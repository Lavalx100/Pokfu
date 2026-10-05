# Pokfu iOS App Store submission pack

This file is the release handoff for Pokfu 1.1 (build 5). It records the
values that are already in the project and the account-specific steps that
must be completed in App Store Connect.

## Release identity

| Item | Value |
| --- | --- |
| App name | Pokfu |
| Developer shown in the app | Jad Khiami |
| App Store developer name | Comes from your Apple Developer account; confirm it shows the name you want |
| Marketing version | 1.1 |
| Build number | 5 |
| iOS bundle ID | `com.pokfu.app` |
| Widget bundle ID | `com.pokfu.app.EventWidget` |
| App Group | `group.com.pokfu.app` |
| URL scheme | `pokfu` |
| Privacy policy URL | https://pokfu.netlify.app/ |
| Suggested SKU | `pokfu-ios-1` |
| Suggested primary category | Productivity |
| Suggested secondary category | Education |

The SKU is only an internal App Store Connect value. Choose another one if
`pokfu-ios-1` is already in use; it cannot be changed after the app record is
created.

The name embedded in the app is already `Jad Khiami`. The public developer name
shown on the App Store is controlled by the Apple Developer enrollment/account,
not by this repository, so confirm that account-level value before creating the
record.

## Suggested store metadata

These are drafts, not legal claims. Check each statement against the exact
release and your Moodle deployment before publishing.

### Subtitle

`Moodle tasks, simplified`

### Promotional text

`Keep your Moodle schedule, courses, and reminders close at hand.`

### Description

Pokfu keeps your Moodle schedule in one focused place. Connect to your Moodle
site to see upcoming deadlines, browse courses, plan reminders, and review
your calendar without switching between pages.

Features:

- View upcoming Moodle events and deadlines
- Browse courses and course content
- Create local reminders
- Review your calendar and workload
- Use widgets and Live Activities where supported

Pokfu is an independent open-source distribution maintained by Jad Khiami. It
is not affiliated with Moodle.

### Keywords

`Moodle,deadlines,courses,calendar,reminders,student,school,planner`

### URLs

- Privacy policy: https://pokfu.netlify.app/
- Marketing URL: https://pokfu.netlify.app/
- Support URL: https://pokfu.netlify.app/#contact
- Support email: jad.kh1@outlook.com

## Before creating the app record

1. Confirm that you have the legal right to distribute this derivative. Keep
   the upstream MIT license and attribution in the source distribution. Do not
   imply that Pokfu is the official Moodle app or that it is endorsed by
   Moodle.
2. Enroll in the Apple Developer Program and confirm your Account Holder,
   banking, tax, and agreements are complete.
3. In Certificates, Identifiers & Profiles, register:
   - App ID `com.pokfu.app`
   - App ID `com.pokfu.app.EventWidget`
   - App Group `group.com.pokfu.app`
4. Make sure the App ID capabilities include App Groups and the widget/live-
   activity capabilities used by this release. Do not enable Push
   Notifications unless you add a real remote push service; the current app
   uses local reminders only.
5. Create a real support contact. The reviewer must be able to reach you.

## Build and upload

After your Apple team is selected in Xcode and automatic signing succeeds,
archive the native project:

```sh
xcodebuild \
  -project ios/Runner.xcodeproj \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Pokfu.xcarchive \
  archive
```

The expected output is `build/Pokfu.xcarchive`. Open it in Xcode Organizer and
choose **Distribute App → App Store Connect → Upload** to create and upload the
signed release. There is no Flutter workspace or CocoaPods installation.

For a GUI upload, open `ios/Runner.xcodeproj`, choose `Any iOS Device (arm64)`, then
choose Product > Archive. In Organizer choose Distribute App > App Store
Connect > Upload. Wait for the build to finish processing before selecting it
in the App Store version record.

## App Privacy questionnaire: review before answering

The current code has no ads, analytics SDK, developer-hosted user database, or
tip jar. It stores Moodle tokens and Moodle content locally and sends requests
to the Moodle host selected by the user. That is not a substitute for your
own legal/privacy review.

Before submission, review these possible data categories in App Store Connect:

- Account or login information used to authenticate with Moodle
- User or course content returned by the Moodle host
- Identifiers associated with the Moodle account, if retained by the host
- Any data contained in files the user chooses to download or open

Mark tracking as **No** only if the final build still has no tracking or
advertising technology. If your Moodle operator, analytics provider, crash
reporter, or another SDK collects data, include that collection in the
questionnaire. Data kept only on-device and never transmitted to a party that
can access it may be treated differently in Apple’s questionnaire, so verify
the answers against the final network behavior.

## Review information

Pokfu requires access to a working Moodle server. Prepare a reviewer account
on a non-production or test Moodle site, or provide a fully featured demo mode
before submission. Do not give Apple a personal account or an account that
will expire during review.

Suggested review notes:

> Pokfu is a Moodle companion. On first launch, tap Connect to Moodle and use
> the test Moodle server and credentials supplied below. The app opens the
> Moodle authentication flow, returns to Pokfu through the `pokfu` URL scheme,
> and then loads courses and calendar events. Widgets and Live Activities are
> optional features on supported OS versions. Pokfu contains no purchases,
> advertising, or tracking. The privacy policy is available at
> https://pokfu.netlify.app/.

Add the test server, username, password, any required MFA/SSO instructions,
and a contact who can keep the account active during review. If the real
Moodle deployment cannot be shared with Apple, add a demo mode or expect the
review to be blocked.

## Export compliance

The iOS app declares `ITSAppUsesNonExemptEncryption` as `false` because the
current build uses normal platform HTTPS/TLS and has no custom encryption
implementation. Re-evaluate this answer if you add cryptography, VPN,
secure-messaging, encryption libraries, or another networking stack that
changes the export-compliance analysis.

## Version and screenshot requirements

- Use `1.1` for this App Store version and increment the build number for every
  uploaded build (`5`, `6`, `7`, ...).
- Capture clean release screenshots without the debug banner or simulator
  chrome. The current 6.9-inch iPhone simulator is useful for the largest
  iPhone screenshot slot, but populate all required device families that you
  choose to support.
- Do not use placeholder Moodle data that belongs to a real student. Use a
  test account or anonymized sample data.
- Keep screenshots, description, privacy answers, and review notes consistent
  with the build that is actually selected.

Candidate screenshots captured from the clean Pokfu simulator build:

- `docs/app-store/pokfu-iphone-6.9-events.jpg`
- `docs/app-store/pokfu-ipad-13-events.jpg`

Review them for real/private Moodle data before uploading; capture additional
course, calendar, and settings screens for the final listing.

## What still requires your Apple account

- Select your Apple Developer team and create distribution signing assets.
- Confirm the Apple account’s public developer name and complete any identity,
  EU trader, banking, and tax requirements that apply to you.
- Register the bundle IDs and App Group under your team.
- Create the App Store Connect app record and accept any new agreements.
- Provide the legal seller/contact information, age rating, pricing,
  availability, app privacy answers, and export-compliance answers.
- Provide support contact details, screenshots, review credentials, and final
  release notes.
- Upload the signed archive, select the processed build, answer the final
  compliance questions, and submit the version for review.

## App Store Connect click-by-click

### 1. Create the app record

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Open **Apps**, click **+**, and choose **New App**.
3. Select **iOS**, enter `Pokfu`, choose the primary language, select the
   registered bundle ID `com.pokfu.app`, and enter the SKU `pokfu-ios-1`.
4. Create the record. Do not create another record for the widget; the widget
   is an embedded extension inside the iOS app.

### 2. Fill the General information pages

Under the app’s **App Information** section:

- Set the subtitle, categories, age-rating answers, copyright, and any
  required regional/trader information.
- Set the privacy policy URL to `https://pokfu.netlify.app/`.
- Set the support URL to a working page or email controlled by you.
- Set the marketing URL to `https://pokfu.netlify.app/` only if you want the
  privacy site to be the public landing page.
- Complete App Privacy with the final network/data behavior. The questionnaire
  is not automatically populated by `PrivacyInfo.xcprivacy`.

Under **Pricing and Availability**, choose Free or a price tier, territories,
and the release availability. This app has no in-app purchases in the current
build.

### 3. Add the first version

1. Open the `1.1 Prepare for Submission` page.
2. Paste the approved description, keywords, promotional text, and support
   information.
3. Upload screenshots for every required device family you support. For a
   phone-only listing, start with the 6.9-inch iPhone slot and add any older
   required iPhone slot shown by the page. If you leave iPad enabled in the
   build, also prepare iPad screenshots or remove iPad support deliberately
   before upload.
4. In **Build**, select build `5` after processing completes.
5. Complete **App Review Information**, including the test server, test
   username/password, MFA instructions, and review contact.
6. Add release notes such as: `Initial Pokfu release with Moodle events,
   courses, calendar, reminders, widgets, and Live Activities on supported
   devices.`

### 4. Upload and test

1. In Xcode Organizer, upload the signed archive, or use Transporter with the
   generated `.ipa`.
2. Wait for processing. If the build is missing, inspect **Activity** for
   processing errors before uploading a new build number.
3. Open **TestFlight**, add yourself as an internal tester, and install the
   build on a physical iPhone. Exercise first launch, Moodle authentication,
   deep-link return, logout, reminders, file opening, widget installation,
   dark mode, accessibility text sizing, and offline/error states.
4. If you use external testers, complete the beta-app review information and
   export-compliance questions first.

### 5. Submit

1. Return to the `1.1 Prepare for Submission` page and make sure the selected
   build, screenshots, privacy answers, export answers, and review notes all
   describe the same binary.
2. Click **Add for Review**, resolve every missing-item warning, then click
   **Submit for Review**.
3. Choose a release option: manual release, automatic release after approval,
   or automatic release no earlier than a date you select.
4. After approval, watch the version status until it is Ready for Sale. A
   phased release can be enabled later if you want a gradual rollout.

## Common submission blockers for this project

- **Signing:** the Xcode project intentionally leaves `DEVELOPMENT_TEAM`
  blank. Select your team in Xcode and enable automatic signing for both
  `Runner` and `EventWidgetExtension`.
- **Capabilities:** register the App Group and widget bundle ID under the same
  team; otherwise the archive may fail signing or the widget may not load.
- **Moodle access:** Apple review cannot verify the main feature without a
  reachable Moodle test account or demo mode.
- **Privacy mismatch:** the public policy, App Store privacy answers, and the
  actual server/SDK behavior must agree. Update all three if you add analytics,
  crash reporting, ads, or a hosted service.
- **Brand/rights:** retain upstream MIT attribution and make the independent
  relationship clear. Do not copy an official Moodle logo or claim affiliation.
- **Build number:** every re-upload of version 1.1 needs a new build number;
  do not reuse build `5`.

## Official Apple references

- [Create an App Store Connect app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
