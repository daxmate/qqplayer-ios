//  PlayerEngine+SFB.swift
//  QQPlayer
//
//  SFBAudioEngine integration for PlayerEngine.
//
//  SFBAudioEngine playback is delegated to SFBAudioEngineManager (see
//  SFBAudioEngineManager.swift and its extensions); the original
//  "MARK: - SFBAudioEngine Integration" section in PlayerEngine carries only
//  this comment, preserved here for continuity.
//
import Foundation

extension PlayerEngine {
    // NOTE: startSilentPlaybackForPause() used to live here. It looped a
    // near-silent buffer forever (numberOfLoops = -1) so the process would not
    // be suspended while paused. That defeated the whole point of pausing: the
    // audio route stayed powered and the app kept running indefinitely. Pausing
    // now simply lets the app suspend. Playback control while suspended is
    // handled by MPRemoteCommandCenter, which iOS resumes us to service.
    // stopSilentPlaybackForPause() is retained so a player left running by a
    // previously-installed build is torn down on the next pause/stop.

    // MARK: - SFBAudioEngine Integration
    // SFBAudioEngine now handles playback directly via SFBAudioEngineManager

}
