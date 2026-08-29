# QQPlayer (iOS)

> **fork 声明**：本项目基于 [Cosmos Music Player](https://github.com/clquwu/Cosmos-Music-Player)（GPL-3.0，作者 Raphael Boullay Le Fur）二次开发，详见 [NOTICE.md](NOTICE.md)。本仓库整体以 GPL-3.0 发布。

---

# QQPlayer 🎵

---

QQPlayer 是一款高品质音乐播放器，同时支持 iCloud Drive 同步与本地存储，让用户可以灵活地管理自己的音乐。应用专为 iOS 与 Apple 生态打造，完整支持 CarPlay。

一款为 iOS 打造的发烧级音乐播放器，支持 FLAC、WAV、M4A、MP3、Opus、OGG、DSD、DSF 等格式，具备 Apple CarPlay、DSD 播放（DoP 与 PCM 转换）、双存储方案（iCloud / 本地）、歌单管理、歌手信息整合、图形均衡器与多语言支持等高级特性。

## 功能 ✨

### 🚗 Apple CarPlay 集成
- **完整 CarPlay 支持**：为车内安全音乐控制提供原生 CarPlay 界面
- **标签页导航**：快速访问全部歌曲、收藏、歌单与浏览等分区
- **专辑封面展示**：高质量封面，支持 aspect-fill 裁剪与占位图
- **正在播放界面**：完整的播放控制，包括播放/暂停、切歌与进度拖动
- **无缝同步**：手机与 CarPlay 之间播放状态实时同步
- **多语言支持**：CarPlay 界面完整本地化

### 🎧 音频播放
- **高品质无损支持**：原生支持无损 FLAC、WAV 音频文件，以及 MP3
- **图形均衡器**：基于文本的 GraphicEQ 支持，实现精确的音频定制
- **自定义 EQ 配置**：配置并保存多套 GraphicEQ 设置
- **Siri 集成**：通过语音控制音乐播放
- **ReplayGain 支持**：自动音量归一化，带来一致的听感
- **内嵌封面**：从 FLAC、MP3、WAV 元数据中读取并展示专辑封面
- **高级音频引擎**：基于 AVFoundation 构建，保证最优音质

### 📚 音乐库管理
- **双存储支持**：可选 iCloud Drive（跨设备同步）或本地存储（仅限本机）
- **iCloud Drive 集成**：使用 iCloud 存储时音乐文件自动跨设备同步
- **本地文件支持**：完整支持存储在 App Documents 文件夹中的音乐文件
- **智能曲库索引**：自动发现并索引来自两种存储位置的音乐文件
- **元数据提取**：从 FLAC、MP3、WAV 文件中读取歌手、专辑、标题等元数据
- **离线优先**：本地文件完全离线可用，无需联网

### 👤 歌手信息
- **双 API 集成**：整合 Discogs 与 Spotify API，获取全面的歌手资料
- **歌手档案**：丰富的歌手生平与信息
- **高清图片**：歌手照片与专辑封面
- **备选来源**："歌手不对？"功能可切换数据来源
- **智能缓存**：高效缓存系统，支持离线访问

### 🎤 Siri 语音控制
- **完整语音集成**：通过 Siri 语音命令控制音乐播放
- **智能识别**：对歌单与歌曲名称支持模糊匹配，容忍发音差异
- **完整控制**：可通过语音播放收藏、歌单、指定歌曲或全部音乐
- **无缝体验**：合理的队列管理与播放状态同步

#### 支持的 Siri 命令

**英文命令：**
- "Hey Siri, play my music on QQPlayer"
- "Hey Siri, play my favorites on QQPlayer"
- "Hey Siri, play [playlist name] on QQPlayer"
- "Hey Siri, play [song name] on QQPlayer"

**法文命令：**
- "Dis Siri, joue ma musique sur QQPlayer"
- "Dis Siri, joue mes favoris sur QQPlayer"
- "Dis Siri, joue la playlist [nom] sur QQPlayer"
- "Dis Siri, joue [nom de chanson] sur QQPlayer"

### 🌍 国际化
- **多语言支持**：简体中文、繁体中文、英文、法文、俄文
- **界面本地化**：完整的 UI 翻译系统
- **文化适配**：正确的复数形式与日期格式
- **易于扩展**：模块化系统，可方便地添加新语言

### ☁️ 存储方案
- **iCloud Drive**：音乐、收藏与歌单跨设备自动同步
- **本地存储**：音乐直接存放在设备本地，无需 iCloud
- **灵活选择**：两种存储方式可同时混用
- **离线模式**：无网络时功能完整可用（尤其配合本地文件）
- **智能降级**：优雅处理网络连接异常
- **认证管理**：使用云端功能时提供稳健的 iCloud 认证

## 技术架构 🏗️

### 核心组件

#### 服务层
- **AppCoordinator**：应用主协调器，管理所有服务与初始化
- **PlayerEngine**：高级音频播放引擎，支持后台播放与 GraphicEQ 处理
- **DatabaseManager**：基于 SQLite/GRDB 的本地数据库，支持迁移
- **StateManager**：iCloud 状态同步与本地持久化
- **LibraryIndexer**：自动发现与索引音乐文件

#### API 集成
- **DiscogsAPI**：从 Discogs 数据库获取丰富的歌手信息
- **SpotifyAPI**：基于 OAuth2 认证的备选歌手数据
- **HybridMusicAPI**：服务之间的智能回退机制

#### 数据管理
- **CloudDownloadManager**：处理 iCloud Drive 文件操作
- **FileCleanupManager**：管理从 iCloud Drive 删除文件的本地清理
- **ArtworkManager**：从两种存储类型中提取并缓存专辑封面

### 数据库结构

```sql
-- 歌手表
CREATE TABLE artist (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL COLLATE NOCASE
);

-- 专辑表
CREATE TABLE album (
    id INTEGER PRIMARY KEY,
    artist_id INTEGER REFERENCES artist(id) ON DELETE CASCADE,
    title TEXT NOT NULL COLLATE NOCASE,
    year INTEGER,
    album_artist TEXT COLLATE NOCASE
);

-- 曲目表
CREATE TABLE track (
    id INTEGER PRIMARY KEY,
    stable_id TEXT NOT NULL UNIQUE,
    album_id INTEGER REFERENCES album(id) ON DELETE SET NULL,
    artist_id INTEGER REFERENCES artist(id) ON DELETE SET NULL,
    title TEXT NOT NULL COLLATE NOCASE,
    track_no INTEGER,
    disc_no INTEGER,
    duration_ms INTEGER,
    sample_rate INTEGER,
    bit_depth INTEGER,
    channels INTEGER,
    path TEXT NOT NULL,
    file_size INTEGER,
    replaygain_track_gain REAL,
    replaygain_album_gain REAL,
    replaygain_track_peak REAL,
    replaygain_album_peak REAL,
    has_embedded_art INTEGER DEFAULT 0
);

-- 收藏表
CREATE TABLE favorite (
    track_stable_id TEXT PRIMARY KEY
);

-- 歌单表
CREATE TABLE playlist (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_played_at INTEGER DEFAULT 0
);

-- 歌单条目表
CREATE TABLE playlist_item (
    playlist_id INTEGER REFERENCES playlist(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    track_stable_id TEXT NOT NULL,
    PRIMARY KEY (playlist_id, position)
);
```

## 安装说明 🚀

### 环境要求
- **Xcode**：最新稳定版（建议 Xcode 15+）
- **Swift**：6+
- **iOS 部署目标**：iOS 18.5+
- **Git**：用于版本管理
- **有效的 Apple 开发者账号**：使用 iCloud 能力所必需
- **真机设备**：物理 iOS 设备（测试 iCloud 功能所必需）

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone git@github.com:daxmate/qqplayer-ios.git
   cd qqplayer-ios
   ```

2. **配置环境变量**
   - 复制 `.env.template` 为 `.env`
   - 填入你的 API 凭据：
   ```bash
   SPOTIFY_CLIENT_ID=your_spotify_client_id
   SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
   DISCOGS_CONSUMER_KEY=your_discogs_consumer_key
   DISCOGS_CONSUMER_SECRET=your_discogs_consumer_secret
   ```

3. **申请 API Key**

   **Spotify API Key：**
   - 访问 [Spotify Developer Dashboard](https://developer.spotify.com/dashboard/applications)
   - 创建一个新应用
   - 将 Client ID 与 Client Secret 复制到 `.env` 文件

   **Discogs API Key：**
   - 访问 [Discogs Developer Settings](https://www.discogs.com/settings/developers)
   - 创建一个新应用
   - 将 Consumer Key 与 Consumer Secret 复制到 `.env` 文件

4. **配置 iCloud**
   - 确保你的 Apple 开发者账号已开通 iCloud 能力
   - 应用使用容器：`iCloud.com.daxmate.qqplayer.ios`
   - 如需修改，请在工程设置中更新 Bundle Identifier

5. **构建并运行**
   - 在 Xcode 中打开 `QQPlayer.xcodeproj`
   - 选择你的开发团队
   - 在真机上构建并运行（iCloud 功能需要真机）

### 首次启动设置

1. **登录 iCloud**（可选）：仅当需要跨设备同步时才登录
2. **添加音乐**：选择你偏好的存储方式：
   - **iCloud Drive**：将音乐文件放入 "iCloud Drive → QQPlayer" 文件夹
   - **本地存储**：将音乐文件放入 "我的 iPhone → QQPlayer" 文件夹
3. **曲库同步**：应用会自动检测并索引两个位置的音乐
4. **开始使用**：创建歌单，尽情欣赏你的音乐！

## 使用指南 📱

### 添加音乐

你有两种存储方式可选：

#### 方式一：iCloud Drive（跨设备同步）
1. 打开 iOS 设备上的"文件"应用
2. 进入 "iCloud Drive" → "QQPlayer"
3. 将 FLAC、MP3 或 WAV 音乐文件放入此文件夹
4. 文件将同步到登录同一 iCloud 账号的所有设备

#### 方式二：本地存储（仅限本机）
1. 打开 iOS 设备上的"文件"应用
2. 进入 "我的 iPhone" → "QQPlayer"
3. 将 FLAC、MP3 或 WAV 音乐文件放入此文件夹
4. 文件仅保留在本设备（无需 iCloud）

**混合存储**：两种方式可以同时使用——应用会从两个位置自动发现并索引音乐！

### 使用图形均衡器
1. **进入 EQ**：在正在播放界面点击均衡器图标
2. **输入 GraphicEQ 文本**：以文本格式输入你的 GraphicEQ 设置
3. **应用设置**：保存自定义的 GraphicEQ 配置
4. **多套配置**：创建并在多套 GraphicEQ 设置之间切换
5. **开关切换**：随时启用或停用均衡器，且不丢失设置

GraphicEQ 格式允许你针对特定频率做增益调节，实现精确的音频控制。

### 创建歌单
1. 在歌单分区点击 "+" 按钮
2. 输入歌单名称
3. 从曲库中添加歌曲
4. 歌单自动跨设备同步

### 查看歌手信息
1. 在曲库中进入任意歌手
2. 查看来自 Discogs/Spotify 的丰富歌手资料
3. 点击"歌手不对？"切换数据来源
4. 歌手数据会缓存，可离线查看

### 使用 Siri 语音控制
1. **启用 Siri**：确保设备设置中已开启 Siri
2. **授予权限**：在弹窗中允许 QQPlayer 使用 Siri
3. **语音命令**：使用上文列出的任意支持的命令
4. **智能匹配**：不用担心发音是否标准——应用对名称使用模糊匹配

### 语言设置
应用自动跟随设备的语言设置。目前支持：
- 简体中文（zh-Hans）
- 繁体中文（zh-Hant）
- 英文（en）
- 法文（fr）
- 俄文（ru）

## 依赖 📦

### Swift 包
- **GRDB**：SQLite 数据库管理
- **Foundation**：核心系统框架
- **AVFoundation**：音频播放引擎与音频处理
- **SwiftUI**：现代 UI 框架
- **Combine**：响应式编程

### API 服务
- **Spotify Web API**：歌手信息与元数据
- **Discogs API**：综合音乐数据库
- **iCloud Drive API**：跨设备同步

## 目录结构 📂

```
QQPlayer/
├── Services/           # 核心业务逻辑服务
│   ├── AppCoordinator.swift
│   ├── PlayerEngine.swift
│   ├── EQManager.swift
│   ├── KaraokeController.swift
│   ├── LyricsManager.swift
│   ├── DatabaseManager.swift
│   ├── StateManager.swift
│   ├── LibraryIndexer.swift
│   ├── SpotifyAPI.swift
│   ├── DiscogsAPI.swift
│   └── HybridMusicAPI.swift
├── Views/              # SwiftUI 视图
│   ├── Library/
│   ├── Artists/
│   ├── Albums/
│   ├── Playlists/
│   ├── Player/
│   ├── Equalizer/
│   └── Utility/
├── ViewModels/         # 视图模型
├── Models/             # 数据模型
│   ├── DatabaseModels.swift
│   ├── StateModels.swift
│   ├── EqualizerModels.swift
│   └── SettingsModels.swift
├── Helpers/            # 工具类
│   ├── LocalizationHelper.swift
│   └── EnvironmentLoader.swift
└── Resources/          # 本地化文件
    ├── zh-Hans.lproj/
    ├── zh-Hant.lproj/
    ├── en.lproj/
    ├── fr.lproj/
    └── ru.lproj/
```

另外还有 `SiriIntentsExtension/`（Siri 意图扩展）、`PlayerWidget/`（小组件）与 `Share/`（分享扩展）等独立 target。

# 参与贡献 🤝

欢迎为本项目贡献代码！请遵循以下准则，共同维护高质量的代码库。

## 环境要求

- **Xcode**：最新稳定版（建议 Xcode 15+）
- **Swift**：6+
- **iOS 部署目标**：iOS 18.5+
- **Git**：用于版本管理
- **真机设备**：物理 iOS 设备（测试 iCloud 功能所必需）

## 开发流程

1. 从 `main` 创建功能分支：
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. 遵循编码规范进行修改

3. 提交更改：
   ```bash
   git add .
   git commit -m "feat: add new feature description"
   ```

4. 推送到你的 fork 并创建 Pull Request

## 编码规范

### Swift 风格
- 遵循 [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- 使用 SwiftLint 保证格式一致（提交前运行 `swiftlint`）
- 尽可能优先使用 `let` 而非 `var`
- 使用有意义的变量与函数名
- 为公开 API 添加文档注释

### 代码组织
- 使用 `// MARK: -` 注释对相关功能分组
- 尽量保持文件不超过 300 行
- 使用扩展按功能组织代码
- 遵循 MVC/MVVM 架构模式

### 示例：
```swift
// MARK: - View Lifecycle
override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
    configureBindings()
}

// MARK: - Private Methods
private func setupUI() {
    // Implementation
}
```

## Pull Request 规范

### 提交之前
- [ ] 代码有完善的文档
- [ ] UI 变更附截图/GIF
- [ ] 在真机上测试过 iCloud 功能
- [ ] 环境变量已正确配置

### PR 描述模板
```markdown
## Description
简要描述改动内容

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tested on iOS device
- [ ] iCloud sync functionality verified
- [ ] API integrations working

## Screenshots
(如有)
```

## 提交信息格式

使用 conventional commits 格式：
```
type(scope): description

feat(auth): add biometric login support
fix(network): resolve timeout issues
docs(readme): update installation instructions
```

类型：`feat`、`fix`、`docs`、`style`、`refactor`、`test`、`chore`

## 问题反馈

报告问题时请包含：
- iOS 版本与设备型号
- Xcode 版本
- Swift 版本
- 复现步骤
- 预期行为与实际行为
- 崩溃日志或错误信息
- 如有可能附上截图
- iCloud 账号状态

## 代码评审流程

1. 所有 PR 至少需要一次评审
2. 及时响应评审意见
3. 保持 PR 聚焦且规模合理
4. 回复评论并按需更新代码
5. 确保所有测试通过且功能在真机上可用

## 重点贡献方向

### 国际化
添加新语言：

1. 在 `Resources/` 中创建新的 `.lproj` 文件夹
2. 复制 `en.lproj/Localizable.strings` 作为模板
3. 将所有字符串翻译为目标语言
4. 如需要，更新 `LocalizationHelper.swift` 以支持区域格式
5. 用新语言测试 UI

### API 集成
添加新的音乐 API：

1. 在 `Services/` 中创建新的服务文件
2. 实现所需协议
3. 更新 `HybridMusicAPI.swift` 接入新服务
4. 添加适当的错误处理与缓存
5. 更新环境变量文档

### 音频处理
增强音频功能：

1. 扩展 `PlayerEngine.swift` 实现核心音频功能
2. 更新 `EQManager.swift` 实现 EQ 相关功能
3. 确保实时处理保持音频质量
4. 使用各种音频格式与采样率测试
5. 记录新增的音频处理能力

感谢你的贡献！🚀

## 安全与隐私 🔒

- **灵活存储**：音乐文件存储在设备本地或用户个人的 iCloud Drive
- **用户自主**：完全掌控音乐文件的存储位置（本地或云端）
- **API Key**：通过环境变量安全加载
- **无追踪**：不收集或追踪任何用户数据
- **离线优先**：无需联网即可完整使用（尤其配合本地存储）
- **加密同步**：iCloud 同步使用 Apple 端到端加密
- **无外部服务器**：音乐文件永远不会离开你的设备/iCloud 账号

## 疑难排查 🔧

### 常见问题

**音乐不显示：**
- iCloud 文件：检查 iCloud Drive 是否已启用并登录
- 本地文件：确认文件位于本地的 "QQPlayer" 文件夹
- 确认文件为 FLAC、MP3 或 WAV 格式
- 尝试在应用内手动同步
- 同时检查 iCloud Drive 与 "我的 iPhone" 两个位置

**歌手信息缺失：**
- 检查网络连接
- 确认 API Key 配置正确
- 尝试"歌手不对？"功能切换备选来源

**均衡器不生效：**
- 确认均衡器已启用（开关打开）
- 检查音频输出是否被外部限制（耳机安全音量、音量上限等）
- 应用自定义设置前先尝试重置为预设
- 若更改未立即生效，重启播放

**歌单同步异常：**
- 确认 iCloud Drive 有足够存储空间
- 检查设备网络连接
- 尝试退出并重新登录 iCloud

**Siri 不工作：**
- 确认设置 → Siri 与搜索中已启用 Siri
- 在弹窗中允许 QQPlayer 使用 Siri
- 尝试说出 "QQPlayer" 帮助 Siri 识别应用
- 重启应用刷新 Siri 词库
- 首次配置 Siri 时确保设备联网

## 环境变量 🔧

运行本项目需要在 `.env` 文件中添加以下环境变量：

```bash
# Spotify API Keys (Required)
SPOTIFY_CLIENT_ID=your_spotify_client_id
SPOTIFY_CLIENT_SECRET=your_spotify_client_secret

# Discogs API Keys (Required)
DISCOGS_CONSUMER_KEY=your_discogs_consumer_key
DISCOGS_CONSUMER_SECRET=your_discogs_consumer_secret
```

### 获取 API Key

**Spotify API Key：**
- 访问 [Spotify Developer Dashboard](https://developer.spotify.com/dashboard/applications)
- 创建一个新应用
- 将 Client ID 与 Client Secret 复制到 `.env` 文件

**Discogs API Key：**
- 访问 [Discogs Developer Settings](https://www.discogs.com/settings/developers)
- 创建一个新应用
- 将 Consumer Key 与 Consumer Secret 复制到 `.env` 文件

## 附录 📋

我们使用 Spotify 和 Discogs 获取歌手详情，使用 LRCLIB 获取同步歌词。我们与这些服务没有任何经济关联——只是想为你提供最好的使用体验。

### 致谢 🎨

- **歌词 API**：特别感谢 [LRCLIB](https://github.com/tranxuanthang/lrclib) 项目（作者 tranxuanthang）
- **Logo 设计**：由 **Zerrotic** 创作（Discord 用户名 zerrotic）
- **App Store 截图**：由 **MrVedakkaN** 设计（Discord 用户名 mrvedakkan）

## 作者 👥

- [@clquwu](https://github.com/clquwu) - 上游（Cosmos Music Player）主要开发者
- 本项目由 daxmate 基于 Cosmos Music Player 二次开发维护

## 联系方式 📧

上游作者：
- **邮箱**：raphaelboullaylefur@proton.me
- **Discord**：clarityhs

## 支持 💬

遇到问题、疑问或功能需求：
- 在仓库中提交 issue
- 查阅上方疑难排查章节
- 确保安装的是最新版本
- 如需直接联系上游，可通过邮箱或 Discord

## 许可证 📄

本项目基于 GNU GPL-3.0 许可发布，详见 [LICENSE](LICENSE) 文件。

---

**祝你享受 QQPlayer 带来的高品质音乐体验！** 🎵✨
