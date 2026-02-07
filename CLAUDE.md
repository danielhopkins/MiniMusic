# MiniMusic

## Quick Reference
- **Platform**: macOS 26+
- **Language**: Swift 6.2
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Package Manager**: Swift Package Manager (via XcodeGen)

## Build & Run

- Build: `xcodebuild -project MiniMusic.xcodeproj -scheme MiniMusic -destination 'platform=macOS' build`
- Relaunch app after build: `./relaunch.sh`
- Regenerate Xcode project after changing `project.yml`: `xcodegen generate`

## XcodeBuildMCP Integration
When available, prefer XcodeBuildMCP tools over raw `xcodebuild`:
- Build: `build_macos`
- Run: `build_run_macos`
- Clean: `clean`
- Discover projects: `discover_projs`

## Project Structure
```
MiniMusic/
├── App/                    # MiniMusicApp.swift entry point
├── Models/                 # AppState, SearchResultItem
├── ViewModels/             # PlayerViewModel, MusicSearchViewModel
├── Views/                  # PlayerView, SearchView, QueueView, LibraryView, SettingsView
├── Utilities/              # MusicAuthManager, HotkeyNames
├── Assets.xcassets/
└── Info.plist
```

## Coding Standards

### Swift Style
- Use `async/await` for all async operations
- Follow Apple's Swift API Design Guidelines
- Use `guard` for early exits
- Prefer value types (structs) over reference types (classes) where appropriate
- Default actor isolation is `MainActor` (via `SWIFT_DEFAULT_ACTOR_ISOLATION` build setting) — no need for explicit `@MainActor` annotations on types

### SwiftUI Patterns
- Prefer `@Observable` over `ObservableObject` (macOS 26+ target)
- Use `@State` for view-owned state (works for both value and @Observable types)
- Use `@Environment` for dependency injection (replaces @EnvironmentObject)
- Use `@Bindable` for bindings to @Observable objects
- Extract views when they exceed ~100 lines
- Use `.task { }` for async work tied to view lifecycle

### State Management (Modern Observation)
```swift
// Preferred:
@Observable class MyViewModel { var foo = "" }
// In views: @State var vm = MyViewModel()
// Passed in: @Bindable var vm: MyViewModel
// Environment: @Environment(MyViewModel.self) var vm

// Avoid (legacy Combine pattern):
// class MyViewModel: ObservableObject { @Published var foo = "" }
// @StateObject, @ObservedObject, @EnvironmentObject
```

### Error Handling
- Use typed errors conforming to `LocalizedError`
- Handle MusicKit authorization states gracefully
- Provide user-facing error messages

## App Architecture Notes
- **Menu bar app**: Uses `MenuBarExtra` with `.window` style, `LSUIElement: true`
- **MusicKit**: Uses `ApplicationMusicPlayer.shared` for Apple Music playback
- **Global hotkeys**: Via `KeyboardShortcuts` library (default: Option+Space)
- **Search**: Parallel library + catalog search with 300ms debounce via `TaskGroup`
- **Dependencies**: KeyboardShortcuts (v2.0.0+), MenuBarExtraAccess (v1.0.0+)

## DO NOT
- Use force unwrapping (`!`) without justification
- Use deprecated APIs when modern alternatives exist
- Create massive monolithic views
- Ignore concurrency warnings
