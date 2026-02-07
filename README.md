# MiniMusic

A lightweight macOS menu bar player for Apple Music. Control playback, search your library and the catalog, manage your queue, and browse playlists — all from a small popover window.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue) ![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple)

## Features

- **Menu bar app** — lives in your menu bar, not the dock
- **Full playback controls** — play/pause, skip, scrub, shuffle
- **Smart search** — searches your library and Apple Music catalog in parallel, with library results prioritized
- **Queue management** — see what's playing now and what's up next
- **Library browser** — quick access to your playlists
- **Global hotkey** — toggle the player from anywhere (default: Option+Space, customizable)
- **Keyboard navigation** — arrow keys, Enter to play, Escape to dismiss

## Requirements

- macOS 26 (Tahoe) or later
- Apple Music subscription (for catalog search and playback)
- Xcode 26+ (to build from source)

## Install

### Download

Grab the latest DMG from the [Releases page](https://github.com/danielhopkins/MiniMusic/releases). Open the DMG and drag MiniMusic to your Applications folder. The app is signed, notarized, and sandboxed — no Gatekeeper warnings.

### From source

```bash
# Clone
git clone https://github.com/danielhopkins/MiniMusic.git
cd MiniMusic

# Generate Xcode project (requires xcodegen)
xcodegen generate

# Build
xcodebuild -project MiniMusic.xcodeproj -scheme MiniMusic -configuration Release -destination 'platform=macOS' build

# Copy to Applications
cp -R ~/Library/Developer/Xcode/DerivedData/MiniMusic-*/Build/Products/Release/MiniMusic.app /Applications/
```

Or open `MiniMusic.xcodeproj` in Xcode and build with Cmd+R.

### Quick dev cycle

```bash
# Build and relaunch in one step
xcodebuild -project MiniMusic.xcodeproj -scheme MiniMusic -destination 'platform=macOS' build && ./relaunch.sh
```

## Usage

1. Launch MiniMusic — it appears as an icon in your menu bar
2. Click the menu bar icon or press **Option+Space** to open the player
3. Grant Apple Music access when prompted
4. Search, browse, and play

## Architecture

Built with SwiftUI and the modern `@Observable` pattern (no Combine-based `ObservableObject`).

```
MiniMusic/
├── App/                    # Entry point
├── Models/                 # AppState, SearchResultItem
├── ViewModels/             # PlayerViewModel, MusicSearchViewModel
├── Views/                  # PlayerView, SearchView, QueueView, LibraryView, SettingsView
└── Utilities/              # MusicAuthManager, HotkeyNames
```

### Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration |
| [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | Menu bar window visibility control |

## License

MIT
