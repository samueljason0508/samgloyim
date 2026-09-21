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
- Account filters and an account-to-category flow diagram inspired by the PDF. **Follow your money** switches between that flow and a per-account breakdown showing spend, share of the month, transaction count, balance, and category split.
- Add, edit, delete, and search expenses and income; category and type filters. Transactions record a time as well as a date; rows show it only when one exists, since imported rows carry a date alone.
- Each linked bank gets its own account, opened on first sight of it, so the account filter and every per-account total mean what they say. Cash holds anything entered by hand — manual transactions, receipts and CSV rows default to it, because no bank reported them.
- Bank rows are categorized from Plaid's detailed category, not just its primary one, and a sync applies the bank's later corrections and reversals as well as its new rows. Money moved between your own accounts — card payoffs, transfers, savings, cash withdrawals — is recorded but excluded from spending and income, so it neither double-counts nor swamps the month. Paying a person through Zelle or a similar app is not one of those: it counts as spending, even though the bank files it beside genuine transfers. Incoming transfers stay out of income, because a repayment or money arriving from your own other bank is not earnings.
- Create and edit local accounts with opening balances.
- Receipt OCR from multiple Photos or Files images. Every reading must be opened, checked, and saved before import. OCR reads merchant, date, and receipt total; it does not itemize mixed-category receipts.
- Photograph a receipt and match it to a card purchase. The total must equal a purchase exactly; a near miss is never rounded onto the closest one. When nothing matches, several purchases tie, or the suggestion is wrong, you pick the purchase yourself — or save the receipt as a new one.
- CSV import with review, row-level validation, inferred categories, and possible duplicate detection. Invalid rows are listed; they are never silently imported.
- CSV export through the system Files picker.
- Calculated monthly insights.
- **Two-level categories.** The top level is 16 buckets wide — mirroring Plaid's spending primaries, plus the splits this app cares about — so no bank row falls through to Other. Underneath, each synced row keeps the bank's own detailed category verbatim, so Food & drink opens into Fast food, Restaurant and Vending machines. A category you pick by hand is pinned and no sync overwrites it.
- **Which card should I use here?** On Overview, one tap finds the shop you are standing in and names the card that earns the most there. MapKit identifies the place, so there is no merchant database to build; earn rates are looked up per card and are editable, because a rotating category changes every quarter and a rate that has run out is worse than no rate.
- **What you owe, across every card.** Overview opens with what the banks themselves say is owed on each card, and what the other accounts hold. A balance is never added up from the transactions on hand unless no bank reports one — the sync window starts somewhere, and everything charged or paid before it is missing — and when that fallback is used it says so. A card can be marked as one by hand, not only when a bank says so.
- **Across the months.** Six months of spending, whole or one category at a time, with a line saying whether this month is above or below the last. Transfers stay out of it.
- **Renews on its own.** Repeating charges found across every account, grouped by merchant however the bank spells it, and kept only when every gap between them looks monthly — so a shop visited often is not a subscription. Price rises and the same service billed to two cards are called out.
- **A payoff reads as one event.** The two halves of a card payment name each other in Activity. Two possible matches are treated as none.
- **Banks that need attention say so.** Each bank syncs on its own: one asking you to sign in again is named in Settings, and the others keep syncing. Two accounts for the same card can be merged, transactions and balances included.
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

## Which card should I use here?

**Overview → Which card should I use here?** asks for your location once, on that tap, finds the nearest place through MapKit, and
ranks your cards for what that place sells. Location is used while the app is open, never leaves the device, and is never sent to the
backend.

Earn rates are not hard-coded to any particular card. `POST /api/card-rewards` looks up whatever card your bank reported — Plaid's
`official_name`, e.g. "Blue Cash Everyday®" — from what the issuer publishes, and caches the answer for two weeks. That needs `GEMINI_API_KEY` in `backend/.env` — a Google AI Studio key, whose free tier covers 5,000 grounded lookups a month.
Without it, or without permission to ground against Google Search, the lookup returns a clear error and you enter rates by hand in
Settings → the account → Rewards. It never falls back to an ungrounded answer: a model recalling last year's rotating categories from
memory is worse than no answer at all. Either way the rates are yours to correct, and every one carries the window it applies to: a rate outside its
window does not count, and one that has just lapsed is called out rather than quietly dropped.

Only credit cards are ranked. A tie is left as a tie instead of picking a winner.

## Running the backend somewhere other than your laptop

The app asks the backend for bank sync, card rewards and nothing else; receipts are read on
the device. **Import › Sync server** is where its address lives, along with the access token.
On the simulator the default — `http://localhost:5100` — is right, because the app and the
server share a machine. On a real phone `localhost` is the phone, so it has to be told where
to look: either the machine's address on the same network (`10.0.0.5:5100`) or a public
`https://` one.

Every `/api` route requires an access token. The app does not ask you to type it: **Import ›
Sync server** takes a name and a password, `POST /login` trades them for the token, and only the
token is kept, in the keychain. Who may sign in comes from `BACKEND_USERS`, a comma-separated
list of `name:salt:scryptHash` — never a password, so neither the environment nor a log can leak
one. Add someone with:

    node -e "const c=require('crypto'),s=c.randomBytes(16).toString('hex');console.log(`NAME:${s}:${c.scryptSync(process.argv[1],s,32).toString('hex')}`)" 'their password'

Guessing is throttled to eight tries per address every fifteen minutes. `node backend/test-login.js`
exercises the whole of it against a throwaway user.

The token itself still exists underneath. The backend mints one on first run, keeps it at
`backend/data/access-token.txt`, and prints it when it starts; paste that into the app. Set
`BACKEND_ACCESS_TOKEN` to supply your own instead, and change it to revoke a device.

### Deploying to Render

`render.yaml` is a blueprint: point Render at this repo and it reads it. Two things to know
before you do.

A free web service **has no persistent disk** and its filesystem is erased on every deploy and
every spin-down — which happens after 15 minutes without traffic. Linked banks are kept in
that filesystem, so on a free plan they need somewhere else to live, and the backend sends
them to a key/value store when `KV_REST_API_URL` and `KV_REST_API_TOKEN` are set. Any store
speaking Upstash's REST shape works. Access tokens are encrypted before they leave the
process, so the store never holds one in the clear.

A free service also **sleeps**, and the first request after it wakes takes most of a minute.
The app waits that out rather than reporting a failure, but the first sync after a quiet spell
is slow, and the Check button may need a second press.

    1. Create a key/value database and copy its REST URL and REST token.
    2. Generate an access token:
       node -e "console.log(require('crypto').randomBytes(16).toString('hex'))"
    3. New › Blueprint on Render, pick this repo, and fill in the values it asks for:
       PLAID_CLIENT_ID, PLAID_SECRET, STORAGE_ENCRYPTION_KEY, BACKEND_ACCESS_TOKEN,
       GEMINI_API_KEY, KV_REST_API_URL, KV_REST_API_TOKEN.
    4. In the app, set Import › Sync server to the https address Render gives you, paste the
       access token underneath, and press Check.

Because the filesystem is wiped, `BACKEND_ACCESS_TOKEN` must be set on a hosted deployment:
otherwise a new token is minted on every restart and every paired device starts being refused
for no visible reason. The backend refuses to start in that state rather than let you find out
later.

## Data and scope

All amounts are integer cents in USD. Income is excluded from spending totals. Recorded account balances use all transactions and the opening balance, rather than a live bank balance. There are no budgets or savings goals; the app tracks what you spent, not what you planned to.

Receipt images are processed with Apple's on-device Vision text recognition; the app keeps reviewed fields and extracted text, not the original image.

Bank sync goes through Plaid and requires the local backend in `backend/` and your own Plaid credentials; connections are read-only and scoped to transactions. This version does **not** connect to Apple Wallet, Google Sheets accounts, or Excel accounts; it does not read `.xlsx` directly. Card recommendations compare published earn rates; they are not an offers feed. No API exposes Amex Offers or similar, so nothing here claims a discount is available — only what a card earns by category, with the date that rate was looked up. Insights are deterministic calculations. There is no fraud detection or App Store deployment in this project.

A bank first reports a purchase while it is pending, under a raw card descriptor and with no category, then re-reports it enriched once it posts. A cursor sends each of those changes exactly once, so a sync that reads only new rows leaves the first version frozen forever — which is how nearly everything ends up filed under Other. `POST /api/resync` forgets every cursor and replays full history; rows already stored are repaired in place rather than duplicated.

Accounts used to be a single catch-all the import picker named, which every linked bank was filed into; a saved file from before that change is split per bank on load, and the old catch-all is renamed to Cash when it still holds hand-entered rows and dropped when it does not. An account you made yourself is never renamed or removed.

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
