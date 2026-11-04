# Riengtu

A private money app for iPhone and iPad, in English and Vietnamese. You record what you spend and what you own, from cash and bank accounts to Vietnamese stocks, gold and property, in any currency, and it stays on your device.

## Privacy

- **No account, no network.** Riengtu makes no network requests and has no analytics or third-party code. The privacy manifest declares no collected data.
- **Encrypted at rest.** The ledger is one JSON file, `Application Support/ledger.json`, written with complete file protection: iOS encrypts it with the device passcode, and it can't be read while the device is locked. It's included in device backups, like other apps' data.
- **App lock.** Settings > Lock with Face ID (or Touch ID, or the passcode). Once it's on, Riengtu locks when it launches and each time it goes to the background. If the device's passcode is later turned off, Riengtu unlocks rather than lock someone out of their own data.
- **Hidden in the app switcher.** Whenever Riengtu isn't active, a cover hides its screens, so amounts don't show in the app switcher.
- **Never overwrites what it can't read.** If the file is damaged, or from a newer version, Riengtu saves nothing until the person chooses Start Over, which keeps the old file on the device.

## Money

Riengtu has three tabs: Spending, Assets and Settings.

- **Spending.** Each expense keeps its own currency. Expenses have no totals. New expenses start in the currency used last, or the region's currency at first.
- **Assets.** What the person owns, in three groups: money (cash, bank accounts, e-wallets, savings deposits), investments (stocks, fund certificates, gold, crypto) and property and belongings (property, vehicles, anything else). An asset is valued by an amount, by a quantity times a price, or, for gold, by a weight in lượng, chỉ or grams times a price per lượng, chỉ or gram. Prices are typed in, and each asset keeps the date its value was last changed. The tab totals each currency on its own: amounts in different currencies are never added together.

Amounts, quantities and prices are `Decimal`, stored as text, so no digits are lost.

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

- `App/`: the SwiftUI app.
  - `RootView` holds the tabs, loads the ledger when the app becomes active, and locks it in the background.
  - `Expenses/` has the Spending tab (`SpendingView`, the expenses grouped by day), the editor sheet, the category grid and the currency picker. Each category's name, symbol and color is in `ExpenseCategory+Display.swift`.
  - `Assets/` has the Assets tab (`AssetsView`) and its editor sheet. Each kind of asset's name, symbol and color is in `AssetKind+Display.swift`.
  - `Components/` has views both tabs use: `NumberField`, which tidies typed amounts, and `IconBadge`.
  - `Privacy/` has `AppLock` (Face ID, Touch ID or passcode) and `privacyShield()`, which covers a view while Riengtu is locked or inactive.
  - `Settings/` is the settings screen, and `Previews/` the sample data for previews.
  - `Localizable.xcstrings` has every string in both languages, and `InfoPlist.xcstrings` the Info.plist ones, such as the reason for Face ID. `PrivacyInfo.xcprivacy` is the privacy manifest: declare each required-reason API there as the app starts using it (so far, `UserDefaults` for the lock setting).
- `Packages/RiengtuKit/`: everything that isn't UI, and the tests.
  - `Expense`, `ExpenseCategory`, `Asset`, `AssetKind` and `Ledger` are the data. `Ledger` also groups the assets and totals them by currency.
  - `LedgerStore` is what the app observes. It saves every change before showing it.
  - `LedgerFile` reads and writes the JSON file. The file has a version (`Ledger.currentVersion`, now 2): a file from an earlier version is read and saved in the current one, and one from a later version isn't read at all.
  - `AmountInput` tidies typed amounts in the device's number format, such as `1.250.000` in Vietnam.
  - `Currencies` lists the currencies and their digits and symbols.
  - `AppLanguage` lists the languages the app is in.

## Languages

English is the source language and Vietnamese the translation, both in the string catalog `App/Localizable.xcstrings`. iOS picks the app's language from the device's preferred languages, or from the one chosen for Riengtu in Settings > Riêng Tư > Language. That choice only appears once the device has more than one preferred language.

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

They cover the ledger, assets and their values (including gold's units), saving and loading (including damaged files and ones from version 1), amount input in both number formats, currencies and `AppLanguage`. `StringCatalogTests` checks both string catalogs: every string must be translated into Vietnamese and marked so. A new string fails until it is.

To try the lock in the Simulator, choose Features > Face ID > Enrolled, then Matching Face or Non-matching Face when Riengtu asks.
