//
//  CarPlay+Playback.swift
//  QQPlayer
//
//  CarPlay 播放相关：播放队列构建、曲目格式兼容过滤、NowPlaying 按钮与模板。
//
import CarPlay
import Foundation
import UIKit

extension CarPlaySceneDelegate {
    // MARK: - Helpers

    func addNowPlayingButton(to template: CPListTemplate) {
        guard let nowPlayingImage = UIImage(systemName: "play.circle.fill") else { return }

        let nowPlayingButton = CPBarButton(image: nowPlayingImage) { [weak self] _ in
            self?.showNowPlaying()
        }
        template.trailingNavigationBarButtons = [nowPlayingButton]
    }

    private func showNowPlaying() {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared
        interfaceController?.pushTemplate(nowPlayingTemplate, animated: true, completion: nil)
    }

    func queueForAllSongs(startingAt index: Int) -> [Track] {
        if let paginatedQueue = try? DatabaseManager.shared.getTracksPaginated(
            limit: maxQueueItems,
            offset: index,
            excludingFormats: incompatibleFormats
        ), !paginatedQueue.isEmpty {
            return paginatedQueue
        }

        return forwardQueue(from: allSongsTracks, startingAt: index)
    }

    func forwardQueue(from tracks: [Track], startingAt index: Int) -> [Track] {
        guard !tracks.isEmpty else { return [] }
        let safeIndex = max(0, min(index, tracks.count - 1))
        let endIndex = min(safeIndex + maxQueueItems, tracks.count)
        return Array(tracks[safeIndex ..< endIndex])
    }

    func isCompatible(track: Track) -> Bool {
        let ext = URL(fileURLWithPath: track.path).pathExtension.lowercased()
        return !incompatibleFormats.contains(ext)
    }

    func getCompatibleTracks(for playlist: Playlist) -> [Track] {
        guard let playlistId = playlist.id else { return [] }

        let playlistItems = (try? AppCoordinator.shared.databaseManager.getPlaylistItems(playlistId: playlistId)) ?? []
        let trackIds = playlistItems.map { $0.trackStableId }
        let allPlaylistTracks = (try? AppCoordinator.shared.databaseManager.getTracksByStableIdsPreservingOrder(trackIds)) ?? []
        return allPlaylistTracks.filter(isCompatible)
    }
}
