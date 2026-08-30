//
//  MacLibraryView.swift
//  QQPlayer
//
//  macOS main window: NavigationSplitView with a library sidebar, a track
//  list (or album/artist/playlist grid), and the player detail page.
//  QQPlayerMac target only — kept out of the iOS target via pbxproj
//  membership exceptions.
//

import Combine
import SwiftUI

enum MacLibrarySection: String, CaseIterable, Identifiable {
    case tracks = "歌曲"
    case albums = "专辑"
    case artists = "艺术家"
    case playlists = "播放列表"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tracks: return "music.note.list"
        case .albums: return "square.stack"
        case .artists: return "music.mic"
        case .playlists: return "list.bullet.rectangle"
        }
    }
}

struct MacLibraryView: View {
    @StateObject private var player = PlayerEngine.shared
    @StateObject private var indexer = LibraryIndexer.shared
    @StateObject private var progress = PlayerEngine.shared.progress

    @State private var section: MacLibrarySection = .tracks
    @State private var tracks: [Track] = []
    @State private var albums: [Album] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var loadError: String?
    @State private var selectedAlbum: Album?
    @State private var selectedArtist: Artist?
    @State private var albumTracks: [Track] = []
    @State private var artistTracks: [Track] = []
    @State private var selectedTrackId: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            contentList
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 600)
        } detail: {
            MacPlayerView(
                track: player.currentTrack,
                artistName: currentArtistName,
                isPlaying: player.isPlaying,
                duration: player.duration,
                playbackTime: progress.playbackTime,
                onPlayPause: togglePlayPause,
                onNext: { Task { await player.nextTrack(autoplay: true) } },
                onPrevious: { Task { await player.previousTrack(autoplay: true) } },
                onSeek: { time in
                    Task { await player.seek(to: time) }
                }
            )
        }
        .navigationTitle("QQPlayer")
        .frame(minWidth: 1000, minHeight: 640)
        .task {
            reloadLibrary()
            if !indexer.isIndexing {
                indexer.start()
            }
            player.ensureRemoteCommandsSetup()
        }
        .onReceive(indexer.$isIndexing) { isIndexing in
            if !isIndexing {
                reloadLibrary()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(MacLibrarySection.allCases, selection: $section) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if indexer.isIndexing {
                    ProgressView(value: indexer.indexingProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                    Text("索引中… \(indexer.tracksFound) 首")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        indexer.start()
                    } label: {
                        Label("刷新音乐库", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentList: some View {
        switch section {
        case .tracks:
            MacTrackListView(
                tracks: tracks,
                activeTrackId: player.currentTrack?.stableId,
                isPlaying: player.isPlaying,
                artistNameResolver: resolveArtistName,
                onPlay: playFromTrackList,
                onSelect: { selectedTrackId = $0.stableId }
            )
        case .albums:
            MacAlbumGridView(
                albums: albums,
                selectedAlbum: $selectedAlbum,
                albumTracks: $albumTracks,
                artistNameResolver: resolveArtistName,
                onPlayAlbum: playAlbum
            )
        case .artists:
            MacArtistListView(
                artists: artists,
                selectedArtist: $selectedArtist,
                artistTracks: $artistTracks,
                artistNameResolver: resolveArtistName,
                onPlayArtist: playArtist
            )
        case .playlists:
            MacPlaylistListView(
                playlists: playlists,
                onOpen: openPlaylist
            )
        }
    }

    // MARK: - Data

    private func reloadLibrary() {
        do {
            tracks = try DatabaseManager.shared.getAllTracks()
            albums = try DatabaseManager.shared.getAllAlbums()
            artists = try DatabaseManager.shared.getAllArtists()
            playlists = try DatabaseManager.shared.getAllPlaylists()
            loadError = nil
        } catch {
            loadError = "加载音乐库失败：\(error.localizedDescription)"
            print("❌ macOS reloadLibrary failed: \(error)")
        }
    }

    private func resolveArtistName(for track: Track) -> String? {
        try? DatabaseManager.shared.getArtistDisplayName(
            forTrackStableId: track.stableId,
            fallbackArtistId: track.artistId
        )
    }

    private var currentArtistName: String? {
        guard let track = player.currentTrack else { return nil }
        return resolveArtistName(for: track)
    }

    // MARK: - Playback actions

    private func playFromTrackList(_ track: Track) {
        Task {
            await player.playTrack(track, queue: tracks)
        }
    }

    private func playAlbum(_ album: Album, tracks albumTracks: [Track]) {
        guard let first = albumTracks.first else { return }
        Task {
            await player.playTrack(first, queue: albumTracks)
        }
    }

    private func playArtist(_ artist: Artist, tracks artistTracks: [Track]) {
        guard let first = artistTracks.first else { return }
        Task {
            await player.playTrack(first, queue: artistTracks)
        }
    }

    private func openPlaylist(_ playlist: Playlist) {
        do {
            let items = try DatabaseManager.shared.getPlaylistItems(playlistId: playlist.id ?? 0)
            let stableIds = items.map { $0.trackStableId }
            let tracks = try DatabaseManager.shared.getTracksByStableIdsPreservingOrder(stableIds)
            guard let first = tracks.first else { return }
            Task {
                await player.playTrack(first, queue: tracks)
            }
        } catch {
            print("❌ openPlaylist failed: \(error)")
        }
    }

    private func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
}
