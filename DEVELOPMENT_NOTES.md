# Pleb Client Development Notes

## Project Overview
A native Linux Nostr client using Qt/QML for the UI and Rust for the backend, connected via cxx-qt.

**Repository**: https://github.com/PlebOne/Pleb-Client

## Why Qt Instead of Iced
The original project (PlebClient-3) used iced 0.13.1 but had issues:
1. System tray support was problematic (close-to-tray crashed or didn't work)
2. Character boundary panics with emoji in notifications
3. General UI limitations

Qt provides native system tray, better desktop integration, and mature QML for UI.

## Current State (Dec 4, 2025)

### What's Built
- **Rust/Qt bridge** using cxx-qt 0.7.3
  - `AppController` - login, logout, navigation, NWC wallet
  - `FeedController` - feed loading, note interactions
  - `DmController` - DM conversations, NIP-04/NIP-17 support
- **QML UI** (basic scaffold, needs polish)
  - LoginScreen - nsec input
  - FeedScreen - note feed display
  - DmScreen - direct messages
  - ProfileScreen - user profile
  - SettingsScreen - logout, NWC connection
  - NotificationsScreen - placeholder
  - Sidebar - navigation
  - Components: NoteCard, ProfileAvatar

### What Works
- App compiles and launches
- QML loads (with some visual issues)
- Login function is called (logs show it working)
- Property setters are properly using cxx-qt API

### Known Issues
1. **Screen navigation not updating** - Login sets `logged_in=true` and `current_screen="feed"` but UI doesn't change. May be QML binding issue with underscore property names.
2. **Missing icon** - `qrc:/icons/icon.png` not found (cosmetic)
3. **UI visual mess** - QML needs styling work
4. **No actual Nostr functionality** - bridges are stubs, need to integrate nostr-sdk

## Architecture

```
src/
├── main.rs              # Qt app initialization
├── bridge/
│   ├── mod.rs
│   ├── app_bridge.rs    # AppController QObject
│   ├── feed_bridge.rs   # FeedController QObject  
│   └── dm_bridge.rs     # DmController QObject
└── core/
    ├── mod.rs
    ├── config.rs        # App configuration
    └── error.rs         # Error types

qml/
├── Main.qml             # Main window, navigation
├── components/
│   ├── Sidebar.qml
│   ├── NoteCard.qml
│   └── ProfileAvatar.qml
└── screens/
    ├── LoginScreen.qml
    ├── FeedScreen.qml
    ├── DmScreen.qml
    ├── ProfileScreen.qml
    ├── SettingsScreen.qml
    └── NotificationsScreen.qml
```

## Next Steps (Priority Order)

### 1. Fix Navigation Bug
- Debug why `current_screen` property changes don't update StackLayout
- May need to check cxx-qt property naming (underscores vs camelCase)
- Add more console.log debugging in QML

### 2. Implement Actual Login
- Parse nsec using nostr crate
- Store keys securely
- Initialize nostr-sdk Client
- Connect to relays

### 3. Fetch and Display Feed
- Connect to relays on login
- Subscribe to following feed (kind 1 notes)
- Parse events and populate FeedController
- Display in FeedScreen

### 4. System Tray (Primary Goal)
- Add Qt.labs.platform SystemTrayIcon
- Close-to-tray functionality
- Tray menu (show/hide, quit)
- Notification badges

### 5. DMs (NIP-04 and NIP-17)
- Load existing conversations
- Send/receive encrypted messages
- Auto-detect protocol per conversation

### 6. Profile & Settings
- Display user profile
- Edit profile (kind 0)
- Relay management
- NWC wallet connection

## Dependencies
- cxx-qt 0.7.3
- cxx-qt-lib 0.7.3
- nostr-sdk 0.37
- nostr 0.37
- tokio (async runtime)
- serde/serde_json
- tracing/tracing-subscriber
- chrono

## Build & Run
```bash
cd ~/Projects/PlebClient-Qt
QML_IMPORT_PATH=/usr/lib/x86_64-linux-gnu/qt6/qml cargo run
```

## Qt6 Packages Needed
```bash
sudo apt install qt6-base-dev qt6-declarative-dev qt6-tools-dev \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-window qml6-module-qtqml-workerscript \
  qml6-module-qtquick-templates
```

## Original Project Reference
The iced-based version is at `~/Projects/PlebClient-3` with working:
- D-Bus signer integration
- NIP-46 bunker support  
- Profile editing
- DM sending (fixed during this session)
- NWC wallet integration

Code can be referenced for Nostr logic to port to Qt version.
