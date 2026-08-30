//
//  AppCoordinator+ImportExport.swift
//  QQPlayer
//
//  歌单数据层（增删改查/文件夹同步）+ 索引后置维护（数据库关系校验、
//  孤儿文件清理、缓存修剪）。
//
import Foundation

extension AppCoordinator {
    func scheduleDeferredPostIndexMaintenance() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await self?.runPostIndexMaintenance()
        }
    }

    private func runPostIndexMaintenance() async {
        print("🔄 AppCoordinator: Starting deferred post-index maintenance...")
        await verifyDatabaseRelationships()
        await fileCleanupManager.checkForOrphanedFiles()
        await pruneCachesForDeletedContent()
        print("✅ AppCoordinator: Deferred post-index maintenance completed")
    }

    /// Drops cached data belonging to content that no longer exists. Deleting a
    /// track removes its database rows, but the artwork it pulled in and the
    /// artist metadata fetched for it used to live on disk forever.
    private func pruneCachesForDeletedContent() async {
        do {
            // Fetching every track is a full table read; keep it off the main
            // actor so maintenance never stutters the UI on a large library.
            let validStableIds = try await Task.detached(priority: .utility) {
                Set(try DatabaseManager.shared.getAllTracks().map(\.stableId))
            }.value

            // An empty library here almost always means the scan failed or the
            // database is unreadable, not that the user deleted everything.
            // Passing an empty set through would erase the entire artwork
            // cache, so treat it the same way the playlist cleanup does.
            guard !validStableIds.isEmpty else {
                print("⚠️ SAFETY: Skipping cache pruning - no tracks in database")
                return
            }

            await ArtworkManager.shared.cleanupOrphanedArtwork(validStableIds: validStableIds)
        } catch {
            print("⚠️ Failed to prune artwork cache: \(error)")
        }

        // Artist metadata is keyed by artist name rather than track id, so it
        // is pruned by age rather than by liveness.
        await DiscogsAPIService.shared.purgeExpiredDiskCache()
        await HybridMusicAPIService.shared.purgeExpiredDiskCache()
    }

    private func verifyDatabaseRelationships() async {
        do {
            print("🔍 Verifying database relationships...")
            let tracks = try databaseManager.getAllTracks()
            let albums = try databaseManager.getAllAlbums()
            let artists = try databaseManager.getAllArtists()

            print("📊 Database stats - Tracks: \(tracks.count), Albums: \(albums.count), Artists: \(artists.count)")

            let validArtistIds = Set(artists.compactMap(\.id))
            let validAlbumIds = Set(albums.compactMap(\.id))

            var tracksWithoutArtist = 0
            var tracksWithoutAlbum = 0
            var invalidArtistRefs = 0
            var invalidAlbumRefs = 0

            for track in tracks {
                // Check artist relationship
                if let artistId = track.artistId {
                    if !validArtistIds.contains(artistId) {
                        invalidArtistRefs += 1
                    }
                } else {
                    tracksWithoutArtist += 1
                }

                // Check album relationship
                if let albumId = track.albumId {
                    if !validAlbumIds.contains(albumId) {
                        invalidAlbumRefs += 1
                    }
                } else {
                    tracksWithoutAlbum += 1
                }
            }

            print("🔍 Verification complete:")
            print("   - Tracks without artist: \(tracksWithoutArtist)")
            print("   - Tracks without album: \(tracksWithoutAlbum)")
            print("   - Invalid artist refs: \(invalidArtistRefs)")
            print("   - Invalid album refs: \(invalidAlbumRefs)")

        } catch {
            print("❌ Failed to verify database relationships: \(error)")
        }
    }

    // MARK: - Playlist operations

    func addToPlaylist(playlistId: Int64, trackStableId: String) throws {
        try databaseManager.addToPlaylist(playlistId: playlistId, trackStableId: trackStableId)
        syncPlaylistsToCloud()
    }

    func removeFromPlaylist(playlistId: Int64, trackStableId: String) throws {
        try databaseManager.removeFromPlaylist(playlistId: playlistId, trackStableId: trackStableId)
        syncPlaylistsToCloud()
    }

    func reorderPlaylistItems(playlistId: Int64, from sourceIndex: Int, to destinationIndex: Int) throws {
        try databaseManager.reorderPlaylistItems(playlistId: playlistId, from: sourceIndex, to: destinationIndex)
        syncPlaylistsToCloud()
    }

    func createPlaylist(title: String) throws -> Playlist {
        let playlist = try databaseManager.createPlaylist(title: title)
        syncPlaylistsToCloud()
        return playlist
    }

    func createFolderPlaylist(title: String, folderPath: String) throws -> Playlist {
        let playlist = try databaseManager.createFolderPlaylist(title: title, folderPath: folderPath)
        syncPlaylistsToCloud()
        return playlist
    }

    func syncPlaylistWithFolder(playlistId: Int64, trackStableIds: [String]) throws {
        try databaseManager.syncPlaylistWithFolder(playlistId: playlistId, trackStableIds: trackStableIds)
        syncPlaylistsToCloud()
    }

    func getFolderSyncedPlaylists() throws -> [Playlist] {
        return try databaseManager.getFolderSyncedPlaylists()
    }

    func isTrackInPlaylist(playlistId: Int64, trackStableId: String) throws -> Bool {
        return try databaseManager.isTrackInPlaylist(playlistId: playlistId, trackStableId: trackStableId)
    }

    func deletePlaylist(playlistId: Int64) throws {
        // Get playlist info before deleting from database
        let playlists = try databaseManager.getAllPlaylists()
        guard let playlist = playlists.first(where: { $0.id == playlistId }) else {
            throw AppCoordinatorError.playlistNotFound
        }

        let playlistSlug = playlist.slug

        // Delete from database
        try databaseManager.deletePlaylist(playlistId: playlistId)

        // Delete from iCloud and local storage
        try stateManager.deletePlaylist(slug: playlistSlug)

        print("✅ Playlist '\(playlist.title)' deleted from database and cloud storage")
    }

    func renamePlaylist(playlistId: Int64, newTitle: String) throws {
        try databaseManager.renamePlaylist(playlistId: playlistId, newTitle: newTitle)
        print("✅ Playlist renamed to '\(newTitle)'")
    }

    func updatePlaylistAccessed(playlistId: Int64) throws {
        try databaseManager.updatePlaylistAccessed(playlistId: playlistId)
    }

    func updatePlaylistLastPlayed(playlistId: Int64) throws {
        try databaseManager.updatePlaylistLastPlayed(playlistId: playlistId)
        // Update widget to show most recently played playlists
        syncPlaylistsToCloud()
    }
}
