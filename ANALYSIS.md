# Cosmos Music Player 架构分析报告

> 只读分析（2026-08-29），基于当前仓库状态（git log 仅 1 个 commit: 1.2.4）。
> 统计口径：77 个 Swift 文件，约 34,199 行（含 Widget/Share/Siri 扩展与测试）。

---

## 1. 技术栈

**一句话**：Swift 6 单仓库 Xcode 工程（无 Tuist/project.yml），仅两个 SPM 依赖（GRDB + SFBAudioEngine），iOS 18.5+，服务层全部单例。

| 项 | 值 |
|---|---|
| Swift 版本 | 主 App **Swift 6.0**（严格并发），Widget/Share/Siri 扩展 Swift 5.0；工程级默认 5.0 |
| iOS 最低部署 | **18.5**（全部 target）；CosmosSiriTests 测试 target 为 **27.0**（用 iOS 27 的 AppIntentsTesting/MediaIntents） |
| 构建方式 | **xcodeproj 直接构建**，无 project.yml/Package.swift；Xcode 16 的 folder-synchronized groups（文件自动纳入 target） |
| SPM 依赖 | ① **GRDB.swift**（upToNextMajorVersion，SQLite ORM）② **SFBAudioEngine 0.13.0**（exactVersion，sbooth，FLAC/Opus/Vorbis/DSD 解码 + 元数据读写） |
| 系统框架 | AVFoundation/AVFAudio、SwiftUI、UIKit、Intents/AppIntents、CarPlay（CPTemplate）、WidgetKit、UniformTypeIdentifiers、CryptoKit、ImageIO |
| Target 清单 | Cosmos Music Player（主 App）、PlayerWidgetExtension、Share（SLComposeServiceViewController）、SiriIntentsExtension（legacy SiriKit）、CosmosSiriTests（XCUITest bundle） |
| Bundle ID | dev.clq.Cosmos-Music-Player |
| 密钥 | .env 模板（Spotify client id/secret、Discogs consumer key/secret），EnvironmentLoader 注入 |

---

## 2. 架构模式

**一句话**：SwiftUI + 服务层单例 + NotificationCenter 事件总线的"轻 MVVM"——没有独立 ViewModel 层（仅 TutorialViewModel 一个），@Published 状态直接挂在 Service 单例上被 View 观察。

- **MVVM 变体**：View（SwiftUI）→ 直接观察 Service 单例（`PlayerEngine.shared`、`ArtworkManager.shared`、`LibraryIndexer.shared`、`EQManager.shared`，均 `ObservableObject` + `@Published`），AppCoordinator 以 `@EnvironmentObject` 注入。没有 ViewModel 层，也没有 Repository 层（DB 操作散在各 Service 里直接调 DatabaseManager）。
- **数据流**：
  1. `AppCoordinator.initialize()`（App 入口 `.task`）→ iCloud 状态检查 → `LibraryIndexer.start()` 扫描 → GRDB 落库 → `@Published tracks` → 各 Screen 刷新；
  2. 播放：`PlayerView`/`MiniPlayerView` 持 `@StateObject playerEngine`，`PlayerEngine.progress`（独立 ObservableObject）以 **10Hz Timer** 驱动进度条/歌词，避免整个播放页高频重建；
  3. 跨组件通信用 **NotificationCenter**：`LibraryNeedsRefresh`、`MinimizePlayer`、`BackgroundColorChanged`、`cosmosSettingsDidChange`（刻意不用 UserDefaults.didChange 避免整库重绘）、`iCloudAuthStatusChanged`、`NavigateToPlaylist`。
- **状态持久化**：设置 `DeleteSettings`（UserDefaults JSON，带 Codable 默认值容错）；曲库 GRDB SQLite；收藏/播放列表/播放器状态双写 iCloud（JSON 文件）与本地 Documents；播放器状态 `PlayerState`（含当前曲、队列、进度、循环/随机开关，列表截断 100 首）。
- **并发**：主 App Swift 6 严格并发，Service 大量 `@MainActor`，耗时 IO 用 `Task.detached`/nonisolated 方法；DB 读写 `DatabaseManager.read/write` 同步封装。
- **坑点意识强**：代码里有大量针对真实场景的注释（CarPlay 下勿重配 audio session、后台 10Hz timer 触发 watchdog、旧版 silent-pause 循环的废除说明等），工程质量高于一般开源播放器。

---

## 3. Services 职责（15 个，一句话版）

| Service | 行数 | 职责 |
|---|---|---|
| **PlayerEngine** | 3308 | 播放内核：AVAudioEngine 原生引擎（FLAC/MP3/WAV/AAC）+ 委托 SFBAudioEngine 双路由、segment 调度、无缝预加载、ReplayGain、EQ 接入、NowPlaying/远程控制、音频会话与后台、播放状态持久化、CarPlay 协同 |
| **LibraryIndexer** | 2719 | 曲库扫描：NSMetadataQuery（iCloud）+ 直接目录扫描（本地）+ 共享容器/外部书签导入，元数据解析（时长/采样率/位深/ReplayGain/嵌入封面），stableId 文件指纹，文件夹自动建播放列表 |
| **DatabaseManager** | 2247 | GRDB 数据访问层：全部曲库 CRUD + 迁移（逐列 ALTER）+ 搜索（归一化分词）+ 去重合并 + 播放列表/收藏/EQ 操作 |
| **LyricsManager** | 893 | 歌词：嵌入元数据提取（FLAC Vorbis/ID3 USLT+SYLT/DSF/AVFoundation）+ lrclib.net 在线获取 + JSON 磁盘缓存（actor 并发安全） |
| **AppCoordinator** | 1366 | 服务编排器：初始化流程、iCloud 状态机、索引调度、收藏/播放列表云同步、SiriKit legacy 意图处理（INPlayMedia/INAddMedia）、对外统一业务 API |
| **StateManager** | 577 | iCloud + 本地 JSON 状态同步（FavoritesState/PlaylistState/PlayerState），原子写、损坏文件隔离、预暖 iCloud 容器 |
| **ArtworkManager** | 987 | 封面提取（嵌入元数据/文件头手工解析 FLAC/ID3/DSF）+ 内存 NSCache + 磁盘缓存 + 缩略图 + stableId→hash 映射 |
| **EQManager** | 558 | 图形 EQ：预设管理（导入 GraphicEQ 文本 / 手动 16 段）、AVAudioEngine 与 SFB 双后端运行时频率/增益 |
| **HybridMusicAPI** | 414 | 艺术家信息门面：Spotify 优先 → Discogs 兜底，统一 UnifiedArtist 模型 + 磁盘缓存 + "wrong artist" 切换 |
| **SpotifyAPI** | 395 | Spotify OAuth2 客户端凭据流，艺术家 profile/图片 |
| **DiscogsAPI** | 376 | Discogs 消费者凭据签名，艺术家 profile/图片 |
| **CloudDownloadManager** | 675 | iCloud Drive 文件按需落地（ensureLocal）：NSMetadataQuery 监控下载进度、失败检测（连续 3 次熔断）、鉴权联动 |
| **FileCleanupManager** | 349 | 曲库一致性：扫描后对比成功枚举的根目录，删除已消失文件并清理封面缓存（防 iCloud 鉴权失败误删） |
| **PlaybackRouter** | 110 | 播放策略路由：按扩展名 + M4A 内 Opus 探测，决定 native AVAudioFile / SFB AudioDecoder |
| **SFBAudioEngineManager** | 1212 | SFBAudioEngine 封装：Opus/Vorbis/DSD 播放、DSD→PCM/DoP、EQ 处理图附加、外部 DAC 检测、CarPlay 格式兼容、后台优化 |

---

## 4. 数据模型

### DatabaseModels.swift（GRDB 记录类型）
- **Artist**: `id, name`（NOCASE）
- **Album**: `id, artistId, title, year, albumArtist`
- **Track**: `id, stableId(唯一), albumId, artistId, title, trackNo, discNo, durationMs, sampleRate, bitDepth, channels, path, fileSize, modificationDate(微秒指纹), replaygainTrackGain/AlbumGain/TrackPeak/AlbumPeak, hasEmbeddedArt`
- **Favorite**: `trackStableId`（主键）
- **Playlist**: `id, slug(唯一), title, createdAt, updatedAt, lastPlayedAt, folderPath, isFolderSynced, lastFolderSync, customCoverImagePath`
- **PlaylistItem**: `playlistId, position, trackStableId`（复合主键）
- **EQPreset/EQBand/EQSettings**: 预设（imported/manual 类型）+ 频段（frequency/gain/bandwidth/bandIndex）+ 全局开关
- 另有 `IdentifiedTrackRow`（ForEach 重复曲目安全 ID）、多对多 `track_artist` 表、`deleted_folder_playlist` 墓碑表
- 多歌手支持：track/album 通过 `track_artist` 关联多 Artist

### SettingsModels.swift（UserDefaults，`DeleteSettings`）
- 外观：`minimalistIcons, backgroundColorChoice(8 色), forceDarkMode`
- 音频：`dsdPlaybackMode(auto/pcm/dop)`
- 曲库：`deleteFromLibraryOnly, lastLibraryScanDate, autoCreateFolderPlaylists`
- 播放器：`showLyricsButton, showSleepTimerButton`（默认关）
- 首页：`homeSections`（6 个 section 可见性 + 排序，可拖动）
- 排除曲目：`ExcludedTrackStableIds`（仅从曲库删除不删文件）

### StateModels.swift（iCloud 同步 JSON）
- `FavoritesState`（version/updatedAt/favorites[stableId]）
- `PlaylistState`（slug/title/items[trackId+addedAt]）

### 播放器状态（StateManager 内 PlayerState）
- 当前曲/队列/currentIndex/播放时间/播放中/循环模式/随机 + 恢复逻辑

---

## 5. 歌词功能（重点）

- **格式**：**LRC（句级时间轴）**——`[mm:ss]` / `[mm:ss.xx]` / `[mm:ss.xxx]` 均支持；无时间戳的纯文本歌词也支持。**没有逐字（word-level/卡拉OK）时间轴**——`LyricsLine` 只有 `timestamp + text` 两个字段，模型层就不支持逐字。
- **来源（三级）**：
  1. **嵌入元数据**：FLAC Vorbis comment（SYNCEDLYRICS/SYNCLYRICS/LYRICS/UNSYNCEDLYRICS）、MP3 ID3（USLT 非同步 + **SYLT 同步帧**，支持 ISO-8859-1/UTF-16/UTF-16BE/UTF-8 编码）、DSF 内嵌 ID3、OGG/OPUS 文本扫描、AVFoundation metadata 兜底（`©lyr`/`uslt`/lyrics 键）；
  2. **lrclib.net 在线 API**：先 `/get` 精确匹配（曲名+艺术家+专辑+时长），纯文本则再 `/search` 找带时间轴版本（时长 ±2s 优先，synced 优先）；
  3. **磁盘缓存**：`Documents/lyrics-cache/<stableId>.json`（启动全量载入内存）。
- **UI（LyricsView，全屏模态）**：
  - **逐句同步滚动 + 高亮**：当前句放大加粗白色（26pt），邻句 19pt，远处 16pt 递减透明度；ScrollViewReader `scrollTo(anchor: .center)` + spring 动画；
  - **禁用手动滚动**（`.disabled(true)`，纯自动），**没有点击歌词跳转播放**；
  - 纯文本歌词滚动阅读模式、乐器曲目/无歌词空态、加载态；顶部/底部渐隐遮罩；毛玻璃背景。
- 触发入口：播放页歌词按钮（设置里可隐藏），`showLyricsSheet` 时异步加载。

---

## 6. 播放引擎（重点）

- **底层**：**双引擎**。
  - 原生：`AVAudioEngine` + `AVAudioPlayerNode` 自定义 segment 调度（`scheduleSegment(from:file:)`，seek 后按 frame 位置重排），**无缝衔接**（预加载下一曲 + `nextTimelineStartSampleTime` 连续调度）、ReplayGain 增益、AVAudioUnitEQ 接入、10Hz 播放计时器；
  - 委托：**SFBAudioEngine**（`AudioDecoder`/`AudioPlayer`）处理 Opus/Vorbis/OGG/DSD（DSF/DFF，含 DSD→PCM 与 DoP 输出、外部 DAC 检测）；SFB 失败时 DSD 可回退原生引擎；
  - `PlaybackRouter` 按扩展名 + M4A 内 Opus 签名探测选路。
- **队列模型**：`playbackQueue: [Track]` + `currentIndex` + `originalQueue`（随机时保存原序，关闭恢复）+ 预加载 next（`nextTrack/nextAudioFile/nextTrackIndex`）；循环三态：**关 → 队列循环(isRepeating) → 单曲循环(isLoopingSong)**；随机：当前曲锚定后洗牌。
- **倍速播放**：**无**。全代码库无 playbackRate/速度控制。
- **AB 循环 / 区间循环**：**无**。只有整曲单曲循环；引擎已有 `seek(to:)` + frame 级调度，做 AB 有基础。
- **睡眠定时器**：**有**。播放页 Menu 按钮：15/30/45/60 分钟 + 取消（设置里 `showSleepTimerButton` 开关，默认隐藏）；实现为 Task 睡眠后暂停，非精确到曲末。
- **其他**：锁屏 NowPlaying + MPRemoteCommandCenter 全控制、后台播放/音频会话中断恢复/路由变化/MediaServices 重置/内存警告全链路处理、播放状态持久化（杀进程恢复）、Spotify 式 affinity 意图（AppIntents）。

---

## 7. UI 功能面

**页面清单（Views/）**：

| 分组 | 页面 |
|---|---|
| Library | `LibraryView`（首页：6 个可排序 section 列表）、`AllSongsScreen`、`LikedSongsScreen`、`TrackListView`（排序/批量操作）、`SearchView`（全库搜索）、`MusicFilePicker`（文件导入） |
| Albums | `AlbumsScreen`、`AlbumDetailScreen`、`AlbumTrackRowView` |
| Artists | `ArtistsScreen`、`ArtistDetailScreen`（Discogs/Spotify 艺术家简介）、`ArtistAlbumCardView` |
| Playlists | `PlaylistsScreen`、`PlaylistCardView`（封面拼贴）、`PlaylistDetailScreen`、`PlaylistListView`、`PlaylistSelectionView`、`PlaylistManagementView`、`AIPlaylistSheet`（智能歌单生成） |
| Player | `PlayerView`（全屏播放页）、`MiniPlayerView`（底部迷你条+进度）、`QueueManagementView`（队列管理）、`LyricsView`、`WaveformView`（装饰）、`TrackRowView` |
| Utility | `SettingsView`（外观/EQ/DSD/播放器开关/首页 section 排序）、`EQSettingsView`（EQ 预设 + 图形编辑 + GraphicEQ 导入）、`BackgroundTextureView`（渐变背景）、`InitializationView/OfflineStatusView/ErrorView` |
| 其他 | `TutorialView`（首次启动引导）、ContentView（根容器 + Lifecycle/Overlay/Sheet 三个 Modifier） |

**播放页布局（PlayerView）自上而下**：封面大图（左右滑动切歌、点击最小化、三张相邻封面 3D 效果）→ 标题/艺术家 → 进度条（InteractiveProgressBar 可拖动 seek + 当前/总时长）→ 主控制行（随机/上一曲/播放暂停/下一曲/循环，毛玻璃圆角容器）→ 附加控制行（队列/睡眠定时器/歌词/AirPlay 按钮，可伸缩布局）→ 底部 MiniPlayer（封面+标题+进度条+播放按钮）。

---

## 8. 本地化

- **4 语言：en / fr / ru / zh-Hans**，各 307 条 key（文件 385-389 行），**zh-Hans 全覆盖、与英文完全对齐**，含 AppIntentVocabulary.plist（Siri 意图词表）。
- 机制：`Localized` 静态访问器（NSLocalizedString 包装）+ `String.localized(with:)` 格式化；新增文案需在 4 个 strings 文件同步加 key。
- CarPlay 界面仅英/法（README 声明），zh-Hans 主要是主 App UI。

---

## 9. 测试

- **只有 1 个测试 target：CosmosSiriTests**（XCUITest bundle，deployment iOS 27，用 `AppIntentsTesting` 框架跨 IPC 驱动真实 App 的 App Intents）。
- **13 个用例**：
  - `EntityQueryTests`（5）：Song/Album/Artist/Playlist 字符串查询、Spotlight 标识符回环；
  - `IntentExecutionTests`（7）：ResumePlayback、FavoriteCurrentSong、PlaySong、PlaySong+插队、Like/Unset 往返、AddToPlaylist、GenerateMix（空库/无播放列表自动 XCTSkip）；
  - `SpotlightTests`（1）：清除/重建 Spotlight 索引往返。
- **没有单元测试 target**：PlayerEngine、LyricsManager、DatabaseManager、LibraryIndexer 等核心逻辑均无单测；业务逻辑正确性主要靠运行时日志（print 打点非常密集，代码里有一套"诊断文化"）。

---

## 10. 差距清单（对照后续需求）

> 改动量评估：小 ≤2 天 · 中 1-2 周 · 大 ≥2 周（单人 iOS 开发估算）

| # | 需求 | 现状 | 改动量 |
|---|---|---|---|
| 1 | **逐句跟唱模式** | 已有句级 LRC 时间轴 + 播放进度驱动高亮/自动滚动管线（LyricsView 全套）。需加：跟唱交互态（句级进度/当前句操作）、可能做逐字对齐（模型层需新增 word-level 数据，或客户端按字匀速推算）、句子定位按钮。**引擎侧无需大改** | **中**（UI+交互为主，LyricsLine 模型扩展小） |
| 2 | **AB 循环** | 无。但引擎是 frame 级 segment 调度 + 现成 `seek(to:)`，最简实现：播放计时器里 `playbackTime >= B → seek(to: A)`，原生/SFB 双路都要实现；UI 加 A/B 标记按钮 + 状态显示。注意 seek 会 `clearPreloadedNext()`（不影响同曲内循环） | **小-中** |
| 3 | **倍速播放** | 无任何实现。原生路 `AVAudioPlayerNode.playbackRate`（需同步处理 playbackTime 采样时钟与 seek 偏移，现有 `seekTimeOffset`+nodeTime 计算要适配 rate）；SFB 路 `AudioPlayer` 需查证 rate 支持。UI 加速率菜单（0.5-2.0x） | **中** |
| 4 | **单句循环** | 无。本质 = 取当前歌词行起止时间做 AB 循环 + UI 按钮；依赖 #1/#2 的能力（行边界已可从 syncedLyrics 拿到） | **中**（与 AB 循环共享引擎改动） |
| 5 | **局域网连接桌面主机同步曲库/歌词/封面** | **完全空白**：全库无 Bonjour/NetService、无本地 HTTP 服务、无 NWListener，网络层只有 URLSession 出站 API 调用；也无增量同步协议。**可复用资产**：stableId 文件指纹（天然去重/增量依据）、GRDB 曲库、歌词/封面磁盘缓存结构、FileCleanupManager 的"枚举根目录对账"思路。需新建：发现（Bonjour）、传输（HTTP 大文件断点）、同步协议（曲库 diff + 文件 + 歌词 + 封面）、后台任务、权限（Local Network 弹窗） | **大** |
| 6 | **离线下载管理** | 现有 `CloudDownloadManager` 只管 iCloud Drive 文件按需落地（ensureLocal + NSMetadataQuery 进度），不是"下载曲库到本地"的通用下载器。若指从桌面主机/在线源下载：需新建下载队列（任务/暂停/断点/存储配额），落库可复用 `upsertTrack`，索引可复用 `processExternalFile` | **中-大** |
| 7 | **阅读器（EPUB 有声书）** | 全新领域。可复用：PlayerEngine 播音频（有声书即音频文件）、播放状态持久化、LyricsManager 式的时间轴对齐（若做逐段朗读高亮）。需新建：EPUB 解析（新 SPM 依赖或自研）、书籍模型/书架、章节导航、音频-文本段落对齐、阅读 UI（字号/翻页）、与播放队列融合 | **大** |
| 8 | **词典** | 全新功能，无任何基础设施。接在线词典 API：URLSession 基建现成，小；本地词库/离线查词：需新依赖与存储设计，大。**无离线词库经验可复用** | **小-大**（取决于方案） |
| 9 | **在线歌曲搜索下载** | 有 SpotifyAPI（OAuth2 客户端凭据，但只用于艺术家信息）；无歌曲搜索下载通道、无下载管理器（见 #6）。导入侧现成：文件进曲库目录即被索引（`importMusicFiles`/`processExternalFile`）。需：搜索 API 集成 + 下载队列 + 版权/格式策略 | **中-大** |
| 10 | **标签刮削** | 部分现成：HybridMusicAPI（Discogs/Spotify 艺术家信息）、ArtworkManager（封面提取缓存）、元数据**读取**（LibraryIndexer 解析）。缺：曲目级标签刮削（Discogs 有 track 接口可扩）、**标签写回文件**（SFBAudioEngine 能写元数据，需封装）、DB 更新联动、批量 UI | **中** |
| 11 | **睡眠定时器** | **已有**（15/30/45/60 分钟 + 取消，设置可显隐）。如需增强（自定义时长、"播完当前曲停止"、到点渐弱）是小改 | **小**（已满足基础需求） |

---

## 汇报摘要

- **技术栈一句话**：Swift 6（严格并发）iOS 18.5+ 单 xcodeproj 工程，仅 GRDB + SFBAudioEngine 两个 SPM 依赖，AVFoundation 原生引擎 + SFBAudioEngine 双引擎播放。
- **架构一句话**：SwiftUI + 服务层全单例（@Published 直出状态）+ NotificationCenter 事件总线 + GRDB SQLite 的轻 MVVM，AppCoordinator 管编排不管导航。
- **可复用亮点 3-5 条**：
  1. **双引擎播放内核**：无缝衔接 + ReplayGain + EQ + 全链路后台/中断/路由处理（3300 行 PlayerEngine + 1200 行 SFB 封装），是所有音频功能的稳固地基；
  2. **stableId 文件指纹 + GRDB 幂等曲库**：天然支持去重/增量/迁移，做同步、下载、刮削都能直接落库；
  3. **歌词管线完整**：多格式嵌入解析（含 SYLT 同步帧）+ lrclib.net + 磁盘缓存，句级时间轴模型干净，跟唱/单句循环的"地基"已有；
  4. **元数据多源兜底 + 双层缓存**（封面：嵌入→Spotify→Discogs；ArtworkManager 内存+磁盘），标签刮削可在此上扩展；
  5. **全套系统集成**：CarPlay、Widget、Share、legacy SiriKit + iOS 27 AppIntents（schema intent + Spotlight 索引）+ 四语言本地化，工程质量与防御式注释水平高。
- **关键差距 5-8 条（带改动量）**：
  1. 无倍速播放（中）；
  2. 无 AB/区间循环（小-中，引擎 seek/segment 基础现成）；
  3. 歌词无逐字时间轴、无点击跳转，跟唱需扩模型+交互（中）；
  4. 局域网同步完全空白——无 Bonjour/HTTP 服务/传输协议（大）；
  5. 无通用下载管理（现有 CloudDownloadManager 仅 iCloud 落地）（中-大）；
  6. EPUB 阅读器/有声书全新领域（大）；
  7. 词典全新（小-大视方案）；
  8. 无标签写回文件能力（读有、写无）（中）；
  9. 睡眠定时器已有（满足）；单测为零，仅 13 个 App Intents 集成测试（补测试，中）。
