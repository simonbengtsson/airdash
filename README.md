# AirDash File Sharing

Transfer photos and files to any device.

### Get the app

- [Apple App Store (iOS & macOS)](https://apps.apple.com/se/app/airdash-file-sharing/id1596599922)
- [Homebrew (macOS)](https://formulae.brew.sh/cask/airdash)
- [Google Play (Android)](https://play.google.com/store/apps/details?id=io.flown.airdash)
- [Microsoft Store (Windows)](https://apps.microsoft.com/store/detail/airdash/9NL9K7CSG30T)
- [Snap Store (Linux)](https://snapcraft.io/airdash)

### Analytics

- [Analytics Dashboard](https://mixpanel.com/p/XKeBKcwzQ5HjuUxuxHv934)

### Key features

- Support for all major platforms and app stores (iOS, macOS, Windows, Linux and Android)
- Free forever to send any number of files of any size
- Maximum privacy and security by fully encrypting files and transferring them directly between devices
- Quickly start transfers using native mobile share sheet and drag and drop on desktop
- Send files anywhere (no need to be on the same network or nearby)
- Automatically uses the best and fastest connection available (wifi, mobile internet, ethernet etc)

### Key technologies

- Flutter 3 (iOS, macOS, Android, Linux and Windows apps)
- WebRTC (file and data transfers)
- Firebase Firestore (WebRTC signaling and config storage)
- Firebase Functions (device pairing and config automation)
- Firebase Hosting (website and static files hosting)
- App Store Connect API and Microsoft Store submission API (release automation)
- Mixpanel (web and app analytics)
- Sentry (app monitoring and error tracking)

### Run project

- Create a firebase project (https://console.firebase.google.com) and enable firestore and anonymous authentication
- Create a .env file by duplicating the .env.sample file
- Replace the firebase project id and web API key in the .env file with the ones for your project (firebase console -> project settings)
- Run `dart tools/scripts.dart app_env` to get a env.dart file
- Deploy pairing backend function by `cd functions && npm i && npx firebase deploy --only pairing`
- Run app using editor or `flutter run`

By default a google stun server is used to connect peers. The simplest way to enable turn servers as well is to use https://www.twilio.com/stun-turn. Create functions/.env file similar to the functions/.env-sample file and deploy the updateTwilioToken backend function.

### Contribute

Contributions are very much welcome on everything from bug reports to feature development. If you
want to change something major write an issue about it first to ensure it will be considered for
merge.

### Publish guide (for contributors)

Prepare

- Update libraries
- flutter pub get
- cd ios && pod update
- cd macos && pod update
- Update changelog.md and version in pubspec.yaml and snapcraft.yaml
- git commit -am vX.X.X
- git tag "vX.X.X"
- git push && git push -f --tags

macOS

- flutter build macos
- Archive -> Distribute -> Direct Distribution
- npx appdmg appdmg.json ./build/airdash.dmg
- Distribute with transporter

iOS

- flutter build ipa
- Distribute with Transporter

Android

- flutter build appbundle
- cp build/app/outputs/bundle/release/app-release.aab build/airdash.aab
- open https://play.google.com/console/u/0/developers/6822011924129869646/app/4975414306006741094/tracks/production
- App Bundle Explorer -> Download signed apk -> build/airdash.apk

Windows

- Open Windows in VMWare
- Open ~\Documents\airdash in vs code
- git pull -r && flutter pub get
- dart run msix:create
- Copy msix file to build/airdash.msix
- Create new update -> open https://partner.microsoft.com/en-us/dashboard/products/9NL9K7CSG30T

Linux

- Open Ubuntu in VMWare
- Open ~\Documents\airdash in vs code
- git pull -r && flutter pub get
- snapcraft clean --use-lxd # required
- snapcraft --output build/airdash.snap --use-lxd
- snapcraft upload --release=stable build/airdash.snap
- Copy to mac ./build/airdash.snap (send.vis.ee for example)

Create Github release

- open https://github.com/simonbengtsson/airdash/releases/new
- Attach
  - build/airdash.apk
  - build/airdash.dmg
  - build/airdash.msix
  - build/airdash.snap
