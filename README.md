# Riengtu

SwiftUI app for iPhone and iPad, in English and Vietnamese.

## Requirements

- iOS 18 or later.
- Xcode 16 or later. The project is built with Xcode 27.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Setup

```sh
brew install xcodegen   # once
xcodegen generate       # creates Riengtu.xcodeproj from project.yml
open Riengtu.xcodeproj
```

Run the `Riengtu` scheme on an iPhone or an iPad. The `.xcodeproj` is generated and not committed: edit `project.yml`, and run `xcodegen generate` again after adding or removing files.

## Layout

- `App/`: the SwiftUI app. `RootView` holds the navigation stack, `Home/` the first screen and `Settings/` the settings screen. `Localizable.xcstrings` has every string in both languages. `PrivacyInfo.xcprivacy` is the privacy manifest: declare each required-reason API there as the app starts using it.
- `Packages/RiengtuKit/`: everything that isn't UI, and the tests. `AppLanguage` lists the languages the app is in.

## Languages

English is the source language and Vietnamese the translation, both in the string catalog `App/Localizable.xcstrings`. iOS picks the app's language from the device's preferred languages, or from the one chosen for Riengtu in Settings > Riengtu > Language. That choice only appears once the device has more than one preferred language.

In Xcode, choose the language under Product > Scheme > Edit Scheme > Run > Options > App Language, or open the Vietnamese preview in `RootView.swift`. From the command line, build, install and launch in Vietnamese:

```sh
xcrun simctl list devices available   # pick a simulator
SIM="iPhone 17"
xcodebuild build -project Riengtu.xcodeproj -scheme Riengtu -destination "platform=iOS Simulator,name=$SIM,OS=27.0" -derivedDataPath build CODE_SIGNING_ALLOWED=NO
xcrun simctl boot "$SIM"
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Riengtu.app
xcrun simctl launch "$SIM" com.riengtu -AppleLanguages "(vi)"
xcrun simctl io "$SIM" screenshot /tmp/riengtu-vi.png
```

Building in Xcode adds new strings from the code to the catalog. `xcodebuild build` doesn't, but `xcodebuild -exportLocalizations` does:

```sh
xcodebuild -exportLocalizations -project Riengtu.xcodeproj -scheme Riengtu -localizationPath build/loc -exportLanguage vi -derivedDataPath build
```

## Tests

```sh
cd Packages/RiengtuKit && swift test
```

They cover `AppLanguage`, and `StringCatalogTests` checks the app's string catalog: every string must be translated into Vietnamese and marked so. A new string fails until it is.
