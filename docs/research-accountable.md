# Research: Accountable (accountable.de / accountable.eu)

**Date:** 2026-09-12
**Method:** Web search and fetches of accountable.de, accountable.eu, App Store/Google Play listings, help center articles, blog posts, Trustpilot, OMR Reviews, and independent blog reviews. Competitor data pulled from each vendor's own pricing pages. No first-party account was created; nothing here comes from using the product directly.
**Verification key:** items are VERIFIED (explicit statement found on an official source), PARTIALLY VERIFIED (feature's existence confirmed but a detail like exact mechanism is inferred), or UNVERIFIED / COULD NOT CONFIRM (third-party claim only, or no source found). Ratings/counts drift over time; treat exact numbers as approximate.

---

## 1. Products and Plans

Accountable operates in **Germany (accountable.de) and Belgium (accountable.eu)** only. The research brief assumed France/Netherlands operations as well; this could not be confirmed and is likely incorrect — accountable.eu is Belgium-specific with FR/NL language variants, not separate country products. [accountable.eu](https://www.accountable.eu/)

### Germany (accountable.de) pricing — [source](https://www.accountable.de/preise/)

| Plan | Monthly | Annual (per mo) | Target user | Key inclusions |
|---|---|---|---|---|
| Rechnungen Free | €0 | €0 | Starters | Unlimited e-invoices (ZUGFeRD/XRechnung), 5 expenses/mo, 1 bank connection, free business account + virtual Mastercard, mobile-only |
| Rechnungen Plus | €12.40 | €9.90 | Invoicing-only freelancers | + quotes, recurring invoices, web+mobile, unlimited AI tax advisor |
| Buchhaltung | €24.90 | €19.90 | Kleinunternehmer needing full bookkeeping | + unlimited expenses, 5 bank connections, free year-end tax docs |
| Steuern ("most popular") | €37.40 | €29.90 | VAT-liable self-employed | + UStVA submission, EÜR/ESt annual return, Zusammenfassende Meldung, €500 tax guarantee, tax-coach chat |
| Max | €74.90 | €59.90 | Users wanting hand-holding | + personal tax coach, 4 consultations/yr, €10,000 tax guarantee, physical card; 12-month minimum term |

Add-ons: Anlage KAP / Anlage V forms €19.90–24.90 one-time; extra "Banking Space" €1/mo; physical card €7.50 one-time. [source](https://www.accountable.de/preise/)

App Store in-app-purchase SKUs use different names/prices than the site (INVOICING+ €14.99, GROW €22.49, BOOKKEEPING €30.00, PRO €40.90, TAXES €44.49, PRO MAX €54.00) — likely stale IAP naming, flagged as a discrepancy. [App Store listing](https://apps.apple.com/de/app/accountable-f%C3%BCr-selbstst%C3%A4ndige/id1384729810)

Belgium pricing differs (e.g. Taxes €20.90 non-VAT / €29.90 VAT-subject, Max €51.50–59.90 depending on tenure). [source](https://www.accountable.eu/en-be/pricing/)

**Free trial:** No explicit time-boxed trial found on accountable.de itself; the free tier is permanent, and paid plans carry a "30-Tage-Geld-zurück-Garantie" (30-day money-back guarantee) instead. Third-party sites claim a "14-day free trial" — UNVERIFIED against accountable.de directly. [source](https://www.accountable.de/preise/)

**Steuerberater partnership:** Accountable refers users into its own partner network of independent tax advisors (not "bring your own advisor"); referral is free for both sides. À-la-carte pricing: document review €3/doc, 30-min consult €79, income tax return prep €475, audit support €158/h (all +VAT). [source](https://www.accountable.de/steuerberater/)

No standalone one-off "just file my tax return" product was found; all filing sits inside subscriptions plus the à-la-carte advisor services above. COULD NOT CONFIRM otherwise.

---

## 2. Feature Inventory

### Income / invoicing
Unlimited invoices free on every tier, including e-invoice formats **XRechnung, ZUGFeRD, PEPPOL**; quotes and recurring/installment invoices from the Plus tier; multi-currency, logo templates, payment reminders. [accountable.de](https://www.accountable.de/), [App Store](https://apps.apple.com/de/app/accountable-f%C3%BCr-selbstst%C3%A4ndige/id1384729810)

### Expenses and receipt capture (AI)
Photo/PDF receipt upload; OCR extracts date, amount, vendor, invoice number; auto-suggests expense category and pre-fills VAT rate by expense type; described as "self-learning" (remembers vendors over time); duplicate detection, splitting one receipt across categories, missing-receipt reminders. Free tier capped at 5 expenses/mo; unlimited from Buchhaltung tier. [blog](https://www.accountable.de/blog/ausgaben-accountable/), [blog](https://www.accountable.de/blog/ki-buchhaltung-tools/)

### Banking and payment matching
Free business account is white-labeled banking-as-a-service via **Swan**, not Accountable's own banking license; includes virtual Mastercard, Apple/Google Pay, automatic tax-reserve set-aside. Separately, PSD2/open-banking connections to external banks auto-detect invoice payments (1 connection free, up to 5 on paid tiers). No FinTS/HBCI found. Exact transaction-matching logic (amount+reference vs. ML) not documented. [blog](https://www.accountable.de/blog/swan-accountable/), help center (via search)

### VAT (UStVA, ZM, Kleinunternehmer)
UStVA preparation/submission from the Steuern tier; Zusammenfassende Meldung explicitly listed in that tier. Kleinunternehmerregelung (§19 UStG) is a first-class target segment with its own landing page and blog content on reverse-charge (§13b) obligations that persist even for Kleinunternehmer. Whether reverse-charge/EU B2B handling is automated in-app (vs. explained in blog posts) is unverified. [pricing](https://www.accountable.de/preise/), [Kleinunternehmer page](https://www.accountable.de/steuer-app-fuer-kleinunternehmer/), [blog](https://www.accountable.de/blog/reverse-charge-verfahren-kleinunternehmer/)

### Income tax (EÜR, ESt, Anlage S/G, deadlines)
EÜR generation from Buchhaltung/Steuern tiers; ESt annual return from Steuern/Max. Dedicated guides exist for **Anlage S** (freelance) and **Anlage G** (trade) income, strongly implying in-app support, but auto-population of these specific Anlage forms was not directly confirmed (PARTIALLY VERIFIED). Deadline reminders exist via push notifications. [blog](https://www.accountable.de/blog/anlage-s-steuererklaerung/), [blog](https://www.accountable.de/blog/anlage-g/)

### ELSTER submission
Marketing copy explicitly claims direct submission to the Finanzamt via ELSTER for UStVA, EÜR, and Gewerbesteuer, "alles in einer App," without needing an accountant. The underlying technical mechanism (Accountable holding its own ELSTER certificate / RFC-based submission vs. a prepare-then-user-authorizes flow) is not documented anywhere found — flag as VERIFIED marketing claim, UNVERIFIED mechanism. [App Store listing](https://apps.apple.com/de/app/accountable-f%C3%BCr-selbstst%C3%A4ndige/id1384729810), [accountable.de](https://www.accountable.de/)

### Tax coach / AI tax advice
Two distinct layers: a 24/7 **"KI Steuerberater"** AI chat trained on German tax law, answering from the user's own data, with an explicit disclaimer that it can be wrong and is not a certified advisor; and human **"tax coaches"** with tier-gated access (chat on Steuern, dedicated coach + quarterly calls on Max). AI advisor access starts as low as the Plus tier ("unlimited AI tax advisor"). [KI Steuerberater page](https://www.accountable.de/ki-steuerberater/), [pricing](https://www.accountable.de/preise/)

### Steuerberater collaboration
No "invite your own external advisor" feature was found; collaboration works through (a) Accountable's own referral network (see §1) or (b) a DATEV export a user's own advisor can import. [help center](https://www.accountable.de/en/help-center/datev-export-in-accountable-2/)

### Mobile vs. web vs. desktop
Native iOS and Android apps (App Store 4.7/5 ~3.7k ratings; Google Play ~4.6/5 ~4.6k reviews per search summary, unconfirmed by direct fetch). Free tier is mobile-app-only; a browser-based web app unlocks from Plus tier up. No native macOS/Windows desktop app found. [App Store](https://apps.apple.com/de/app/accountable-f%C3%BCr-selbstst%C3%A4ndige/id1384729810), [pricing](https://www.accountable.de/preise/)

### Exports
DATEV export: CSV of all bookings (income, expenses, bank transactions) plus a receipts.zip keyed by document ID, configured with chart of accounts / client number / advisor's DATEV number. One review site independently calls this DATEV export "fehlerhaft" (buggy) and says the company has acknowledged it needs rework. Generic CSV/PDF export exists but wasn't independently documented outside the DATEV flow. [help center](https://www.accountable.de/en/help-center/datev-export-in-accountable-2/), [review](https://e-rechnung-vergleich.de/accountable-test/)

### Integrations
Swan for banking infrastructure; Stripe/PayPal/Apple Pay appear only as *Accountable's own subscription billing* payment methods. No evidence of Stripe/PayPal/Amazon as income-side connectors (auto-importing a user's own marketplace/processor sales) — likely does not exist. Third-party aggregator (not accountable.de) lists a broad roster of connectable German banks (N26, DKB, ING, Sparkassen, Commerzbank, Wise, bunq, etc.) — unverified against Accountable's own current list. [blog](https://www.accountable.de/blog/swan-accountable/), [third-party](https://www.kontofinder.de/banken/accountable/)

### Onboarding
Structured questionnaire: self-employed y/n → duration (<1yr vs >1yr, which drives pricing shown) → legal form → VAT number/status → principal vs. side activity → days worked → Kleinunternehmer-equivalent exemption status → optional profession → promo code → account creation, then bank connection and reminder preferences. [help center](https://www.accountable.de/en/help-center/guideline-for-accountable-users/)

### Notifications and reminders
Push notifications for upcoming filing deadlines and amounts owed, always visible in-app; no distinct "email digest" feature confirmed. [blog](https://www.accountable.de/blog/umsatzsteuervoranmeldung-was-passiared-wenn-ich-eine-frist-verpasse/)

### GoBD claims
Strong, specific claim (quoted): archives receipts "revisionssicher," booked documents cannot be deleted or content-edited (only reversed/storniert), every action is logged with timestamp + user ID, data held on EU servers with automatic 10-year retention, and each uploaded receipt is hashed at save time so later tampering is detectable; once linked to a booking a receipt becomes read-only. [blog](https://www.accountable.de/blog/gobd-konform/)

---

## 3. Review Sentiment

| Source | Rating | Notes |
|---|---|---|
| Apple App Store (DE) | 4.7/5, ~3,700 ratings | [link](https://apps.apple.com/de/app/accountable-f%C3%BCr-selbstst%C3%A4ndige/id1384729810) |
| Google Play | ~4.6/5, ~4,600 reviews (unverified by direct fetch) | [link](https://play.google.com/store/apps/details?id=com.hivearts.accountable) |
| Trustpilot (.eu) | 4.7/5, 1,111 reviews | [link](https://www.trustpilot.com/review/www.accountable.eu) |
| Trustpilot (.de) | 4.6/5, 412 reviews; Trustpilot itself flags review-solicitation concerns | [link](https://www.trustpilot.com/review/accountable.de) |
| OMR Reviews | 4.8/5, 80 reviews | [link](https://omr.com/en/reviews/product/accountable) |
| Reddit | No usable discussion found (search/fetch blocked); treat as inconclusive, not "no sentiment" | — |
| Independent blogs | Mostly 4.2–4.7/5 equivalent framing | [mariuskiesgen.de](https://mariuskiesgen.de/accountable/), [e-rechnung-vergleich.de](https://e-rechnung-vergleich.de/accountable-test/), [onlinebilanz.de](https://onlinebilanz.de/accountable-erfahrungen-steuer-app-selbststaendige/) |

Note: capterra.com/p/135001/Accountable is an unrelated US healthcare-compliance product of the same name — excluded.

**Top praise themes:** (1) intuitive UI approachable for non-accountants, consistently the #1 theme everywhere; (2) cost/time savings vs. a traditional Steuerberater (framed as replacing ~€800–2,000/yr advisor relationships); (3) responsive support, both the AI tax advisor (praised for removing embarrassment around "stupid questions") and human tax coaches.

**Top complaint themes:** (1) bank/PayPal sync bugs, the most repeated technical gripe across Trustpilot, Play Store and OMR; (2) structural ceiling — no reliable DATEV export ("fehlerhaft," acknowledged by the company per one reviewer) and no support for GmbH/UG or accrual accounting; (3) pricing/paywall transparency — one reviewer reported income-declaration features hidden behind an undisclosed paywall discovered only at annual filing time, plus occasional slow premium-support follow-through (one case: a month-long delay).

---

## 4. Competitor Comparison

One line each; DE pricing, monthly, current promos may differ from list price.

| Product | Positioning | Price (from) | Invoicing | Expense AI/OCR | Bank feed | UStVA/ELSTER | EÜR | DATEV | Steuerberater access | Platforms |
|---|---|---|---|---|---|---|---|---|---|---|
| **Accountable** | AI-first, no-accounting-knowledge tax app for freelancers | Free–€59.90/mo | Yes, incl. free tier | Yes (OCR + auto-category + VAT rate) | PSD2, up to 5 connections | Direct claim, mechanism unverified | Yes | Yes, reported buggy | Referral network only | iOS, Android, web (no desktop) |
| **Lexware Office (lexoffice)** | DE market leader, invoicing-to-bookkeeping suite | €3.95–16.45/mo promo (list €7.90–32.90) | Yes, incl. e-invoicing | Belegscanner (OCR capture) | Present, provider count unverified | Direct ELSTER, no separate certificate needed | Yes (tier L+) | Unverified (not confirmed) | Yes, all tiers | Web + mobile |
| **sevdesk** | Cloud accounting from freelancer to SME, DATEV-centric | Free–€13.95/mo promo (list €25.90+) | Yes, ZUGFeRD/XRechnung | "KI-gestützte Belegerfassung" | Yes, 4,000+ banks | Direct ELSTER, no certificate needed | Yes, + GuV/BWA | Yes, explicit, SKR03/04/07 | Yes, DATEV portal | Web + mobile |
| **WISO MeinBüro** | Established Buhl-brand suite, invoicing to inventory | €10.90–69.90/mo (annual-equivalent) | Yes, e-invoicing | OCR + full-text search only | Yes, BaFin-licensed | Direct ELSTER, explicit | Yes | Yes, explicit, SKR03/04 | Yes, portal | Web + mobile (legacy desktop unclear) |
| **Kontist** | Business bank account with bundled bookkeeping | Free–€25/mo | Via bundled sevdesk, not native | AI categorization (Plus tier only) | Native (it's a bank) | UStVA only on Plus, sole proprietors only | Not native (via sevdesk bundle) | Plus tier only | Implied via DATEV export, no portal | Web + mobile |

Cross-cutting: DATEV/SKR03-04 export and direct ELSTER submission are **category baseline** for the three DE-native accounting incumbents (Lexware, sevdesk, WISO); banking-first players (Kontist, and reportedly Finom) gate these behind top tiers or lack them, making Accountable's positioning closer to Kontist than to the accounting incumbents. [Kontist pricing](https://kontist.com/pricing/)

---

## 5. Backlog Candidates for Pfennig

Given Pfennig is local-first, macOS-native, single-user, document-driven (not invoice-first), and explicitly out to avoid ERP scope (concept.md §2, §3), the following ideas are worth stealing, each with rationale and rough size:

- **AI receipt field extraction (date/vendor/amount/VAT rate)** — Accountable's pattern of pre-filling the *VAT rate* by expense type, not just amount/vendor, is a useful reference. Pfennig keeps provenance internal rather than adding field-level provenance badges. **S**
- **GoBD claim language and mechanics (hash-on-save, read-only once linked, audit log)** — Pfennig already has a GoBD posture (§5.9); Accountable's public wording (hash detection, storno-only corrections) is a good template for our own documentation and for what "immutable once posted" should mean in the UI. **S**
- **Deadline/reminder surfacing for UStVA and ESt** — a lightweight local notification of upcoming filing deadlines fits an AI-first, low-friction app without expanding scope into filing itself. **S**
- **"Ask the AI why" tax-context chat scoped to the user's own data** — not a general chat interface (explicit non-goal, §3, §8.1), but a narrow, read-only "explain this categorization/this VAT treatment" affordance on a transaction could deliver similar user trust without becoming a chatbot-first product. **M**
- **Recurring-expense / subscription detection** — Accountable auto-recognizes repeat vendors; useful for reducing review load on SaaS/telecom expenses, aligns with "review exceptions, be done" north star (§50). **M**
- **Duplicate-receipt detection** — already implicitly needed for Pfennig's document/transaction linking (§25 Duplicate Detection exists); Accountable's approach (flagging near-identical receipts) validates this is worth prioritizing early. **S**
- **DATEV/SKR mapping as a future adapter, kept out of the core category model** — Pfennig's concept.md already anticipates this (§2.2, §3: "future adapter maps canonical categories to accounts"); Accountable's own DATEV export being widely reported as buggy is a cautionary tale to get the mapping right rather than ship it half-baked. **L**
- **Split one document across multiple categories/allocations** — Accountable supports splitting a single receipt line across categories; Pfennig's `bookkeeping_allocations` table (§17.6) suggests this is already modeled, worth confirming the UI supports it as cleanly as this. **S**

**Do not copy** (conflicts with Pfennig's explicit non-goals, §3):
- Invoice creation, quotes, and recurring/installment invoicing as a product pillar — explicit non-goal; Pfennig is transaction/document-first, not an invoicing tool.
- Bundled business bank account (Swan-powered) — direct bank connections and payment features are out of scope (§3: "Direct bank account connection (PSD2/FinTS)"); Pfennig only imports statement files.
- Primary AI chat / "KI Steuerberater" as a standalone product surface — explicit non-goal (§3: "Primary chat interface", §8.1); any AI-explains-data affordance must stay secondary to the transaction table.
- Direct ELSTER submission — explicit non-goal for V1 (§2.2, §3); Pfennig should not attempt to become a filing channel.
- Multi-tier subscription upsell structure gating core bookkeeping features (e.g. expense limits on a "free" tier) — inconsistent with a locally-owned, single-purchase or simple-license product; also a recurring source of the "hidden paywall" complaints seen in reviews.
- Steuerberater referral marketplace / a-la-carte advisor billing — business-model territory unrelated to the product's scope, and a distraction from the core "drop documents, review, done" loop.
- GmbH/UG double-entry and Soll-Versteuerung support — explicitly out of scope for V1 (concept.md §2.1, §2.2); resist scope creep even though competitors treat it as a growth path.

---

*Compiled by an AI research agent; all facts above should be spot-checked before use in customer-facing material, particularly items marked UNVERIFIED or PARTIALLY VERIFIED.*
