//  PlayerEngine+Queue.swift
//  QQPlayer
//
//  Queue management, playback order modes, shuffle, and loop handling for
//  PlayerEngine.
//
import Foundation

extension PlayerEngine {
    // MARK: - Index Normalization Helper

    func normalizeIndexAndTrack() {
        if playbackQueue.isEmpty {
            currentIndex = 0
            currentTrack = nil
            return
        }

        if let ct = currentTrack,
           let idx = playbackQueue.firstIndex(where: { $0.stableId == ct.stableId }) {
            currentIndex = idx
        } else {
            currentIndex = max(0, min(currentIndex, playbackQueue.count - 1))
            currentTrack = playbackQueue[currentIndex]
        }
    }

    // MARK: - Queue Management

    func playTrack(_ track: Track, queue: [Track] = []) async {
        print("🎵 Playing track: \(track.title)")

        // Restore player state on first interaction if not already done
        await ensurePlayerStateRestored()

        playbackQueue = queue.isEmpty ? [track] : queue
        currentIndex = playbackQueue.firstIndex(where: { $0.stableId == track.stableId }) ?? 0

        // Explicitly set the current track to ensure UI synchronization
        currentTrack = track

        // Save original queue for shuffle functionality
        originalQueue = playbackQueue.map { $0.stableId }

        normalizeIndexAndTrack()

        let loaded = await loadTrack(track)
        guard loaded else { return }

        if usingSFBEngine && isPlaying {
            playbackState = .playing
            startPlaybackTimer()
            updateNowPlayingInfoEnhanced()
            updateWidgetData()
        } else {
            play()
        }
    }

    func nextTrack(autoplay: Bool? = nil) async {
        guard !playbackQueue.isEmpty else { return }
        normalizeIndexAndTrack()
        let shouldAutoplay = autoplay ?? isPlaying

        currentIndex = (currentIndex + 1) % playbackQueue.count
        let next = playbackQueue[currentIndex]
        let loaded = await loadTrack(next, preservePlaybackTime: false)
        guard loaded else { return }

        if shouldAutoplay {
            if usingSFBEngine && isPlaying {
                playbackState = .playing
                startPlaybackTimer()
            } else {
                play()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cancelPendingCompletions()
                self.playerNode.stop()
                self.isPlaying = false
                self.playbackState = .paused
                self.seekTimeOffset = 0
                self.playbackTime = 0
                self.updateNowPlayingInfoEnhanced()
                self.updateWidgetData()
            }
        }
    }

    func previousTrack(autoplay: Bool? = nil) async {
        guard !playbackQueue.isEmpty else { return }
        normalizeIndexAndTrack()

        let wasPlaying = autoplay ?? isPlaying

        if playbackTime > 3.0 {
            await seek(to: 0)
            if !wasPlaying {
                await MainActor.run {
                    isPlaying = false
                    playbackState = .paused
                    updateNowPlayingInfoEnhanced()
                    updateWidgetData()
                }
            }
            return
        }

        currentIndex = currentIndex > 0 ? currentIndex - 1 : playbackQueue.count - 1
        let prev = playbackQueue[currentIndex]
        let loaded = await loadTrack(prev, preservePlaybackTime: false)
        guard loaded else { return }

        if wasPlaying {
            await MainActor.run {
                if usingSFBEngine && isPlaying {
                    playbackState = .playing
                    startPlaybackTimer()
                } else {
                    play()
                }
            }
        } else {
            await MainActor.run {
                cancelPendingCompletions()
                playerNode.stop()
                isPlaying = false
                playbackState = .paused
                seekTimeOffset = 0
                playbackTime = 0
                updateNowPlayingInfoEnhanced()
                updateWidgetData()
            }
        }
    }

    func addToQueue(_ track: Track) {
        playbackQueue.append(track)
    }

    func insertNext(_ track: Track) {
        let insertIndex = currentIndex + 1
        playbackQueue.insert(track, at: min(insertIndex, playbackQueue.count))
    }

    // MARK: - Playback Order Mode

    func cyclePlaybackOrderMode() {
        let nextRaw = (playbackOrderMode.rawValue + 1) % PlaybackOrderMode.allCases.count
        applyPlaybackOrderMode(PlaybackOrderMode(rawValue: nextRaw) ?? .sequential)
    }

    func applyPlaybackOrderMode(_ mode: PlaybackOrderMode) {
        // 这两个 @Published 无副作用，先直接置位
        isRepeating = false
        isLoopingSong = false

        switch mode {
        case .sequential:
            // 关随机 → 恢复原队列
            if isShuffled {
                toggleShuffle()
            }
        case .shuffle:
            // 开随机 → 保存原队列 + 重排
            if !isShuffled {
                toggleShuffle()
            }
        case .repeatAll:
            if isShuffled {
                toggleShuffle()
            }
            isRepeating = true
        case .repeatOne:
            if isShuffled {
                toggleShuffle()
            }
            isLoopingSong = true
        }
    }

    var playbackOrderMode: PlaybackOrderMode {
        if isShuffled {
            return .shuffle
        }
        if isLoopingSong {
            return .repeatOne
        }
        if isRepeating {
            return .repeatAll
        }
        return .sequential
    }

    func cycleLoopMode() {
        if !isRepeating && !isLoopingSong {
            // Off → Queue Loop
            isRepeating = true
            isLoopingSong = false
            print("🔁 Queue loop mode: ON")
        } else if isRepeating && !isLoopingSong {
            // Queue Loop → Song Loop
            isRepeating = false
            isLoopingSong = true
            print("🔂 Song loop mode: ON")
        } else {
            // Song Loop → Off
            isRepeating = false
            isLoopingSong = false
            print("🚫 Loop mode: OFF")
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        print("🔀 Shuffle mode: \(isShuffled ? "ON" : "OFF")")

        if isShuffled {
            // Save original order and shuffle the queue
            originalQueue = playbackQueue.map { $0.stableId }
            shuffleQueue()
        } else {
            // Restore original order
            restoreOriginalQueue()
        }

        normalizeIndexAndTrack()
    }

    private func shuffleQueue() {
        guard !playbackQueue.isEmpty else { return }
        normalizeIndexAndTrack()
        let anchor = playbackQueue[currentIndex]
        var rest = playbackQueue
        rest.remove(at: currentIndex)
        rest.shuffle()
        playbackQueue = [anchor] + rest
        currentIndex = 0

        print("🔀 Queue shuffled, current track remains at index 0")
    }

    private func restoreOriginalQueue() {
        guard !originalQueue.isEmpty else { return }

        do {
            let restoredQueue = try databaseManager.getTracksByStableIdsPreservingOrder(originalQueue)
            guard !restoredQueue.isEmpty else { return }

            // 随机期间增删队列（addToQueue/insertNext 只改 playbackQueue）的曲目
            // 按 stableId 差集补回队尾，否则关闭随机时这些曲目消失
            // （2026-08-29 审计 #5）。
            let restoredIds = Set(restoredQueue.map { $0.stableId })
            let additions = playbackQueue.filter { !restoredIds.contains($0.stableId) }
            let mergedQueue = restoredQueue + additions

            // Find current track in merged queue
            if let currentTrack = self.currentTrack,
               let mergedIndex = mergedQueue.firstIndex(where: { $0.stableId == currentTrack.stableId }) {
                playbackQueue = mergedQueue
                currentIndex = mergedIndex
                print("🔀 Original queue restored, current track at index \(mergedIndex)" +
                    (additions.isEmpty ? "" : ", \(additions.count) shuffled-era additions kept"))
            } else {
                playbackQueue = mergedQueue
                currentIndex = min(currentIndex, max(0, mergedQueue.count - 1))
            }
        } catch {
            print("❌ Failed to restore original queue: \(error)")
        }

        normalizeIndexAndTrack()
    }
}
