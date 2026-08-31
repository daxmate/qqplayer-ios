//
//  MacTrackListView.swift
//  QQPlayer
//
//  macOS track list (content column for the 歌曲 section). QQPlayerMac target only.
//

import SwiftUI

struct MacTrackListView: View {
    let tracks: [Track]
    let activeTrackId: String?
    let isPlaying: Bool
    let artistNameResolver: (Track) -> String?
    let onPlay: (Track) -> Void
    let onSelect: (Track) -> Void

    @State private var selectedRows = Set<String>()

    private var rows: [MacTrackRow] {
        tracks.map { MacTrackRow(id: $0.stableId, track: $0) }
    }

    var body: some View {
        if tracks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("音乐库为空")
                    .font(.title3)
                Text("点击左下角「刷新音乐库」扫描 ~/Music/QQPlayer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(rows, selection: $selectedRows) {
                TableColumn("#") { row in
                    if row.track.stableId == activeTrackId {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .foregroundColor(.accentColor)
                    } else {
                        Text("\(row.track.trackNo.map(String.init) ?? "")")
                            .foregroundColor(.secondary)
                    }
                }
                .width(32)

                TableColumn("标题") { row in
                    Text(row.track.title)
                        .fontWeight(row.track.stableId == activeTrackId ? .semibold : .regular)
                        .lineLimit(1)
                }

                TableColumn("艺术家") { row in
                    Text(artistNameResolver(row.track) ?? "")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                TableColumn("专辑") { row in
                    Text(albumTitle(for: row.track))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                TableColumn("时长") { row in
                    Text(MacTimeFormat.format(duration(for: row.track)))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .width(56)
            }
            // forSelectionType 必须传 selection 集合的元素类型（即行的 ID 类型），
            // 不能传数据元素类型——传元素类型时 macOS 上 contextMenu 整个不注册
            // （右键不弹、双击 primaryAction 不触发）。三个 macOS 开源项目
            // （Petrichor/Pearcleaner/Clop）均为 .ID.self 用法。
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first,
                   let track = tracks.first(where: { $0.stableId == id }) {
                    Button("播放") {
                        onPlay(track)
                    }
                }
            } primaryAction: { selectedIDs in
                if let id = selectedIDs.first,
                   let track = tracks.first(where: { $0.stableId == id }) {
                    onPlay(track)
                    onSelect(track)
                }
            }
        }
    }

    private func albumTitle(for track: Track) -> String {
        guard let albumId = track.albumId,
              let album = try? DatabaseManager.shared.read({ db in
                  try Album.fetchOne(db, key: albumId)
              }) else {
            return ""
        }
        return album.title
    }

    private func duration(for track: Track) -> TimeInterval {
        guard let ms = track.durationMs else { return 0 }
        return Double(ms) / 1000.0
    }
}
