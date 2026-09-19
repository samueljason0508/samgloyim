# samgloyim

A native, local-first iPhone finance app built from the supplied finance concept. SwiftUI, Swift Charts, Apple Vision, and PhotosUI. No packages, API keys, backend, or sign-in required.

## Run in Xcode

1. Open **samgloyim.xcodeproj**.
2. Select the **samgloyim** scheme.
3. Select an installed iPhone simulator, such as **iPhone 16 Pro**.
4. Press **Command-R**.

Requires Xcode 15 or later and an iOS 17+ simulator. Built and tested here with Xcode 16.4 and iOS 18.6. Simulator runs do not require a developer team. To run on a physical iPhone, choose your development team under Signing & Capabilities and use a unique bundle identifier if needed.

The first launch includes clearly labeled fictional sample data. Open the sliders button on Overview, then **Start fresh with my own data** to clear it and begin with an empty account. Clearing data requires confirmation.

## What works

- Monthly spending overview, cumulative chart, and category donut.
- Account filters and an account-to-category flow diagram inspired by the PDF. **Follow your money** switches between that flow and a per-account breakdown showing each account's spend, share, transaction count, balance, and category split.
- Add, edit, delete, and search expenses and income; category and type filters. Transactions record a time as well as a date; rows show it only when one exists, since imported rows carry a date alone.
- Import review shows where each row came from and which account it lands in, so a sync spanning two banks stays readable.
- Create and edit local accounts with opening balances.
- Receipt OCR from multiple Photos or Files images. Every reading must be opened, checked, and saved before import. OCR reads merchant, date, and receipt total; it does not itemize mixed-category receipts.
- Photograph a receipt and match it to a card purchase. The total must equal a purchase exactly; a near miss is never rounded onto the closest one. When nothing matches, several purchases tie, or the suggestion is wrong, you pick the purchase yourself — or save the receipt as a new one.
- CSV import with review, row-level validation, inferred categories, and possible duplicate detection. Invalid rows are listed; they are never silently imported.
- CSV export through the system Files picker.
- Calculated monthly insights and short financial-literacy lessons.
- Atomic JSON persistence in the app's Application Support directory. Corrupt or newer-format saves are preserved rather than overwritten.

## Try imports

**Overview → Import → Try a sample import** demonstrates review and duplicate handling without downloading anything.

For real data, export Excel or Google Sheets as UTF-8 CSV and choose **Import a spreadsheet**. Use the sample in `Samples/transactions.csv` as a template. CSVs support up to 10,000 rows / 5 MB. Receipt images support 10 files per batch / 25 MB per image.

Required headers: `date,merchant,amount`.

Optional headers: `category,account,kind,note`.

```csv
date,merchant,amount,category,account,kind,note
2026-09-18,Campus Cafe,12.50,Food & drink,Everyday,expense,Lunch
2026-09-18,Campus job,350.00,Other,Everyday,income,Payday
```

- Dates: `YYYY-MM-DD`, `MM/DD/YYYY`, or `M/D/YYYY`.
- Amounts: USD, at most two decimals. Both signed and unsigned amounts are imported as absolute amounts. **Kind determines direction**: `income` or `expense`; blank means expense. Negative refunds need `income` if they should increase the tracked balance.
- Account names must uniquely match an existing account. Blank uses the selected default account. Unknown accounts are reported and skipped.
- Categories must match an in-app category; unknown or absent categories are inferred from the merchant and can be corrected during review.
- Quotes, commas, CRLF, UTF-8 BOM, and multiline quoted notes are supported.
- Formula-like text fields are prefixed with an apostrophe during export to prevent spreadsheet formula evaluation.
- Review dates, merchant names, amounts, accounts, and categories before importing. Duplicate suggestions require the same normalized merchant, exact amount, calendar day, type, and account. Different bank posting dates or merchant names may not match. Duplicates start unchecked; the user can keep legitimate repeated purchases.
- To test receipt photos in Simulator, drag an image into Simulator to add it to Photos, then choose **Receipt photos**. A fictional receipt is included in `Samples/receipt.png`.

## Match a receipt to a card purchase

**Overview → Import → Scan a receipt** photographs a receipt, reads it on device, and files it against the purchase it belongs to. Simulators have no camera, so the screen offers the photo library instead.

A purchase is only suggested when its amount equals the receipt total to the cent, it falls within four days of the receipt date (card networks post a few days late), and it doesn't already carry a receipt. Income is never matched. Two equally good purchases are treated as no match rather than a coin flip. Everything else — no match, a tie, or a wrong suggestion — is mapped by hand from a searchable list, or saved as a new purchase.

Attaching keeps the confirmed merchant, total, date, and extracted text next to the purchase; the image itself is not stored. Matched purchases show a paperclip in Activity.

`Samples/receipt_trader_joes.png` totals $68.42, which matches the sample Trader Joe's purchase. Load it before running the receipt UI tests:

```sh
xcrun simctl addmedia booted Samples/receipt_trader_joes.png
```

## Data and scope

All amounts are integer cents in USD. Income is excluded from spending totals. Recorded account balances use all transactions and the opening balance, rather than a live bank balance. There are no budgets or savings goals; the app tracks what you spent, not what you planned to.

Receipt images are processed with Apple's on-device Vision text recognition; the app keeps reviewed fields and extracted text, not the original image.

Bank sync goes through Plaid and requires the local backend in `backend/` and your own Plaid credentials; connections are read-only and scoped to transactions. This version does **not** connect to Apple Wallet, Google Sheets accounts, or Excel accounts; it does not read `.xlsx` directly. Location-based merchant discounts are not implemented because they require a real offer database and location service. Insights are deterministic calculations; lessons are written content, not an AI chat service. There is no fraud detection or App Store deployment in this project.

Transactions and accounts persist locally. Deleting the app deletes its data. CSV export includes transactions, not a full backup of opening balances.

## Development and tests

No project generator needs to be installed. The checked-in Xcode project is ready to use. After adding or removing Swift source files outside Xcode, regenerate project membership with:

```sh
python3 scripts/generate_project.py
```

Run tests with **Command-U** or:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project samgloyim.xcodeproj -scheme samgloyim \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test CODE_SIGNING_ALLOWED=NO
```

`DEVELOPER_DIR` selects Xcode for that command only; it doesn't change the Mac's global command-line tools setting.

Unit tests cover exact cents, CSV quoting and validation, exports, duplicate boundaries, OCR extraction, receipt-to-purchase matching, persistence and schema migration, account and month filtering, and corrupt-data preservation. UI tests cover transaction creation/editing/deletion and relaunch persistence, duplicate import review, receipt scanning and manual mapping, account creation, fresh starts, and navigation. UI tests use a separate data file and don't reset your normal app data.

Verified on iPhone 16 Pro / iOS 18.6: the simulator build, 21 unit tests, and all 6 UI flows passed. Screenshots of the running app are in `Screenshots/`.

## Implementation references

- [Apple: Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [Apple: PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)
- [Apple: SwiftUI fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:))
