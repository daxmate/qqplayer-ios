//
//  AppCoordinator+iCloud.swift
//  QQPlayer
//
//  iCloud 同步/状态机/文件协调：容器状态检查、收藏同步、歌单云恢复/写回、
//  索引完成后的 iCloud 收尾、widget 歌单数据刷新。
//
import Foundation
#if os(iOS)
    import UIKit
    import WidgetKit
#endif

extension AppCoordinator {
    // url(forUbiquityContainerIdentifier:) blocks while iCloud sets the
    // container up - seconds on a first install - and Apple's documentation is
    // explicit that it must not be called on the main thread. This whole check
    // therefore runs off the main actor; only the resulting status is published.
    nonisolated func checkiCloudStatus() async -> iCloudStatus {
        // Check if user is signed into iCloud
        guard FileManager.default.ubiquityIdentityToken != nil else {
            writeICloudDiagnostic("notSignedIn: ubiquityIdentityToken == nil")
            return .notSignedIn
        }

        // Check if we can get the container URL. The container root is NOT a
        // "ubiquitous item" — isUbiquitousItem is only true for items explicitly
        // registered via setUbiquitous — so we must not gate on that resource
        // value (it is always false here). The URL existing is sufficient proof
        // the container is usable.
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            writeICloudDiagnostic("containerUnavailable: url(forUbiquityContainerIdentifier:) == nil")
            return .containerUnavailable
        }
        writeICloudDiagnostic("containerURL = \(containerURL.path)")

        print("NSUbiquitousContainers:",
              Bundle.main.object(forInfoDictionaryKey: "NSUbiquitousContainers") ?? "nil")

        // Try to create the app folder
        do {
            let appFolderURL = containerURL.appendingPathComponent("QQPlayer", isDirectory: true)

            if !FileManager.default.fileExists(atPath: appFolderURL.path) {
                try FileManager.default.createDirectory(at: appFolderURL,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                writeICloudDiagnostic("created app folder: \(appFolderURL.path)")
            } else {
                writeICloudDiagnostic("app folder already exists: \(appFolderURL.path)")
            }

            print("iCloud container set up at: \(appFolderURL)")
            return .available
        } catch {
            writeICloudDiagnostic("createDirectory error: \(error)")
            return .error(error)
        }
    }

    /// Writes iCloud diagnostics to Documents/iCloudDiagnostics.txt so we can
    /// see on-device what checkiCloudStatus actually resolved to.
    nonisolated func writeICloudDiagnostic(_ message: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iCloudDiagnostics.txt")
        let line = "[\(Date())] \(message)\n"
        do {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            print("⚠️ Failed to write iCloud diagnostic: \(error)")
        }
    }

    // nonisolated so the blocking work inside - a coordinated iCloud read and
    // the database writes - runs off the main actor. It used to run inline on
    // the main thread during launch, which is a large part of why a first
    // install appeared frozen.
    nonisolated func syncFavorites() async {
        print("🔄 Starting favorites sync...")
        do {
            print("📂 Loading saved favorites from storage...")
            let savedFavorites = try stateManager.loadFavorites()
            print("🗃️ Getting favorites from database...")
            let databaseFavorites = try databaseManager.getFavorites()

            print("📊 Favorites sync - Saved: \(savedFavorites.count), Database: \(databaseFavorites.count)")
            print("📊 Saved favorites: \(savedFavorites)")
            print("📊 Database favorites: \(databaseFavorites)")

            // Only sync if we actually have saved favorites to restore
            if !savedFavorites.isEmpty {
                print("🔄 Restoring saved favorites to database...")
                // One transaction for the whole restore rather than one per track.
                let existing = Set(databaseFavorites)
                let missing = savedFavorites.filter { !existing.contains($0) }
                try databaseManager.addToFavorites(trackStableIds: missing)

                // Get final state after restoration
                print("🔍 Getting final state after restoration...")
                let finalFavorites = try databaseManager.getFavorites()
                print("📊 Final favorites count: \(finalFavorites.count)")
                print("📊 Final favorites list: \(finalFavorites)")

                // Only save if there were actual changes
                if finalFavorites != savedFavorites {
                    print("💾 Saving updated favorites...")
                    try stateManager.saveFavorites(finalFavorites)
                    print("💾 Updated saved favorites")
                } else {
                    print("✅ Favorites already in sync")
                }
            } else if !databaseFavorites.isEmpty {
                // If no saved favorites but database has some, save them
                print("💾 No saved favorites, saving database favorites to storage...")
                try stateManager.saveFavorites(databaseFavorites)
                print("💾 Saved database favorites to storage")
            } else {
                print("📭 No favorites to sync")
            }

        } catch {
            print("❌ Failed to sync favorites: \(error)")
        }

        // Mark initial sync as completed to allow future saves
        await MainActor.run { self.isInitialSyncCompleted = true }
        print("✅ Initial favorites sync completed")
    }

    func handleiCloudAuthenticationError() {
        guard iCloudStatus != .authenticationRequired else { return }

        iCloudStatus = .authenticationRequired
        isiCloudAvailable = false
        showSyncAlert = true

        // Stop any ongoing iCloud operations
        libraryIndexer.switchToOfflineMode()

        // Notify CloudDownloadManager about status change
        NotificationCenter.default.post(name: NSNotification.Name("iCloudAuthStatusChanged"), object: nil)

        print("🔐 iCloud authentication error detected - switched to offline mode")
    }

    func onIndexingCompleted() async {
        do {
            let favorites = try databaseManager.getFavorites()

            // Only save to iCloud if we actually have favorites AND initial sync is completed
            // This prevents overwriting existing iCloud favorites with an empty array during startup
            if !favorites.isEmpty && isInitialSyncCompleted {
                try stateManager.saveFavorites(favorites)
                print("Saved \(favorites.count) favorites to iCloud")
            } else if !isInitialSyncCompleted {
                print("Skipping iCloud save - initial sync not completed yet")
            } else {
                print("Skipping iCloud save - no favorites to save (prevents overwriting existing iCloud data)")
            }

            // Restore playlists from iCloud after indexing is complete
            await restorePlaylistsFromiCloud()

            // Retry once after the first restoration pass
            await retryPlaylistRestoration()

            // Deduplicate playlist items (fixes folder-synced playlists with duplicate entries)
            do {
                try databaseManager.deduplicatePlaylistItems()
            } catch {
                print("⚠️ Failed to deduplicate playlist items: \(error)")
            }

            // Clean up orphaned playlist items
            do {
                try databaseManager.cleanupOrphanedPlaylistItems()
            } catch {
                print("⚠️ Failed to cleanup orphaned playlist items: \(error)")
            }

            // Mark initial indexing as complete
            hasCompletedInitialIndexing = true
            print("✅ Initial indexing completed - playlist sync enabled")

            // Update widget with playlists
            syncPlaylistsToCloud()

            // Run heavier maintenance after UI-critical startup work finishes
            scheduleDeferredPostIndexMaintenance()
        } catch {
            print("Failed to save favorites after indexing: \(error)")
        }
    }

    // Creating the container folder and writing the placeholder files are
    // synchronous iCloud file operations; keep them off the main actor.
    nonisolated func forceiCloudFolderCreation() async {
        do {
            try stateManager.createAppFolderIfNeeded()
            if let folderURL = stateManager.getMusicFolderURL() {
                print("🏗️ iCloud folder created/verified at: \(folderURL)")

                // Create test files to trigger iCloud Drive visibility (as per research)
                let tempFile = folderURL.appendingPathComponent(".qqplayer-placeholder")
                let testFile = folderURL.appendingPathComponent("Welcome.txt")

                let tempContent = "QQPlayer folder - you can delete this file"
                let welcomeContent = "Welcome to QQPlayer!\n\nYou can add your FLAC music files directly to this folder in the Files app.\n\nThe app will automatically detect and index any music files you add here.\n\nEnjoy your music!"

                try tempContent.write(to: tempFile, atomically: true, encoding: .utf8)
                try welcomeContent.write(to: testFile, atomically: true, encoding: .utf8)
                print("📄 Created placeholder and welcome files to ensure folder visibility")
            }
        } catch {
            print("⚠️ Failed to create iCloud folder: \(error)")
        }
    }

    // Reads every playlist file out of the iCloud container and writes the
    // results to the database - all blocking work, so it runs off the main actor.
    nonisolated private func restorePlaylistsFromiCloud() async {
        // Skip if iCloud is not available or authentication required
        guard await isiCloudAvailable, await iCloudStatus == .available else {
            print("⚠️ Skipping playlist restoration - iCloud not available or authentication required")
            return
        }

        do {
            print("🔄 Starting playlist restoration from iCloud...")
            let playlistStates = try stateManager.getAllPlaylists()
            print("📂 Found \(playlistStates.count) playlists in iCloud storage")

            for playlistState in playlistStates {
                // Check if playlist already exists in database
                let existingPlaylists = try databaseManager.getAllPlaylists()

                if let existingPlaylist = existingPlaylists.first(where: { $0.slug == playlistState.slug }) {
                    // Playlist exists - sync tracks from cloud to database
                    print("🔄 Syncing existing playlist from cloud: \(playlistState.title)")

                    guard let playlistId = existingPlaylist.id else { continue }

                    // Skip folder-synced playlists - they manage their own content
                    if existingPlaylist.isFolderSynced {
                        print("📁 Skipping folder-synced playlist: \(playlistState.title)")
                        continue
                    }

                    // Get current tracks in database
                    let currentItems = try databaseManager.getPlaylistItems(playlistId: playlistId)
                    let currentTrackIds = Set(currentItems.map { $0.trackStableId })
                    let cloudTrackIds = Set(playlistState.items.map { $0.trackId })

                    // Only add tracks that are in cloud but not in database
                    // This prevents removing tracks user added locally
                    let tracksToAdd = cloudTrackIds.subtracting(currentTrackIds)

                    if !tracksToAdd.isEmpty {
                        print("➕ Adding \(tracksToAdd.count) missing tracks from cloud to '\(playlistState.title)'")
                        let trackIdsToAdd = Array(tracksToAdd)
                        let existingTrackIds = Set(try databaseManager
                            .getTracksByStableIds(trackIdsToAdd)
                            .map { $0.stableId })

                        for trackId in trackIdsToAdd {
                            if existingTrackIds.contains(trackId) {
                                try databaseManager.addToPlaylist(playlistId: playlistId, trackStableId: trackId)
                                print("✅ Added track to playlist: \(trackId)")
                            } else {
                                print("⚠️ Track not found in database: \(trackId)")
                            }
                        }
                    } else {
                        print("✅ Playlist '\(playlistState.title)' is already in sync")
                    }
                } else {
                    // Playlist doesn't exist - create it
                    print("➕ Restoring new playlist: \(playlistState.title)")
                    let playlist = try databaseManager.createPlaylist(title: playlistState.title)

                    // Add tracks to playlist if they exist in the database
                    guard let playlistId = playlist.id else { continue }

                    let cloudTrackIds = playlistState.items.map { $0.trackId }
                    let existingTrackIds = Set(try databaseManager
                        .getTracksByStableIds(cloudTrackIds)
                        .map { $0.stableId })

                    for trackId in cloudTrackIds where existingTrackIds.contains(trackId) {
                        try databaseManager.addToPlaylist(playlistId: playlistId, trackStableId: trackId)
                        print("✅ Added track to playlist: \(trackId)")
                    }
                }
            }
            print("✅ Playlist restoration completed")
        } catch {
            print("❌ Failed to restore playlists from iCloud: \(error)")

            // Check if this is an authentication error
            if let stateError = error as? StateManagerError, stateError == .iCloudNotAvailable {
                print("🔐 StateManager authentication error - switching to offline mode")
                await handleiCloudAuthenticationError()
            }
        }
    }

    // Same as restorePlaylistsFromiCloud: iCloud reads plus per-track database
    // writes, so it must not hold the main actor.
    nonisolated private func retryPlaylistRestoration() async {
        // Skip if iCloud is not available or authentication required
        guard await isiCloudAvailable, await iCloudStatus == .available else {
            print("⚠️ Skipping retry playlist restoration - iCloud not available or authentication required")
            return
        }

        do {
            print("🔄 Retrying playlist restoration after database fixes...")
            let playlistStates = try stateManager.getAllPlaylists()
            let existingPlaylists = try databaseManager.getAllPlaylists()

            for playlistState in playlistStates {
                if let existingPlaylist = existingPlaylists.first(where: { $0.slug == playlistState.slug }),
                   let playlistId = existingPlaylist.id {
                    // Check if playlist is empty and try to restore tracks
                    let currentItems = try databaseManager.getPlaylistItems(playlistId: playlistId)
                    if currentItems.isEmpty {
                        print("🔄 Playlist '\(playlistState.title)' is empty, attempting to restore tracks...")

                        let cloudTrackIds = playlistState.items.map { $0.trackId }
                        let existingTrackIds = Set(try databaseManager
                            .getTracksByStableIds(cloudTrackIds)
                            .map { $0.stableId })

                        for trackId in cloudTrackIds where existingTrackIds.contains(trackId) {
                            try databaseManager.addToPlaylist(playlistId: playlistId, trackStableId: trackId)
                            print("✅ Added track to playlist after fix: \(trackId)")
                        }
                    } else {
                        print("⚡ Playlist '\(playlistState.title)' already has \(currentItems.count) items")
                    }
                }
            }
            print("✅ Playlist restoration retry completed")
        } catch {
            print("❌ Failed to retry playlist restoration: \(error)")

            // Check if this is an authentication error
            if let stateError = error as? StateManagerError, stateError == .iCloudNotAvailable {
                print("🔐 StateManager authentication error in retry - switching to offline mode")
                await handleiCloudAuthenticationError()
            }
        }
    }

    func syncPlaylistsToCloud() {
        Task { @MainActor in
            // Prevent concurrent sync operations
            guard !isSyncingPlaylists else {
                print("⏭️ Skipping playlist sync - already in progress")
                return
            }

            // Safety: Don't sync until initial indexing is complete
            // This prevents overwriting cloud data with incomplete local data
            guard hasCompletedInitialIndexing else {
                print("⏳ Skipping playlist sync - waiting for initial indexing to complete")
                return
            }

            isSyncingPlaylists = true
            defer { isSyncingPlaylists = false }

            do {
                let playlists = try databaseManager.getAllPlaylists()

                // A library with no tracks at all is the signature of a failed
                // scan or an unreadable database - never of the user having
                // curated their way down to zero. Only in that state do we
                // refuse to overwrite the cloud copies. Computed once here
                // rather than per playlist.
                let libraryLooksUnreadable = ((try? databaseManager.getTrackCount()) ?? 0) == 0

                // Sync to iCloud
                for playlist in playlists {
                    guard let playlistId = playlist.id else { continue }

                    // Get playlist items from database
                    let dbPlaylistItems = try databaseManager.getPlaylistItems(playlistId: playlistId)

                    // Validate that tracks still exist before syncing
                    let orderedTrackIds = dbPlaylistItems.map { $0.trackStableId }
                    let existingTrackIds = Set((try? databaseManager.getTracksByStableIds(orderedTrackIds).map { $0.stableId }) ?? [])
                    let validItems = orderedTrackIds
                        .filter { existingTrackIds.contains($0) }
                        .map { ($0, Date()) }
                    let stateItems = validItems

                    // SAFETY CHECK: don't overwrite cloud data when the library
                    // itself looks unreadable, which is the corruption case this
                    // guard exists for.
                    //
                    // It used to trigger for ANY playlist that ended up empty,
                    // which also covered the perfectly ordinary case of the user
                    // deleting every track in a playlist. The cloud copy was then
                    // pinned forever, still listing the deleted tracks, and was
                    // re-mirrored into Documents/qqplayer-playlists on each launch -
                    // so the entries appeared to come back from the dead.
                    // Scoping it to "the whole library is missing" keeps the
                    // corruption protection while letting a genuinely emptied
                    // playlist clear its cloud copy.
                    if !playlist.isFolderSynced && stateItems.isEmpty && libraryLooksUnreadable {
                        if let existingCloudPlaylist = try? stateManager.loadPlaylist(slug: playlist.slug),
                           !existingCloudPlaylist.items.isEmpty {
                            print("⚠️ Skipping sync for '\(playlist.title)' - library is empty but cloud has \(existingCloudPlaylist.items.count) tracks")
                            print("🛡️ This prevents accidental data loss. The cloud version is preserved.")
                            continue
                        }
                    }

                    let playlistState = PlaylistState(
                        slug: playlist.slug,
                        title: playlist.title,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(playlist.createdAt)),
                        items: stateItems
                    )
                    try stateManager.savePlaylist(playlistState)
                }
                print("✅ Playlists synced to iCloud with \(playlists.count) playlists")

                // Update widget playlist data with artwork
                await updateWidgetPlaylists(playlists: playlists)

            } catch {
                print("❌ Failed to sync playlists to iCloud: \(error)")
            }
        }
    }

    private func updateWidgetPlaylists(playlists: [Playlist]) async {
        // Widget playlist data is iOS WidgetKit-only; on macOS this is a no-op.
        #if os(iOS)
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.daxmate.qqplayer.ios"
            ) else {
                print("⚠️ Widget: Failed to get shared container URL")
                return
            }

            // Sort playlists by most recently played (lastPlayedAt descending)
            let sortedPlaylists = playlists.sorted { playlist1, playlist2 in
                return playlist1.lastPlayedAt > playlist2.lastPlayedAt
            }

            // Show only the top 3 most recently played playlists
            let playlistsToShow = Array(sortedPlaylists.prefix(3))
            print("📊 Widget: Showing top 3 most recently played playlists out of \(playlists.count) total")

            var widgetPlaylists: [WidgetPlaylistData] = []

            for playlist in playlistsToShow {
                guard let playlistId = playlist.id else { continue }

                do {
                    // Get playlist items IN ORDER (same as app displays)
                    let playlistItems = try databaseManager.getPlaylistItems(playlistId: playlistId)

                    let orderedTrackIds = playlistItems.map { $0.trackStableId }
                    let orderedTracks = try databaseManager.getTracksByStableIdsPreservingOrder(orderedTrackIds)

                    // Get first 4 tracks for artwork mashup (in correct playlist order)
                    let artworkTracks = Array(orderedTracks.prefix(4))
                    var artworkPaths: [String] = []

                    // Save artwork for each track
                    for (index, track) in artworkTracks.enumerated() {
                        if let artwork = await ArtworkManager.shared.getArtwork(for: track) {
                            let filename = "playlist_\(playlistId)_\(index).jpg"
                            let fileURL = containerURL.appendingPathComponent(filename)

                            // 编码 + 写盘下沉后台线程（主 actor 串行 3 歌单 × 4 曲目
                            // jpegData + write 会阻塞 UI，2026-08-29 审计 #9）
                            let hasData = await withCheckedContinuation { continuation in
                                DispatchQueue.global(qos: .utility).async {
                                    if let artworkData = artwork.jpegData(compressionQuality: 0.8) {
                                        try? artworkData.write(to: fileURL, options: .atomic)
                                        continuation.resume(returning: true)
                                    } else {
                                        continuation.resume(returning: false)
                                    }
                                }
                            }
                            if hasData {
                                artworkPaths.append(filename)
                                print("✅ Widget: Saved artwork '\(track.title)' for playlist '\(playlist.title)' tile \(index)")
                            }
                        }
                    }

                    // Get theme color from settings
                    let settings = DeleteSettings.load()
                    let colorHex = settings.backgroundColorChoice.rawValue

                    let widgetPlaylist = WidgetPlaylistData(
                        id: String(playlistId),
                        name: playlist.title,
                        trackCount: orderedTracks.count,
                        colorHex: colorHex,
                        artworkPaths: artworkPaths,
                        customCoverImagePath: playlist.customCoverImagePath
                    )
                    widgetPlaylists.append(widgetPlaylist)

                } catch {
                    print("❌ Failed to process playlist \(playlist.title): \(error)")
                }
            }

            PlaylistDataManager.shared.savePlaylists(widgetPlaylists)
            print("✅ Widget playlist data updated with \(widgetPlaylists.count) playlists")

            // Force widget to reload immediately
            WidgetCenter.shared.reloadAllTimelines()
            print("🔄 Widget timeline reload triggered")
        #endif
    }
}
