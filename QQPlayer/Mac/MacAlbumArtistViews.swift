//
//  MacAlbumArtistViews.swift
//  QQPlayer
//
//  macOS album grid, artist list, and playlist list (content columns for the
//  专辑 / 艺术家 / 播放列表 sections). QQPlayerMac target only.
//

import SwiftUI

// MARK: - Albums

struct MacAlbumGridView: View {
    let albums: [Album]
    @Binding var selectedAlbum: Album?
    @Binding var albumTracks: [Track]
    let artistNameResolver: (Track) -> String?
    let onPlayAlbum: (Album, [Track]) -> Void

    @State private var showAlbumSheet = false

    private let gridColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(albums, id: \.id) { album in
                    Button {
                        openAlbum(album)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.18))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "square.stack")
                                        .font(.system(size: 28))
                                        .foregroundColor(.secondary)
                                )
                            Text(album.title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(album.albumArtist ?? String(format: "track_count".localized, albumTrackCount(album)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showAlbumSheet) {
            if let album = selectedAlbum {
                MacAlbumDetailSheet(
                    album: album,
                    tracks: albumTracks,
                    artistNameResolver: artistNameResolver,
                    onPlay: { onPlayAlbum(album, albumTracks) }
                )
            }
        }
    }

    private func openAlbum(_ album: Album) {
        do {
            let tracks = try DatabaseManager.shared.getTracksByAlbumId(album.id ?? 0)
            albumTracks = tracks
            selectedAlbum = album
            showAlbumSheet = true
        } catch {
            print("❌ openAlbum failed: \(error)")
        }
    }

    private func albumTrackCount(_ album: Album) -> Int {
        (try? DatabaseManager.shared.getTracksByAlbumId(album.id ?? 0).count) ?? 0
    }
}

struct MacAlbumDetailSheet: View {
    let album: Album
    let tracks: [Track]
    let artistNameResolver: (Track) -> String?
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(album.title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("play".localized) { onPlay() }
                    .keyboardShortcut(.return)
                Button("close".localized) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            List(tracks, id: \.stableId) { track in
                HStack {
                    Text(track.title)
                        .lineLimit(1)
                    Spacer()
                    Text(artistNameResolver(track) ?? "")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(MacTimeFormat.format(duration(for: track)))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
        .padding()
    }

    private func duration(for track: Track) -> TimeInterval {
        guard let ms = track.durationMs else { return 0 }
        return Double(ms) / 1000.0
    }
}

// MARK: - Artists

struct MacArtistListView: View {
    let artists: [Artist]
    @Binding var selectedArtist: Artist?
    @Binding var artistTracks: [Track]
    let artistNameResolver: (Track) -> String?
    let onPlayArtist: (Artist, [Track]) -> Void

    @State private var showArtistSheet = false

    var body: some View {
        List(artists, id: \.id) { artist in
            Button {
                openArtist(artist)
            } label: {
                HStack {
                    Image(systemName: "music.mic")
                        .foregroundColor(.secondary)
                    Text(artist.name)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "track_count".localized, artistTrackCount(artist)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showArtistSheet) {
            if let artist = selectedArtist {
                MacArtistDetailSheet(
                    artist: artist,
                    tracks: artistTracks,
                    artistNameResolver: artistNameResolver,
                    onPlay: { onPlayArtist(artist, artistTracks) }
                )
            }
        }
    }

    private func openArtist(_ artist: Artist) {
        do {
            let tracks = try DatabaseManager.shared.getTracksByArtistId(artist.id ?? 0)
            artistTracks = tracks
            selectedArtist = artist
            showArtistSheet = true
        } catch {
            print("❌ openArtist failed: \(error)")
        }
    }

    private func artistTrackCount(_ artist: Artist) -> Int {
        (try? DatabaseManager.shared.getTracksByArtistId(artist.id ?? 0).count) ?? 0
    }
}

struct MacArtistDetailSheet: View {
    let artist: Artist
    let tracks: [Track]
    let artistNameResolver: (Track) -> String?
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(artist.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("play".localized) { onPlay() }
                    .keyboardShortcut(.return)
                Button("close".localized) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            List(tracks, id: \.stableId) { track in
                HStack {
                    Text(track.title)
                        .lineLimit(1)
                    Spacer()
                    Text(albumTitle(for: track))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(MacTimeFormat.format(duration(for: track)))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 480, minHeight: 360)
        }
        .padding()
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

// MARK: - Playlists

struct MacPlaylistListView: View {
    let playlists: [Playlist]
    let onOpen: (Playlist) -> Void

    var body: some View {
        List(playlists, id: \.id) { playlist in
            Button {
                onOpen(playlist)
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(.secondary)
                    Text(playlist.title)
                        .lineLimit(1)
                    Spacer()
                    if let itemCount = try? DatabaseManager.shared.getPlaylistItems(playlistId: playlist.id ?? 0).count {
                        Text(String(format: "track_count".localized, itemCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
