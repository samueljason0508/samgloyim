# 🌱 PocketBloom

**Your money, in your pocket — not on someone's server.**

> Devpost submission copy. Two placeholders are marked **[TODO]** — fill them before submitting.

---

## Inspiration

I went out for barbecue with friends, then filled up a car with terrible mileage. Two completely ordinary evenings. And at the end of the month I couldn't answer either of the two questions I actually cared about: how much am I spending eating out, and what is this car really costing me?

I didn't write either purchase down. Nobody does. That's the part budgeting apps get wrong — they assume the failure is discipline, when really the system asks you to act at exactly the moment you're least likely to cooperate.

And the money isn't in one place. The average American actively uses **3.7 credit cards**, and the average consumer holds **five to seven accounts across different providers** that don't talk to each other. Meanwhile **40% of college students** say money is a source of stress and **64% wouldn't know where to find help** (CFP Board, *Dollars & Sense*, 2,025 students surveyed, 2025).

This started as a sprawl of Google Sheets covering different parts of life, none of which ever stuck — because nothing kept them in sync with what was actually being spent.

**[TODO]** — this section is written in the first person. Swap "I" for whichever teammate it belongs to.

## What it does

PocketBloom answers one question — **where did my money actually go?** — and asks nothing of you to do it.

**No setup.** No categories to invent, no budget to define, no sign-up. You open it and it already has an answer. We removed budgets and savings goals on purpose: the app tracks what you *spent*, not what you *planned to*.

**Every card, one picture.** Connect your banks once; each gets its own account automatically and transactions arrive on their own.

**Categories two levels deep.** Sixteen top-level buckets mirroring the bank's own primaries, so nothing falls through to "Other" — and under each, the bank's detailed category kept verbatim, so *Food & drink* opens into Fast food, Restaurant, Vending machines. Anything you categorise by hand is pinned, and no sync overwrites it.

**Receipts that file themselves.** Photograph a receipt; Apple's Vision framework reads it on the device in about a second. It then matches the total to the card purchase it belongs to rather than creating a duplicate — because your bank already told us about that purchase, it just didn't tell us what was in the basket.

**Which card should I use here?** One tap finds the shop you're standing in and names the card that earns most there — and if we don't know your card's rates, we look them up.

**A chart you can interrogate.** Drag a finger across the month to read any single day.

**Numbers you can defend.** Money moved between your own accounts — card payoffs, transfers, cash withdrawals — is recorded but excluded from spending, so one transfer doesn't swamp your month.

## How we built it

- **iOS, fully native** — Swift, SwiftUI, Swift Charts. No third-party UI frameworks.
- **On-device OCR** — Apple Vision for receipts. The image is never stored or uploaded; we keep only the fields you confirm.
- **Location** — MapKit and CoreLocation identify the shop you're in, so there's no merchant database to build.
- **Reward-rate lookup** — **Gemini 3 Flash with Google Search grounding** answers "what does this card earn, by category, right now?" for a card nobody hardcoded. Rates are cached with a TTL and fully editable, because a rotating category changes quarterly and a stale rate is worse than none.
- **Bank sync** — a Node/Express service holds the Plaid credentials, because API keys can be extracted from any app binary and must never ship inside one. Every route requires an access token; bank tokens are encrypted with AES-256-GCM before they ever leave the process.
- **Read-only by construction** — the Plaid token is enrolled in exactly one product: `transactions`. A payment or transfer call is rejected *by the provider*, not merely unimplemented. Even a compromised build couldn't move a penny.
- **Deployable** — a Render blueprint, with linked banks kept in a key/value store because a free host wipes its filesystem on every deploy.
- **Storage** — atomic JSON, versioned schema, integer cents throughout so there's no rounding drift.
- **CI** — every push builds an `.ipa`; tagging a version publishes a release. Unit tests cover the money logic; UI tests drive the real app end to end.

**What actually leaves your phone:** your bank tokens, encrypted, on a service you deploy yourself — and a card's *name* when you ask what it earns. Never a transaction. Never a balance. There's no account to sign into because there's nothing to sign into.

## Challenges we ran into

Every bug that mattered was invisible in normal use. **In a finance app, the dangerous bugs don't crash — they produce a number that looks plausible.**

**A whole day lost to a time zone.** Banks send a date with no time and no zone. We read it as UTC, which west of London is the *previous evening*. Every synced purchase was dated a day early — so purchases on the 1st fell into the previous month, and duplicate detection, which compares calendar days, could never match a bank row against the same purchase from a receipt. One line of code, three broken behaviours.

**Everything filed under "Other."** We assumed our categorisation was too coarse. It wasn't. Banks report a purchase while it's still *pending*, before they know the merchant, then re-report it enriched once it posts. We were keeping the new rows and discarding the corrections. The data was there the whole time.

**A transfer is not spending.** Moving money between your own accounts counted as an expense, so a single large transfer accounted for most of a month's apparent spending.

**Receipts that read as two columns.** On a widely spaced receipt, Vision returns every label first and every price afterwards, so "TOTAL" ends up nowhere near its number. We chose not to bolt on a fragile guess — those fall through to manual mapping.

**Grounded search won't mix with structured output.** The Gemini API refuses to combine a search tool with a response schema, so the JSON shape had to be asked for in the prompt and validated on the way back rather than enforced by the API.

## Accomplishments that we're proud of

**A matcher that refuses to guess.** A receipt matches a purchase only if the total is equal *to the cent* within a few days. A near miss is never rounded onto the closest purchase, and if two fit equally well we report **no match** and hand you the choice — a wrong match is worse than none, because you'd trust it.

**AI used for the one thing it's good at.** The model looks up published reward rates. It never touches your transactions, and it never does arithmetic — every number on screen is computed in Swift from your own data.

**Privacy that's structural, not promised.** Read-only enforced at the provider; tokens encrypted; transactions never transmitted.

**We learned to distrust our own output.** Every bug above was found by opening the app against real bank data and checking what it showed — not by re-reading the code we'd just written. The code looked right. The output was wrong.

**[TODO]** — add a line about first-time technologies for your team (first native iOS app? first financial API? first time using Vision or MapKit?). Judges reward this and it has to come from you.

## What's next

- **Receipt line items** — split one receipt across categories, so a supermarket run isn't a single lump.
- **"You left $47 on the table."** We already know every transaction's merchant and category, and each card's earn rate. Running that *backwards* over your history tells you exactly what using the wrong card cost you.
- **Recurring charges** — the pattern is already in the ledger; surface subscriptions and flag price hikes.
- **Encrypted backup** — the honest cost of local-first: if the data only lives on your phone, you need a way back when the phone doesn't.

---

## Sources

- Experian, June 2025 — average of 3.7 actively used credit cards per person
- MX, account aggregation research — 5–7 financial accounts per consumer
- CFP Board, *Dollars & Sense* — 2,025 U.S. college students, Sept–Oct 2025, ±2.2% at 95% confidence
