# Riengtu

A private money app for iPhone and iPad, in English and Vietnamese. You record what you spend and what you own, from cash and bank accounts to Vietnamese stocks, gold and property, in any currency, and it stays on your device.

## Privacy

- **No account, no network.** Riengtu makes no network requests and has no analytics or third-party code. The privacy manifest declares no collected data.
- **Encrypted at rest.** The ledger is one JSON file, `Application Support/ledger.json`, written with complete file protection: iOS encrypts it with the device passcode, and it can't be read while the device is locked. It's included in device backups, like other apps' data.
- **App lock.** Settings > Lock with Face ID (or Touch ID, or the passcode). Once it's on, Riengtu locks when it launches and each time it goes to the background. If the device's passcode is later turned off, Riengtu unlocks rather than lock someone out of their own data.
- **Hidden in the app switcher.** Whenever Riengtu isn't active, a cover hides its screens, so amounts don't show in the app switcher.
- **Apple Intelligence stays on the device.** Where it's available (iOS 26, a device that runs it, and it turned on), the model on the device suggests a category and tags from an expense's note. Riêng Tư never uses a model in the cloud, and it works fully without one.
- **Captured payments stay on the device too.** Shortcuts can send a bank's emails and Apple Pay payments to Riêng Tư's inbox. They wait there, in a separate file (`inbox.json`) that can be written while the device is locked after its first unlock, until the person adds or dismisses them.
- **Never overwrites what it can't read.** If the file is damaged, or from a newer version, Riengtu saves nothing until the person chooses Start Over, which keeps the old file on the device.

## Money

Riengtu has three tabs: Spending, Assets and Settings.

- **Spending.** Each expense keeps its own currency. Expenses have no totals. New expenses start in the currency used last, or the region's currency at first. Expenses can have tags for what they were for, starting with Personal, Family, Work, Gift and Trip, and the list can be filtered by tag. Settings > Tags renames and deletes them.
- **Assets.** What the person owns, in three groups: money (cash, bank accounts, e-wallets, savings deposits), investments (stocks, fund certificates, gold, crypto) and property and belongings (property, vehicles, anything else). An asset is valued by an amount, by a quantity times a price, or, for gold, by a weight in lượng, chỉ or grams times a price per lượng, chỉ or gram. Prices are typed in, and each asset keeps the date its value was last changed. The tab totals each currency on its own: amounts in different currencies are never added together.

Amounts, quantities and prices are `Decimal`, stored as text, so no digits are lost.

## Capturing payments

iOS doesn't let an app read other apps' notifications, so Riêng Tư can't see a bank app's alerts. Instead, it has two Shortcuts actions, which run in the background:

- **Add Bank Message to Inbox** takes the text of a bank's email or message. `TransactionText` reads it with rules: the amount (not the balance), whether money went out or came in, the time, and the "Nội dung". Money received is left out. This covers QR transfers and card payments the bank emails about.
- **Add Payment to Inbox** takes an amount and a merchant, for an Apple Pay automation.

Captured payments wait in the inbox at the top of the Spending tab. When the app is open, Apple Intelligence (`TransactionReader`) reads new messages for a cleaner description. Tapping one opens the expense editor with its amount, date and note filled in.

To set it up, in Shortcuts > Automation > New: choose **Email**, the bank's address as the sender and Run Immediately, then add **Add Bank Message to Inbox** with Shortcut Input as its message. The bank's emails must arrive in the Mail app. For Apple Pay, choose **Transaction** and add **Add Payment to Inbox** with the input's Amount and Merchant. Settings > Capture Payments shows the same steps.

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

## TestFlight

The App Store app is `vn.riengtu`, on team 8G6DC3A5B8. To upload a build, raise `CURRENT_PROJECT_VERSION` in `project.yml` (each upload needs a new build number; `ExportOptions.plist` leaves it as it is), then archive and upload with the Apple account signed in to Xcode:

```sh
xcodegen generate
xcodebuild archive -project Riengtu.xcodeproj -scheme Riengtu -destination 'generic/platform=iOS' -derivedDataPath build -archivePath build/Riengtu.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/Riengtu.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/upload -allowProvisioningUpdates
```

Don't pipe the upload into `head`: closing the pipe early stops `xcodebuild` partway through.

## Layout

- `App/`: the SwiftUI app.
  - `RootView` holds the tabs, loads the ledger when the app becomes active, and locks it in the background.
  - `Expenses/` has the Spending tab (`SpendingView`, the expenses grouped by day), the editor sheet, the category grid and the currency picker. Each category's name, symbol and color is in `ExpenseCategory+Display.swift`.
  - `Assets/` has the Assets tab (`AssetsView`) and its editor sheet. Each kind of asset's name, symbol and color is in `AssetKind+Display.swift`.
  - `Capture/` has the Shortcuts actions that put payments in the inbox, and the screen that explains how to set them up.
  - `Tags/` has the tag chips in the expense editor, the Tags screen, and `Tags.displayName`, which shows the starter tags in the app's language.
  - `Components/` has views both tabs use: `NumberField`, which tidies typed amounts, and `IconBadge`.
  - `Privacy/` has `AppLock` (Face ID, Touch ID or passcode) and `privacyShield()`, which covers a view while Riengtu is locked or inactive.
  - `Settings/` is the settings screen, and `Previews/` the sample data for previews.
  - `Localizable.xcstrings` has every string in both languages, and `InfoPlist.xcstrings` the Info.plist ones, such as the reason for Face ID. `PrivacyInfo.xcprivacy` is the privacy manifest: declare each required-reason API there as the app starts using it (so far, `UserDefaults` for the lock setting).
- `Packages/RiengtuKit/`: everything that isn't UI, and the tests.
  - `Expense`, `ExpenseCategory`, `Asset`, `AssetKind` and `Ledger` are the data. `Ledger` also groups the assets and totals them by currency.
  - `LedgerStore` is what the app observes. It saves every change before showing it.
  - `LedgerFile` reads and writes the JSON file. The file has a version (`Ledger.currentVersion`, now 3): a file from an earlier version is read and saved in the current one, and one from a later version isn't read at all.
  - `InboxStore` and `InboxFile` keep captured payments (`CapturedTransaction`). `TransactionText` reads a bank's message with rules, and `TransactionReader` with the model.
  - `Tags` tidies and matches tag names. `ExpenseTagger` asks the model on the device for a `TagSuggestion`, which is checked against the person's tags.
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
xcrun simctl launch "$SIM" vn.riengtu -AppleLanguages "(vi)"
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

They cover the ledger, assets and their values (including gold's units), tags, saving and loading (including damaged files and ones from earlier versions), amount input in both number formats, currencies and `AppLanguage`. On a Mac with Apple Intelligence on, one test also asks the real model for a suggestion. `StringCatalogTests` checks both string catalogs: every string must be translated into Vietnamese and marked so. A new string fails until it is.

To try the lock in the Simulator, choose Features > Face ID > Enrolled, then Matching Face or Non-matching Face when Riengtu asks.
