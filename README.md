# Riengtu

A private money app for iPhone and iPad, in English and Vietnamese. You record the money that comes in and goes out, and what you own, from cash and bank accounts to Vietnamese stocks, gold and property, in any currency. It stays on your device, and in your iCloud account, encrypted end to end, if you turn on sync.

## Privacy

- **No account, no network of its own.** Riengtu has no analytics and no third-party code besides GRDB, which runs SQLite on the device. It makes no network requests unless the person turns on iCloud sync. The privacy manifest declares no collected data.
- **Encrypted at rest.** The ledger is a SQLite database, `Application Support/Ledger/ledger.sqlite`, in a folder with complete file protection: iOS encrypts it and its journal with the device passcode, and they can't be read while the device is locked. Deleted rows are overwritten. It's included in device backups, like other apps' data.
- **iCloud sync, if the person turns it on.** Settings > Sync with iCloud keeps the ledger in their own iCloud account's private database, so it's on each of their devices. Each record's data is in an encrypted field, encrypted end to end with keys in their iCloud Keychain, so Apple can't read it. Erase All Data then erases it from iCloud too; other devices keep their copy and stop syncing.
- **App lock.** Settings > Lock with Face ID (or Touch ID, or the passcode). Once it's on, Riengtu locks when it launches and each time it goes to the background. If the device's passcode is later turned off, Riengtu unlocks rather than lock someone out of their own data.
- **Hidden in the app switcher.** Whenever Riengtu isn't active, a cover hides its screens, so amounts don't show in the app switcher.
- **Apple Intelligence stays on the device.** Where it's available (iOS 26, a device that runs it, and it turned on), the model on the device suggests a category and tags from an expense's note. Riêng Tư never uses a model in the cloud, and it works fully without one.
- **Captured payments stay on the device too.** Shortcuts can forward a bank app's notifications and a bank's emails, and Apple Pay payments, to Riêng Tư's inbox. They wait there, in a separate database (`Inbox/inbox.sqlite`) that can be written while the device is locked after its first unlock, until the person adds or dismisses them. Then they stay in the inbox's history, with the message as it came, until the app deletes them after the time chosen in Settings (a week unless changed).
- **Never overwrites what it can't read.** If the database is damaged, Riengtu saves nothing until the person chooses Start Over, which keeps the old file on the device. Records a newer version saved, such as on another device, are shown without being changed, or kept as they are if this version can't read them, until the app is updated.

## Money

Riengtu has three tabs: Inbox (see Capturing payments), Ledger and Assets. The gear at the top left of each opens Settings, and the + at the top right adds to that tab.

- **Ledger** (Sổ thu chi). A month at a time, grouped by day, with the month's money in, money out and the difference on top, each currency on its own. It holds four kinds of entry:
  - **Expenses** and **income**, each with a category. Either can name the account (cash, a bank account, an e-wallet or a savings deposit) the money came from or went to, and that account's balance goes down or up. Its currency is then the account's.
  - **Transfers** between the person's own assets: an ATM withdrawal, topping up an e-wallet, a savings deposit, or buying or selling shares, fund units, coins or gold. Money comes off one asset and goes on the other; for shares and gold it's the number of shares or the weight that changes, and money changed into another currency is typed in both. Transfers aren't income or spending, so the totals leave them out.
  - **Adjustments**, which record a change to an asset's worth made by hand in the Assets tab, such as a corrected balance or a new price. Deleting one leaves the asset as it is.

  Entries don't change assets themselves. An asset keeps the value last set by hand, and its balance is that value with what entries dated since then changed. So editing or deleting an entry simply counts differently, and entries added on two devices both count. Setting the value by hand again starts afresh from then. A balance can go below zero when more is recorded going out than coming in. New entries start in the currency used last, or the region's currency at first, and with the account used last. Expenses and income can have tags for what the money was for, starting with Personal, Family, Work, Gift and Trip, and the ledger can be filtered by tag. Settings > Tags renames and deletes them.
- **Assets.** What the person owns, in three groups: money (cash, bank accounts, e-wallets, savings deposits), investments (stocks, fund certificates, gold, crypto) and property and belongings (property, vehicles, anything else). An asset is valued by an amount, by a quantity times a price, or, for gold, by a weight in lượng, chỉ or grams times a price per lượng, chỉ or gram. Prices are typed in, and each asset keeps the date its value was last set by hand. The tab totals each currency on its own: amounts in different currencies are never added together.

Amounts, quantities and prices are `Decimal`, stored as text, so no digits are lost.

## Capturing payments

iOS doesn't let an app read other apps' notifications itself, but Shortcuts can forward them. Riêng Tư has two Shortcuts actions, which run in the background:

- **Add Bank Message to Inbox** forwards the text of a bank app's notification (its title, then its body, on iOS 27), or of a bank's email or message, as it came. This covers QR transfers, card payments and money received.
- **Add Payment to Inbox** takes Wallet's amount, as text, and a merchant, for an Apple Pay automation. Both are optional: Wallet doesn't always pass the amount on, and an automation can't stop to ask for it, so the payment goes in the inbox without one.

Captured transactions wait in the Inbox, the first tab. When the app is open, it reads new ones. With Apple Intelligence, `TransactionReader` reads the amount, the description, and whether it's spending, income or a transfer between the person's own accounts, and where income came from; `ExpenseTagger` picks an expense's category. The rules (`TransactionText`) check the amount and read the + or −, and read the message alone without Apple Intelligence. The person checks them and taps Add All, which adds the expenses and income from or into the account used last; or taps one to open the editor with it filled in. Transfers wait for their accounts to be chosen.

For transactions from before the inbox was set up, take screenshots of the bank app's transaction history, then in the Inbox tap **+** and choose **From Photos**. **From Files** takes a bank's or another app's export (CSV, TSV, JSON) or text, a transaction for each row, object or paragraph (`FileText`). Vision reads the text on the device (`ScreenshotReader`), `ScreenshotText` finds each transaction with its day and time, and they go in the inbox to be read like a forwarded message. Transactions already in the inbox or its history are left out.

For a bank app's notifications (iOS 27): in Shortcuts > Automation > New, choose **Notification**, the bank's app, a filter that only transactions match (such as Title contains VND) and Run Immediately, then add **Add Bank Message to Inbox** with Shortcut Input as the message: Shortcuts passes the notification's title and body. Set up one for each bank.

On iOS 27, where a shared shortcut carries its trigger, Settings > Capture Payments has an Add Card Payment Shortcut button. It opens an iCloud link to a shortcut that runs Add Payment to Inbox when any card in Wallet is tapped, so adding it is all the setup. The app makes no request itself: Shortcuts downloads the shortcut.

Before iOS 27, or for bank emails, set it up by hand. In Shortcuts > Automation > New: choose **Email**, the bank's address as the sender and Run Immediately, then add **Add Bank Message to Inbox** with Shortcut Input as its message. The bank's emails must arrive in the Mail app. For Apple Pay, choose **Transaction** and add **Add Payment to Inbox** with the input's Amount and Merchant. Settings > Capture Payments shows the same steps.

## iCloud

The app uses the CloudKit container `iCloud.vn.riengtu` (`App/Riengtu.entitlements`, made by XcodeGen from `project.yml`). Xcode creates it the first time a signed build needs it. A container can't be deleted or renamed. Development builds use CloudKit's Development environment, where record types appear as they're first saved. TestFlight and App Store builds use Production, so before uploading a build that syncs, deploy the schema in the [CloudKit Console](https://icloud.developer.apple.com) (Riêng Tư's container > Deploy Schema Changes).

Syncing can't run in the Simulator without a signed build, and `swift test` doesn't reach iCloud. Try it on two devices signed in to the same Apple Account.

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
  - `Ledger/` has the Ledger tab (`LedgerView`, a month of entries grouped by day under the month's totals), the rows (`EntryRow`), the editor sheet for expenses, income and transfers (`EntryEditor`), the category grid and the currency picker. Each category's name, symbol and color is in `ExpenseCategory+Display.swift` and `IncomeCategory+Display.swift`.
  - `Assets/` has the Assets tab (`AssetsView`) and its editor sheet. Each kind of asset's name, symbol and color is in `AssetKind+Display.swift`.
  - `Inbox/` has the Inbox tab (`InboxView`), the first: what waits to be added, Add All, and Add from Screenshots. Also the reading screen (`ReadingView`), reading in the background (`BackgroundReading`), and the inbox's history.
  - `Capture/` has the Shortcuts actions that put payments in the inbox, and the screen that explains how to set them up.
  - `Tags/` has the tag chips in the entry editor, the Tags screen, and `Tags.displayName`, which shows the starter tags in the app's language.
  - `Components/` has views both tabs use: `NumberField`, which tidies typed amounts, and `IconBadge`.
  - `Privacy/` has `AppLock` (Face ID, Touch ID or passcode) and `privacyShield()`, which covers a view while Riengtu is locked or inactive.
  - `Settings/` is the settings screen, and `Previews/` the sample data for previews.
  - `Localizable.xcstrings` has every string in both languages, and `InfoPlist.xcstrings` the Info.plist ones, such as the reason for Face ID. `PrivacyInfo.xcprivacy` is the privacy manifest: declare each required-reason API there as the app starts using it (so far, `UserDefaults` for the lock setting).
- `Packages/RiengtuKit/`: everything that isn't UI, and the tests.
  - `Entry`, `ExpenseCategory`, `IncomeCategory`, `Asset`, `AssetKind` and `Ledger` are the data. `Ledger` changes the assets as entries are saved and deleted, totals each month's income and spending by currency, and groups the assets and totals them by currency.
  - `LedgerStore` is what the app observes. It saves every change before showing it.
  - `LedgerDatabase` keeps the ledger with GRDB: one row per entry, asset and tag, as JSON with its format's version (`RecordVersion`), plus what syncing needs. Migrations only add, so an earlier version can still open the database after a later one.
  - `CloudSync` syncs it with `CKSyncEngine` while the app is open, and `CloudRecord` makes a row a CloudKit record. The later change wins; a record in a newer format is never replaced by an older one.
  - `LedgerFile` reads the JSON file builds before the database used (version 1 to 5), once, to move it into the database.
  - `InboxStore` keeps captured payments (`CapturedTransaction`) and their history in `InboxDatabase`, and reads new ones. `InboxFile` reads the JSON file builds up to 8 used, once. `TransactionText` reads a bank's message with rules, and `TransactionReader` with the model.
  - `ScreenshotReader` reads the text on a screenshot with Vision, and `ScreenshotText` finds the transactions in it.
  - `MoneyFormatStyle` writes amounts, with ₫ after the number.
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

They cover the ledger, entries and what they change in the assets, monthly totals, the database (moving the old file in, records from newer versions, damaged files, and the merge rules for iCloud changes), CloudKit records, assets and their values (including gold's units), tags, saving and loading (including damaged files and ones from earlier versions), amount input in both number formats, currencies and `AppLanguage`. On a Mac with Apple Intelligence on, one test also asks the real model for a suggestion. `StringCatalogTests` checks both string catalogs: every string must be translated into Vietnamese and marked so. A new string fails until it is.

The Shortcuts actions have their own tests (`IntentTests`), which run them through the system the way Shortcuts does, with the app launched in the background. Apple's `AppIntentsTesting` needs an iOS 27.2 or later simulator, and the system has to have registered the app's actions first: build, install and launch the app once, wait a few seconds, then test without building.

```sh
xcodebuild build-for-testing -project Riengtu.xcodeproj -scheme RiengtuIntentTests -destination "platform=iOS Simulator,id=<ID>" -derivedDataPath build
xcrun simctl install <ID> build/Build/Products/Debug-iphonesimulator/Riengtu.app && xcrun simctl launch <ID> vn.riengtu
xcodebuild test-without-building -project Riengtu.xcodeproj -scheme RiengtuIntentTests -destination "platform=iOS Simulator,id=<ID>" -derivedDataPath build
```

They write to that simulator's inbox. "vn.riengtu is not present" means the system hasn't registered the actions yet.

To try the lock in the Simulator, choose Features > Face ID > Enrolled, then Matching Face or Non-matching Face when Riengtu asks.
