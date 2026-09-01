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
    case tracks = "songs"
    case likedSongs = "liked_songs"
    case albums = "albums"
    case artists = "artists"
    case playlists = "playlists"

    var id: String { rawValue }

    /// Localized sidebar title (rawValue is a localization key).
    var title: String { rawValue.localized }

    var icon: String {
        switch self {
        case .tracks: return "music.note.list"
        case .likedSongs: return "heart.fill"
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
    @State private var likedTracks: [Track] = []
    @State private var forceDark: Bool = DeleteSettings.load().forceDarkMode
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
        .toolbar {
            ToolbarItem {
                Button {
                    forceDark.toggle()
                    var settings = DeleteSettings.load()
                    settings.forceDarkMode = forceDark
                    settings.save()
                } label: {
                    Image(systemName: forceDark ? "sun.max.fill" : "moon.fill")
                }
                .help("force_dark_mode".localized)
            }
        }
        .preferredColorScheme(forceDark ? .dark : nil)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FavoritesChanged"))) { _ in
            // 收藏变化后刷新“我喜欢的音乐”列表（含正在展示时的实时移除）
            reloadLikedTracks()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(MacLibrarySection.allCases, selection: $section) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if indexer.isIndexing {
                    ProgressView(value: indexer.indexingProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                    Text(String(format: "indexing_progress".localized, indexer.tracksFound))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        indexer.start()
                    } label: {
                        Label("refresh_library".localized, systemImage: "arrow.clockwise")
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
        case .likedSongs:
            MacTrackListView(
                tracks: likedTracks,
                activeTrackId: player.currentTrack?.stableId,
                isPlaying: player.isPlaying,
                artistNameResolver: resolveArtistName,
                onPlay: playLikedTracks,
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
            loadError = "load_library_failed".localized(with: error.localizedDescription)
            print("❌ macOS reloadLibrary failed: \(error)")
        }
        reloadLikedTracks()
    }

    private func reloadLikedTracks() {
        do {
            let favoriteIds = try AppCoordinator.shared.getFavorites()
            likedTracks = tracks.filter { favoriteIds.contains($0.stableId) }
        } catch {
            print("❌ macOS reloadLikedTracks failed: \(error)")
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

    private func playLikedTracks(_ track: Track) {
        Task {
            await player.playTrack(track, queue: likedTracks)
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
