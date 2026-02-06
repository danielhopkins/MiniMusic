# MiniMusic — macOS Menu Bar Apple Music Player

## Goal

Build a lightweight macOS menu bar app that streams Apple Music without requiring the Music.app to be open. Native Swift/SwiftUI using MusicKit.

## Requirements

- macOS 13+ (Ventura or later for full MusicKit support)
- Swift 5.9+, SwiftUI
- Xcode project with MusicKit entitlement (`com.apple.developer.musickit`)
- User must have an active Apple Music subscription
- App lives in the menu bar (no dock icon, no main window)

## Architecture

```
MiniMusic/
├── MiniMusicApp.swift          # App entry point, MenuBarExtra
├── Views/
│   ├── PlayerView.swift        # Main popover: now playing, controls, volume
│   ├── SearchView.swift        # Search Apple Music catalog
│   ├── QueueView.swift         # Current queue display
│   └── LibraryView.swift       # User library: playlists, recent
├── ViewModels/
│   ├── PlayerViewModel.swift   # Wraps ApplicationMusicPlayer, playback state
│   └── MusicSearchViewModel.swift # Catalog search logic
├── Models/
│   └── AppState.swift          # Shared app state, auth status
├── Utilities/
│   └── MusicAuthManager.swift  # MusicAuthorization.request() handling
└── Assets.xcassets/
```

## Key Implementation Details

### 1. App Shell (MiniMusicApp.swift)

- Use `MenuBarExtra` with `systemImage: "music.note"` for the menu bar icon.
- Set `LSUIElement = true` in Info.plist to hide from the Dock.
- Use `.menuBarExtraStyle(.window)` to get a popover-style panel (not just a menu).

### 2. Auth (MusicAuthManager.swift)

- On first launch, call `MusicAuthorization.request()`.
- Handle `.authorized`, `.denied`, `.restricted`, `.notDetermined` states.
- Show appropriate messaging if denied/restricted.

### 3. Player (PlayerViewModel.swift)

- Use `ApplicationMusicPlayer.shared` — NOT `SystemMusicPlayer` (that one controls Music.app).
- `ApplicationMusicPlayer` automatically integrates with macOS Now Playing / media keys / Control Center. No manual `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter` setup is needed.
- Observe `ApplicationMusicPlayer.shared.state` for playback status.
- Observe `ApplicationMusicPlayer.shared.queue.currentEntry` for current track info.
- Expose play/pause, skip forward, skip back, volume control.
- Display current track name, artist, album, artwork.

### 4. Search (MusicSearchViewModel.swift)

- Use `MusicCatalogSearchRequest` to search songs, albums, artists, playlists, stations.
- Debounce search input (~300ms).
- Display results in a scrollable list.
- Tapping a result sets the player queue and starts playback.

### 5. Queue (QueueView.swift)

- Display `ApplicationMusicPlayer.shared.queue.entries`.
- Allow removing items from queue.
- Show what's playing next.

### 6. Library (LibraryView.swift)

- Use `MusicLibraryRequest` to fetch user's playlists and recently played.
- Allow playing a playlist or album directly.

### 7. Artwork

- `MusicKit` provides `Artwork` objects on tracks/albums. Use `.url(width:height:)` to get image URLs.
- Display artwork in the now playing view using `AsyncImage`.

## UI Layout (PlayerView)

The popover should be compact (~320x400pt):

```
┌─────────────────────────────┐
│  🔍 Search...               │  ← text field, switches to SearchView
├─────────────────────────────┤
│                             │
│      [ Album Artwork ]      │  ← ~120x120
│                             │
│    Song Title               │
│    Artist — Album           │
│                             │
│   ⏮    ▶︎/⏸    ⏭           │  ← playback controls
│   ───────●──────────        │  ← progress scrubber
│   🔈 ─────────●── 🔊       │  ← volume slider
├─────────────────────────────┤
│  ▸ Queue (3 up next)        │  ← expandable / navigates to QueueView
│  ▸ Library                  │  ← navigates to LibraryView
├─────────────────────────────┤
│  ⚙ Settings     ⏏ Quit     │
└─────────────────────────────┘
```

## Keyboard Shortcuts

- `Space` — play/pause (within the popover)
- `Cmd+F` — focus search
- `Cmd+Q` — quit
- Media keys (play/pause, next, prev) are handled automatically by MusicKit.

## Build Steps

1. Create a new Xcode project: macOS > App, SwiftUI lifecycle.
2. In Signing & Capabilities, add the MusicKit entitlement.
3. Set `LSUIElement` to `YES` in Info.plist (hides dock icon).
4. Implement in this order: Auth → Player → Now Playing UI → Controls → Search → Queue → Library.
5. Test with a real Apple Music subscription (MusicKit doesn't work in Simulator for playback).

## Known Considerations

- `ApplicationMusicPlayer` requires a real Apple Music subscription at runtime.
- If Music.app is also open, there may be media key contention — `ApplicationMusicPlayer` should take priority as the active audio session.
- MusicKit catalog search is rate-limited by Apple; debounce user input.
- The app needs to be code-signed with the MusicKit entitlement to function. Ad-hoc signing during development works if provisioning is set up.

## Out of Scope (for now)

- Lyrics display
- AirPlay output selection
- Scrobbling / Last.fm integration
- Global hotkeys (beyond system media keys)
