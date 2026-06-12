# BiliMusic TODO

## Current Status

- [x] Real-device playback is stable.
- [x] QR login works on device.
- [x] Search playback works on device.
- [x] Lock-screen playback and controls work on device.
- [x] Local cache works, including offline playback after disabling network.
- [ ] AltStore renewal flow still needs to be verified.

## P6 Polish

- [x] Shift the UI direction toward Apple Music.
  - Shared Apple Music red accent and system background theme.
  - Player actions use a compact symbol bar instead of label-heavy controls.
  - Home, Search, Favorites, Cache, Settings, Queue, and picker sheets use native grouped list styling.
- [x] Add favorite toggle from the player.
  - Uses the last opened Bilibili favorite folder as the default target.
  - Supports add/remove for the currently playing track.
- [x] Add selectable favorite target from the player.
  - Short press favorites to the default folder.
  - Long press opens a folder picker and remembers the selected folder as the new default.
- [x] Restore the last opened favorite folder by default.
  - Favorites tab re-enters the last folder after loading the folder list.
- [x] Reduce search UI stutter.
  - Cancels stale search tasks.
  - Moves result mapping/filtering off the main actor.
  - Preloads top search results after results arrive.
- [x] Reduce blank delay when tapping a new song.
  - Preloads cid/playurl for the next few visible tracks.
  - Reuses short-lived prepared stream URLs while they are fresh.
- [x] Fix immediate player UI layout problems.
  - Player cover now adapts to viewport size.
  - Favorite/cache actions moved into compact icon controls.
- [x] Fix real-device player sheet layout clipping.
  - Removed large spacer-driven layout.
  - Player page now uses a stable scrollable vertical layout so cover/title/controls stay visible.
- [ ] Add playback history.
  - Persist recently played tracks locally.
  - Show a compact history section or page.
  - Let tapping a history item start playback.
- [ ] Improve queue management.
  - [x] Show the current queue in the full player.
  - [x] Support jumping to a queued track.
  - [x] Support removing queued tracks.
  - [x] Support appending tracks from UP playlists.
- [ ] Verify UP playlists on device.
  - Player has a "合集" entry for the current track's UP owner.
  - Uses public season/series playlists from the UP space.
  - Bilibili API shape may need adjustment after real-account testing.
- [ ] Verify lyrics on device.
  - Uses LRCLIB online synced lyrics first.
  - Falls back to Bilibili subtitle files when no online lyric match exists.
  - Shows a clear empty state when no lyric source matches.
  - Confirm matching is conservative enough to avoid wrong song variants.
- [ ] Verify Music/MV switching on device.
  - Player has a native segmented "音乐 / MV" switch.
  - MV mode uses a stable MP4 stream and resumes near the current timestamp.
  - Switching back to music should resume audio near the same timestamp.
  - Wi-Fi playback can default to MV mode via Settings.
  - Entering background from MV mode switches to pure music and should keep lock-screen playback alive.
- [ ] Add sleep timer.
  - Presets: 15, 30, 45, 60 minutes.
  - Stop playback when the timer ends.
  - Show remaining time in the player or settings.
- [ ] Improve error states.
  - Detect expired or invalid Cookie and guide re-login.
  - Show clear messages for missing audio streams, unavailable videos, and network failures.
  - If a radio recommendation fails, skip to another candidate where possible.
- [ ] Further reduce first-play latency if the stream still feels slow.
  - Consider preparing an `AVPlayerItem` for the highlighted/next track, not just fetching playurl.
  - Keep the previous visual state visible while the new item buffers.
- [ ] Improve cache browsing.
  - Add sorting by recently cached, title, artist, size, or quality.
  - Add search/filter for cached tracks.
  - Consider showing cache quality and file size more consistently.

## Recommendation Tuning

- [x] Keep related-video radio as the primary music recommendation path.
- [x] Replace Bilibili home feed with music-only discovery sources.
  - Home now uses current track/cache seeds and related videos first.
  - Falls back to explicit music keyword search instead of generic Bilibili feed.
- [x] Tighten radio filtering beyond duration if needed.
  - Skip already played BVs.
  - Prefer 1-11 minute tracks.
  - Consider filtering titles that look like commentary, movie clips, or game videos.
- [ ] Tune fallback music keywords after real-device use.

## Documentation

- [x] Update architecture docs to reflect the current non-SwiftData implementation.
- [ ] Document the real-device verification checklist.
- [ ] Document AltStore installation and renewal once verified.
