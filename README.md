# Pokfu

[![iOS Build](https://github.com/Lavalx100/Pokfu/actions/workflows/ios-build.yml/badge.svg)](https://github.com/Lavalx100/Pokfu/actions/workflows/ios-build.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Pokfu is an independent, open-source native SwiftUI Moodle companion. It
helps students see deadlines, browse courses, review grades, plan calendars,
create reminders, and study course material from a Moodle account.

The default configuration targets HKU Moodle. The native service layer lives
in `ios/Runner/PokfuServices.swift` and can be adapted to another Moodle host.

## Run locally

This checkout is a native SwiftUI iOS/iPadOS app. Open the Xcode project and
select the `Runner` scheme:

```sh
xcodebuild -project ios/Runner.xcodeproj \
  -scheme Runner \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

The main app targets iOS 15 and later. The widget and Live Activity remain
native SwiftUI extensions. See the [App Store submission pack](./docs/app-store/APP_STORE_SUBMISSION.md)
for signing, metadata, TestFlight, and review steps.

Open `ios/Runner.xcodeproj` in Xcode, select your Apple development team, and
create the App ID and App Group matching the identifiers in the Xcode project.
The in-place update preserves `com.pokfu.app`, the `pokfu://` URL scheme, and
`group.com.pokfu.app`.

## Rebranding and distribution

The product name and platform identifiers are centralized in the native iOS
project and Swift sources. The public [privacy policy](https://pokfu.netlify.app/)
is maintained separately from this app repository.

The iOS project includes the Pokfu icon, launch assets, deep-link scheme, App
Group, widget target, Live Activity, Keychain migration, and local
notification scheduling. App Store distribution still requires your own
signing team, provisioning, privacy disclosures, screenshots, and store
review.

Optional user-connected Qwen, GLM, Doubao, DeepSeek, and OpenRouter setup is
documented in [docs/AI_PROVIDERS.md](./docs/AI_PROVIDERS.md). Pokfu does not
ship a shared AI key or require an application server.

## Project ownership and license

Pokfu is maintained by Jad Khiami and is distributed under the MIT License in
[LICENSE](./LICENSE). It is an independent project and is not affiliated with
Moodle or HKU.

Pokfu evolved from [Cuckoo by Jerry Li](https://github.com/thermitex/cuckoo-flutter).
The required upstream attribution and license notice are preserved in
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

See [PRIVACY.md](./PRIVACY.md) for the current data-handling notice and
[CONTRIBUTING.md](./CONTRIBUTING.md) for contribution guidelines.
