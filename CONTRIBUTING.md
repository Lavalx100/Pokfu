# Contributing to Pokfu

Pokfu is an open-source native SwiftUI iOS/iPadOS project. Contributions are
welcome through focused pull requests.

## Development requirements

- macOS with Xcode and the iOS Simulator
- iOS 15 SDK for the main app
- iOS 17.5 or newer SDK for the widget extension
- A test Moodle account if you are testing authenticated features

No Flutter SDK, Dart runtime, CocoaPods installation, or app server is needed.

## Build and test

```sh
xcodebuild -project ios/Runner.xcodeproj \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Open `ios/Runner.xcodeproj` in Xcode when you need to run the app interactively
or test signing, widgets, Live Activities, deep links, and Moodle SSO.

## Pull requests

- Keep changes scoped and explain user-visible behavior.
- Add or update XCTest coverage for service and model changes.
- Do not commit Moodle credentials, API keys, private course files, or real
  student data.
- Keep the App Group, URL scheme, bundle identifiers, and migration behavior
  compatible unless a change is explicitly documented.
- Preserve the notices in `LICENSE` and `THIRD_PARTY_NOTICES.md`.
