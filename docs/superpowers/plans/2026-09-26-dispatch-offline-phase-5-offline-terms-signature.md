# Dispatch Offline Phase 5 — Offline Terms & Conditions + Signature — Implementation Plan

> **Status: APPROVED for implementation (Gary, 2026-09-26) under the corrected model: an order's terms are frozen when the order is created.** This revision replaces the first draft (`f17d1f1`), which assumed live terms, stale signatures and re-signing after template changes. None of those remain.
> Rules for execution: TDD task by task (failing test → prove the failure → minimum code → focused and regression tests → review the diff → local commit). Local only: no push, merge, deploy, publish, SSH, production data, feature flag, version/build bump, archive or App Store upload. Neither `main` is touched. Phase 6 and the cross-customer Sync Engine queue issue are out of scope.
> **Phase 5 is finished only after all of these pass (§9):**
> - the backend identity, parity, idempotency and binding tests (§8.1);
> - every mobile case in §8.2–§8.3, including the automated never-opened acceptance scenario;
> - the complete relevant backend regression, with explicit web-signing coverage;
> - the complete mobile core and signed hosted suites;
> - the simulator build, the no-polling gate, and the manifest ceiling of **450 statements (hard)**;
> - a fresh independent reviewer reporting no Critical or Important issues.
>
> Then stop and report; nothing is pushed or deployed.

**Goal:** a Dispatch mission that was **never opened while online** supports, with the iPhone **completely offline**:

`cached Dispatch → Driver Checklist → Order Details → Terms & Conditions → customer acceptance/signature → continue completion`

The signature is durable on the phone the moment it is captured, the workflow advances on that local evidence, and it later syncs to Laravel idempotently. It is always bound to **that order's frozen agreement** and its identity.

**Spec:** `docs/superpowers/specs/2026-09-22-dispatch-offline-mission-cache-design.md`: §8 "Terms & Conditions", §9, §17, §18 step 5, §20.

**Branches (local, no upstream):**
- Backend `feature/dispatch-offline-phase-5`, from Phase 4 HEAD `2f859c0a8`, in worktree `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline`.
- Mobile `feature/dispatch-offline-phase-5`, from Phase 4 HEAD `92daa7f`, in worktree `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p5`.

**Baseline (Phase 4 final):**
- Mobile core 499/499; signed hosted 72/72; simulator build OK.
- Backend Dispatch 591, Api 200, Mobile 15, Unit/Push 6, QueueLine 293, all passing.
- Backend Orders fails 23 and CustomerChecklists fails 11: the same tests by name as the Phase 2 baseline copy.
- `tests/Feature/Terms` and `tests/Feature/CustomerPortal` are captured at `2f859c0a8` before any change (Task 0).

---

## 0. The governing principle and what the code shows

### 0.1 The principle (Gary, 2026-09-26)
- **The terms applicable to an order are frozen when the order is created.** The agreement belongs to the order, not to the current catalog.
- **What the frozen agreement contains:**
  - the standard terms in force at creation;
  - every product addendum for the products originally on the order;
  - the order- and customer-specific substitutions shown to the customer.
- **What later changes do:**
  - Edits to company terms, product terms, product data or pricing apply only to orders created afterwards.
  - Removing a product never removes its addendum.
  - Additions are separate orders (a related order or an Order Enhancement), each with its own agreement and acceptance.
- **So an agreement never goes stale.** A signature is compared only with the order's own frozen agreement, never with current templates. There are no amendments and no re-signing after template changes.

### 0.2 Where the freeze happens today (confirmed)
- **The freeze point already exists.** It is `Front/Checkout/PostController`, the one code path that creates orders with products:
  - public web checkout;
  - admin checkout via impersonation;
  - reorders, which are related orders with `reference_order_number` and their own sequential number.
- **The mobile app's place-order endpoint is retired** (`Url.retired("place-order")`).
- **Inside that transaction** (`DB::beginTransaction()` line 128 … `DB::commit()` line 796):
  1. The order row is created (`$customer->orders()->create(...)`, with `customer_name = $customer->full_name`).
  2. Every order product is created.
  3. Then, at lines 611-619:
     - `$order->load(['products.product.terms'])` and `TermsContentHelper::generateTermsContent($order)`;
     - **`terms_collection`** = the merged, ordered entries `{id, unique_id, title, content, signature_block, is_global}` (the global terms first when any original product `is_general_term_type`, then each product's attached terms, deduplicated);
     - **`pending_terms_content`** = the rendered body;
     - `terms_status = Pending`;
     - `saveQuietly()`.
- **This is the business-level creation point, after the original products are attached, inside the creation transaction.** Phase 5 keeps it; it does not move or re-run it.
- **Nothing rewrites the stored copy afterwards.** No code writes `terms_collection` or `pending_terms_content` after checkout.
- **Nothing edits `orders.customer_name` after creation.** It is written only at checkout and copied once into an Order Enhancement at *its* creation. The frozen customer substitution is therefore the order's own column.

### 0.3 Related orders, Order Enhancements and product removal (confirmed)
- **Reorders** are new checkout orders, so each freezes its own `terms_collection` at its own creation, with its own unique id.
- **Order Enhancements** (`Admin/…/Orders/Extension/StoreController`) are **charge-only child orders** (`NNNN-A`, `reference_order_number` = parent):
  - they have no order products and no `terms_collection`;
  - they never enter the Dispatch working set, because the mission selector needs a Rental order product;
  - the parent's agreement and signature are never touched.
  - Under this model, an Enhancement has no stored agreement. Signing one fails safely (§3.5), which is truthful: it has no products and no terms.
- **Product removal** is a soft delete of the `order_products` row (`SoftDeletes`; Order's `deleting` hook). No removal path reads or writes the stored copy. Because the frozen agreement reads **only the order's own stored columns**, never `order->products`, removal cannot change it.

### 0.4 The existing web-signing defect
- **The signing page shows today's templates.** `index.blade.php` renders `generateTermsContent($order)`, which rebuilds from the current catalog, with a comment saying it does so deliberately.
- **The acceptance records the order's copy.** `PostController` writes `accepted_terms_content` from `terms_collection`.
- **The fix is not to record the live terms.** It is:
  1. load the frozen agreement;
  2. display it;
  3. record acceptance of that same agreement and identity.
- The phone path uses the same source (§3).

### 0.5 Other facts that shape the design (from the first inspection, still true)
- **The signing page is a public, CSRF-protected web route.** There is no terms content API and no API-authenticated acceptance endpoint.
- **The phone never holds the signature today.** The hosted page in a `WKWebView` submits it itself. The existing `terms.accept` op only posts `update-delivery-pickup-inputs`, which records `order_products.{delivery|pickup}_tnc_status`, a column nothing reads.
- **T&C is Delivery-only and order-level** (`LegCompletionRequirements`). Any durable `terms.accept` op satisfies it today.
- **The Sync Engine:**
  - enqueue is durable before it returns, and ops survive force-quit and restart;
  - assets are kept until acknowledgment, and needs-attention assets until a person discards them;
  - it never deduplicates;
  - `retryable:false` gives Needs Attention;
  - ops carry no tenant.
- **`TermsService` documents that acceptance is four columns on the order,** with no terms or signature record (pinned by `TermsRequestEmailTest`). Phase 5 keeps that rule: acceptance stays on the order.
- **The manifest runs 438 of its 450-statement ceiling** at 50 missions.
- **The app bundles no web resources today.** Its only native pad is the landscape checklist `EPSignatureView`.

---

## 1. Approach
1. **One server object, `TermsAgreement::forOrder($order)`**, reads **only the order's stored copy** (`terms_collection`, `customer_name`, `unique_id`, `terms_status`). It never reads templates, products or settings. It yields either:
   - an **available** agreement with a deterministic, version-prefixed identity; or
   - an explicit **unavailable** reason for an order without a trustworthy stored copy.
2. **The web page, the mission package, a small live endpoint and the acceptance write all use it.** No signing screen rebuilds an existing order's agreement.
3. **The phone** renders the packaged (offline) or freshly fetched (online) agreement in the existing T&C screen, as **inert content** in an app-owned local page with the bundled signature pad. It verifies the identity from the payload before showing anything.
4. **Signing** writes a durable Sync Engine op `terms.sign` (signature + identity), which satisfies T&C locally at once and syncs later.
5. **Laravel accepts only an exact match of order and identity.** Anything else is a verification or data-integrity failure, never "terms updated".

---

## 2. The frozen agreement and its identity

### 2.1 What is frozen, and from where
| Part | Source (stored on the order) |
|---|---|
| Standard terms + product addenda, in order | `orders.terms_collection` entries: `is_global`, `content`, `signature_block`. `id`, `unique_id` and `title` are not rendered and are left out of the identity. |
| Customer substitution (`[customer_name]` in the signature block) | `orders.customer_name`, or `"Customer"` when null. This is exactly what the checkout render and the acceptance render substitute, and it is written only at creation. |
| Order binding | `orders.unique_id` |

**Not part of the agreement (page chrome):**
- the Rental Agreement header lines;
- the order number line and instructions;
- the approval-checkbox and sign-button widget markup.

### 2.2 Canonicalization (`kabba-order-terms` v1, documented in code and in `MOBILE_API_CONTRACT.md`)
```
identity = "v1:" + lowercase-hex( SHA-256( canonical_bytes ) )

canonical_bytes = UTF-8 of, each line ending in "\n":
  kabba-order-terms:v1
  order:<L>:<order_unique_id>
  customer_name:<L>:<substituted customer name>
  entries:<N>
  then for i = 0 … N-1, in stored order:
    entry:<i>
    is_global:<1|0>
    content:<L>:<content>
    signature_block:<L>:<signature_block>
```
- **`<L>`** is the UTF-8 **byte** length of the value that follows. The length prefix makes the encoding unambiguous with no escaping.
- **Line endings in every value are normalized** (CRLF and lone CR → LF) *for hashing only*. Stored contents are never changed.
- **Null and `""` are equivalent**, as they are to the renderer. There is no trimming and no Unicode normalization.
- **The identity never depends on rendered HTML,** browser DOM, attribute order, widget markup or image availability.
- **It is bound to the order by construction:** two orders with identical text have different identities, so a related order or Enhancement can never share one.
- **A shared test vector** (`tests/Fixtures/mobile-contract/terms_agreement_identity.json`, copied into the mobile tests) pins PHP and Swift to the same bytes. It covers non-ASCII text, CRLF, and null/empty values.

### 2.3 Legacy and malformed orders (fail safe, never rebuilt)
`TermsAgreement::forOrder` returns **unavailable** with a stable reason, and never substitutes current templates, when:

| Reason | Condition |
|---|---|
| `no_stored_agreement` | `terms_collection` is null. Orders from before the snapshot column (2025-08-01) and Order Enhancements. |
| `malformed_stored_agreement` | Not a list; an entry that isn't an object; `is_global` not a boolean; `content`/`signature_block` not string or null; invalid UTF-8. |
| `empty_agreement` | The list is empty (no terms applied at creation). There is nothing to sign, so it is reported, not silently accepted. |

- **Any order with a valid stored copy is treated as immutable** and identified from its existing contents, whenever it was created.
- **Reporting:**
  - the API and web page state the reason;
  - a phone's attempt raises the existing Mobile Sync Issue;
  - `php artisan terms:agreement-audit` (**read-only**, no secrets) counts Pending orders by agreement status and reason, so the effect can be measured before any deploy.

### 2.4 Immutability backstop
The Order model refuses (throws on `updating`) any change to `terms_collection`, `pending_terms_content` or `customer_name` once `terms_collection` is set. Checkout's first write, from null, is unaffected, and so is `saveQuietly`. No existing code path makes such a change; the guard is there so that a future one fails loudly rather than silently changing an agreement.

---

## 3. Backend design

### 3.1 `App\Services\Terms\TermsAgreement`
- **Status:**
  - `available`: Pending with a valid stored copy;
  - `unavailable`: Pending, with a reason from §2.3;
  - `not_required`: Accepted or Exempt;
  - `not_signable`: Declined, which no code writes today.
- **Accessors:**
  - `identity()`, the canonical form in §2.2;
  - `entries()`;
  - `customerName()`;
  - `approvalsRequired()`, the count of `[customer_approval][/customer_approval]` placeholders in non-global entries, which is what the renderer turns into required checkboxes;
  - `contentHtml()`, which is `TermsContentHelper::generateTermsContentFromArray(entries, customerName)['terms_content']` (the web page body);
  - `acceptedContentHtml($signature)`, which is `generateAcceptedTermsContentFromArray(...)`;
  - `toArray()`, the wire shape in §3.2.
- **Reads only order columns:** no queries beyond the order row.

### 3.2 Wire shape of `terms` (package, and the live endpoint)
```json
"terms": {
  "status": "Pending",
  "page_url": "https://…/terms-and-conditions/ORD…/mobile",
  "offline_content_available": true,
  "agreement_status": "available",
  "unavailable_reason": null,
  "agreement": {
    "identity": "v1:<64 hex>",
    "order_unique_id": "ORD-…",
    "order_number": "#1234",
    "customer_name": "Jane Doe",
    "approvals_required": 2,
    "entries": [ { "is_global": true, "content": "…", "signature_block": "…" } ]
  }
}
```
- **`order_number` is presentation only** and is not part of the identity.
- **When `agreement_status` is not `available`:** `agreement: null`, `offline_content_available: false`, and `unavailable_reason` is set for `unavailable`.
- **Package sections:** `sections.terms` is `ok` | `unavailable` | `not_applicable` | `failed`.
  - `not_applicable` covers terms that aren't Pending, and every Return package.
  - `failed` means an isolated build exception, exactly like Phase 4's sections.
  - The agreement is built once per order in `withOrderSections`, **for Delivery packages only**.
- **Mission revision:** the seed gains `terms` = the identity (Pending and available), `"unavailable:<reason>"`, or `null`.
  - The value is frozen, so it never churns. `terms_status` is already covered through `dispatch.order`.
  - It adds **0** manifest statements: the value comes from columns of the already-loaded order.
- **Live `GET api/admin/v1/orders/terms/{orderUniqueId}`** (`auth:api_user`, read-only) returns `{success, data: <terms>}` for any order. A parity test proves it equals the package's `terms`.

### 3.3 Acceptance `POST api/admin/v1/orders/terms/{orderUniqueId}/accept` (op `terms.sign`)
The request is multipart, wrapped in `MobileOperationService` with ledger type `terms.sign`.

| Field | Rule |
|---|---|
| `terms_identity` | required, `v1:` + 64 hex |
| `signature_media` | required image (png/jpeg), max 2 048 KB |
| `approvals_confirmed` | required integer ≥ 0 |
| `order_product_unique_id` | nullable. When present it must belong to the order, and it records that line's `tnc_status` |
| `leg` | nullable, `delivery` \| `return` |
| `signature_client_media_id`, `captured_at` (device signing time), `operation_id` | the existing mobile contract |

- **An unknown order is refused before any write** (404; no ledger row, no issue, no file).

`TermsAcceptanceService` locks the order row (`lockForUpdate`) and checks, in this order:

| Order state | Outcome | Writes |
|---|---|---|
| Accepted | **200 `already_accepted`** | none (one acceptance per order) |
| Exempt | **200 `not_required`** | none |
| Declined, or agreement `unavailable` | **409 `TERMS_AGREEMENT_UNAVAILABLE`**, `retryable:false`, `data.reason` | none |
| `terms_identity` ≠ the order's frozen identity | **409 `TERMS_IDENTITY_MISMATCH`**, `retryable:false`, message **"Unable to Verify Order Terms — Refresh the Order Before Signing"** | none |
| `approvals_confirmed` < `approvals_required` | 422 terminal | none |
| Exact match | **200 `accepted`** | See the list below. |

On `accepted`, the service writes:
- on the order:
  - `terms_status=Accepted`;
  - `signature_image` = `data:image/png;base64,…` (the web format);
  - `accepted_terms_content` = `acceptedContentHtml`;
  - **`terms_accepted_at = now()`**, the authoritative server acceptance time;
  - **`terms_customer_signed_at = captured_at`** (device signing time, clamped by `MobileTimestamps`), stored as customer-action metadata;
- the line's `{delivery|pickup}_tnc_status='accepted'`, when a line was given;
- `OrderTermsSignedEvent` once.

**Idempotency and binding:**
- The ledger replays the original 200 for the same `operation_id`, so a lost acknowledgment converges to the same success.
- A different op id on an accepted order gets `already_accepted` and changes nothing.
- The row lock serializes a web signing and a phone signing.
- A signature only ever lands on the order named in the URL, and only when that order's own frozen identity equals the submitted one. It can never count for another order, including a related order or Enhancement.

**Registry entries:**
- `ApiErrorCode` gains `TermsIdentityMismatch` and `TermsAgreementUnavailable` (409, not retryable).
- `MobileSyncIssue::ACTIONABLE_OPERATION_TYPES` gains `terms.sign`, labelled "Customer Signature / Terms". A terminal rejection raises an order-scoped issue through the existing path.

### 3.4 Web signing correction
- **`IndexController` + view:**
  - A Pending order with an available agreement renders `TermsAgreement::contentHtml()`, the frozen copy, never `generateTermsContent($order)`, plus `<input type="hidden" name="terms_identity">`.
  - An unavailable agreement shows "We can't display the terms for this order. Please contact us." with no form.
  - A non-Pending order shows `accepted_terms_content`, unchanged.
- **`PostRequest`:**
  - `terms_identity` is required;
  - the approval rule reads `approvalsRequired()` from the frozen copy instead of searching `pending_terms_content`.
- **`PostController` → the same service (web channel):**
  - an exact match writes as today (the frozen copy, `terms_accepted_at=now()`, the event, the signed thank-you URL);
  - a mismatch or a missing identity (a page opened before the deploy) gives 409 `{success:false, message:"Unable to verify order terms. Please refresh the page before signing."}`;
  - unavailable gives 409 with the unavailable message;
  - already accepted returns success with the thank-you URL and **no second write**.
- **Unchanged:** the `terms.accept` ledger type for web posts that carry an `operation_id`, and the four-column record.

### 3.5 Required behavior matrix (server)
| Case | Result |
|---|---|
| Order created with frozen agreement A; A is signed | **Accepted** |
| Company templates later change A → B | The order stays A; a signature of A is **accepted** |
| Templates change before the customer signs | The order still displays and accepts A (web and phone) |
| Templates change after signing, before sync | The order still accepts A |
| Templates change A → B → A | No effect on the order |
| A product is removed from the order | The agreement is unchanged, including that product's addendum |
| A related order (reorder) is created | It has its own frozen agreement and identity and needs its own acceptance; the original is untouched |
| An Order Enhancement is created | It has no stored agreement (no products), so it is `unavailable: no_stored_agreement` and nothing is signed against it; the parent's agreement and signature are untouched |
| A successful acknowledgment is lost | The retry is idempotent and returns the original success |
| A signature is submitted with another order's identity | Rejected, `TERMS_IDENTITY_MISMATCH`, no acceptance write |
| The packaged identity doesn't match the order's frozen identity | Rejected as the same verification/data-integrity failure |
| Current web templates differ from the order's snapshot | Web signing displays and records the snapshot |
| A legacy order has a trustworthy stored copy | Its content is preserved and identified without regeneration |
| A legacy order lacks a trustworthy stored copy | Signing fails safely (`unavailable`); no templates are substituted |

---

## 4. Mobile design

### 4.1 Components
**Core (`swift test`; Foundation plus CryptoKit, a system framework, no UIKit):**
- **`TermsAgreement`:**
  - the model and decoder for `terms.agreement`, plus `agreement_status` and `unavailable_reason`;
  - `canonicalBytes` and `identity` (§2.2);
  - `isVerified` = the recomputed identity equals the supplied identity, and `order_unique_id` matches the order being signed.
- **`TermsAgreementRenderer`:**
  - builds the body the same way `generateTermsContentFromArray` does (the global content with the product addenda substituted, then the signature block);
  - uses **inert markers** (`<span data-kabba-approval>`, `<span data-kabba-sign>`) in place of widgets;
  - HTML-escapes the customer name.
  - Its output is presentation only; it is never hashed.
- **`TermsAgreementStore`:**
  - tenant-scoped and protected (the Amendment B pattern): `<KabbaSync>/terms-agreements/<tenant>/<orderUid>/<identity>.json` plus a newest pointer;
  - stores **verified agreements only**, and keeps each one (no pruning);
  - its freshness is the ledger's per-cache `terms` stamp (newest request time wins), written by the bridge or by a live fetch pinned to the requesting company.
- **Contract and bridge:**
  - `DispatchOfflinePackageSections.terms` (ok / unavailable / not_applicable / failed) and `DispatchOfflinePackageContent.termsAgreement`.
  - `DispatchOfflineFieldBridge` adds the ledger `terms` state and writes the store under the ledger lock only when the agreement verifies. An agreement that doesn't verify is `.invalid` (retryable at the same revision). `unavailable` is a new settled, non-retryable state.
- **Readiness (Amendment A):**
  - Delivery = context + order_details + assembly + terms satisfied or not applicable. An `unavailable` agreement means the Delivery is not fully prepared, and not retried either.
  - Return is unchanged.
  - A pre-Phase-5 server (no `sections.terms`) gives `notProvided`: settled, and T&C behaves as in Phase 4.
- **`TermsSignOperations`:**
  - the capture holds the order, identity, approvals confirmed, line + leg, employee, order number and `capturedAt`;
  - it is enqueued with a **PNG** asset (`terms-<order>`, `signature_media`);
  - the request is the POST in §3.3 with `X-Operation-Id` + `operation_id` + `captured_at`.
- **`EffectiveFieldState` / `LegCompletionEvaluator`:** the rule in §4.4. `LegCompletionInputs` gains `termsIdentity` (the store's verified identity for the order).

**App:**
- **Signing shell** (bundled resources `RentnKing/Resources/TermsSigning/`):
  - `terms-signing.html`, `.css`, `.js`, and `signature_pad.umd.min.js` 5.0.10 (the site's own library, MIT, license file included);
  - loaded with `loadHTMLString` and a nil base URL.
- **Inert rendering**, enforced in three layers:
  1. **A strict CSP:** `default-src 'none'; script-src 'nonce-<random>'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'`. This blocks every script the shell didn't bring, **inline event handlers, `javascript:` URLs,** embedded active content and **remote images** (so a missing image never matters and online and offline look the same).
  2. **The shell sanitizes the body before inserting it:** it parses it with `DOMParser` (an inert document), removes `script`, `iframe`, `object`, `embed`, `link`, `meta`, `base`, `form` and form controls, and every `on*` attribute, `href`, `src` and `srcset` with a non-`data:` scheme or with `javascript:`. Only then does it replace the inert markers with the app's own checkboxes and sign button.
  3. **Navigation:** `WKNavigationDelegate` allows only the initial local load and cancels everything else. Link clicks are prevented in the page.
- **The page's controls.** Submit requires every approval checkbox and a signature, then posts `{signature: <PNG data URL>, approvals_confirmed, identity}` to the `kabbaTermsSigned` handler (through a weak proxy) and disables itself.
- **`TermsAndConditionViewController`** (the same screen):
  - Its presentation comes from a pure resolver (§4.3).
  - **On a signing message** it checks that the identity equals the rendered, verified agreement's and that the data is a PNG under 2 MB. Once the durable `terms.sign` enqueue returns, it shows the existing toast, calls `termsSucess` and pops, like the thank-you path.
  - **If the enqueue fails**, it says so and flips nothing.
  - It never force-unwraps a navigation URL.
- **`TermsAgreementClient`:** the live GET on screen open when reachable. That one request replaces the hosted-page load; there is no polling. The result is saved through `saveLiveCopy(.terms, …)`, pinned to the company captured when it was sent.
- **Other app wiring:**
  - `TermsSignSyncHandler` is registered next to `TermsAcceptSyncHandler`. `terms.accept` stays for the hosted-page fallback and any already-queued ops; it is not overloaded.
  - Order Details and Order List pass `terms_status`. Order Details feeds `termsIdentity` into its leg-completion inputs.
  - `EmptyDataView` gains the new state copy.

### 4.2 Durable artifacts per signing
| Artifact | Where |
|---|---|
| Signature (PNG, the web pad's format) | Sync Engine asset `assets/terms-<order>/<clientMediaId>.png`, protected; kept after acknowledgment (as for checklist signatures) and while Needs Attention until a person discards it |
| Device signing time | op `capturedAt` → `captured_at` |
| Order identity | op identity `orderUniqueId` (+ `orderProductUniqueId`, the line whose workflow surfaced it) and the URL |
| Frozen terms identity | payload `terms_identity`; the verified agreement itself is kept in `TermsAgreementStore` under that identity |
| Approvals | payload `approvals_confirmed` |
| Idempotency key | the operation id (`X-Operation-Id` + `operation_id`) |
| Employee | payload `user_id`, identity `employeeId` |

### 4.3 Screen states (one pure resolver, unit-tested)
| Condition | Shows |
|---|---|
| Server `terms_status` Exempt | "Terms & Conditions aren't required for this order." |
| Server `terms_status` Accepted | "Terms & Conditions are already accepted for this order." |
| A healthy (pending / syncing / synced) `terms.sign` op for this order **at the verified identity** | "Signed on this phone" with its sync state. No second capture is possible (the engine doesn't deduplicate). |
| A verified agreement: the live copy when reachable, else the stored one | The local signing page |
| An agreement that fails verification (identity, or wrong order) | **"Unable to Verify Order Terms — Refresh the Order Before Signing"** |
| Server `agreement_status` unavailable | "This order has no stored terms agreement to sign. Please contact the office." |
| Offline, no stored agreement | "Terms & Conditions for this order aren't downloaded to this phone yet. Connect to the internet to load them." |
| Online, and the server has no agreement endpoint (404: an older server) with a valid `page_url` | The existing hosted page and its thank-you → `terms.accept` path (compatibility only) |
| Online, the fetch failed, and nothing is stored | "Couldn't load the Terms & Conditions. Check the connection and try again." |

### 4.4 Local satisfaction (Delivery; order-level)
T&C is satisfied when any one of these holds:
- **server truth:** Accepted or Exempt;
- **a legacy `terms.accept` op exists** (written only after the hosted page recorded acceptance on the server);
- **a healthy `terms.sign` op exists** for **this order** whose `terms_identity` equals the phone's verified identity for the order. If the phone holds no agreement, nothing contradicts the op, and it counts.

**A `terms.sign` op in Needs Attention never satisfies.** Its terminal causes (mismatch, unavailable, approvals) mean the signature was **not** accepted. It is kept for troubleshooting until a person discards it (or it is replaced by a new signing of the verified document). It is never relabelled.

**Consequences:**
- A signature can't count for another order: the identity is order-bound, and the match is on `orderUniqueId`.
- One signature covers every Delivery line of its order.

### 4.5 Tenant safety
- **`TermsAgreementStore` is tenant-scoped on read and write,** and writes nothing without a tenant.
- **Live saves** are pinned to the requesting company.
- **The A → logout → B offline → back to A test** covers the store.
- **`terms.sign` ops are not tenant-bound**, like every other op. §10.1 explains why that is not materially worse here.

### 4.6 Scenario behavior
| Scenario | Behavior |
|---|---|
| Never opened, offline, terms Pending | The bridge stored the verified agreement. Order Details → T&C renders it, the customer signs, and the op is durable. T&C is satisfied and Complete proceeds without the override. |
| Leave and reopen / force-quit / restart | The agreement, op and PNG are durable; the screen shows "Signed on this phone" and the tile stays satisfied. |
| Prolonged offline, then reconnect | The op retries (never exhausted) and syncs once. The answer is `accepted`, or a replay. The next orders/details or package shows Accepted. |
| Templates change at any point | Nothing on the phone or server changes for this order: its identity is frozen. |
| The package has the mission but no usable agreement (failed, or not verifying) | The mission shows in Dispatch but is not Delivery-ready. It is retried at the same revision when retryable. Offline T&C shows the not-downloaded or unable-to-verify state, never a blank page. |
| The server rejects the op (mismatch / unavailable) | The op goes to Needs Attention with its PNG kept, and T&C shows unsigned. After the order is refreshed, the customer signs the verified document (a new op). |
| Terms accepted elsewhere | Server truth satisfies T&C. A queued phone op gets `already_accepted`. |
| Return mission | Unchanged: T&C is not required. |

---

## 5. Decisions

**Approved by Gary (2026-09-26):**
- **Immutable order agreement.** It is frozen at creation, never regenerated, and there is no staleness or re-signing.
- **Identity.** A version-prefixed SHA-256 over the canonical frozen payload, bound to the order, excluding chrome.
- **Web path.** It displays and records the frozen copy.
- **Legacy orders.** A valid stored copy is used as-is; anything else fails safe.
- **Acceptance stays on the order**, with no history table.
- **One app-owned, local-first screen** online and offline.
- **The bundled MIT `signature_pad`** and inert rendering.
- **A dedicated `terms.sign` op**; `terms.accept` is not overloaded.
- **Delivery-only enforcement** and one acceptance per order.
- **Device signing time is metadata; server time is authoritative.**
- **The mismatch message** "Unable to Verify Order Terms — Refresh the Order Before Signing".
- **450 manifest statements is a hard ceiling.**

**Made within the approved model, recorded for review:**

| ID | Decision | Why |
|---|---|---|
| P5-A1 | Frozen customer substitution = `orders.customer_name` (or "Customer"), backed by the immutability guard (§2.4) | It is written only at creation. Recovering a name from the old rendered HTML is ambiguous, because the widget markup has changed over time. |
| P5-A2 | An `empty_agreement` is unavailable, not signable | Signing a blank agreement would record acceptance of nothing. It is reported instead. |
| P5-A3 | Order Enhancements have no agreement (`no_stored_agreement`) | They have no products or terms today, and no Phase 5 path adds any. Adding freezing to the Enhancement flow would be new scope. |
| P5-A4 | Remote images are blocked in the app's page | Inertness, and the same view online and offline. The identity is text-only, so an image can't affect it. |
| P5-A5 | A web post on an already-accepted order does not overwrite | One acceptance per order. The web path overwrote the signature before. |
| P5-A6 | A web post with a missing identity is rejected with the refresh message | A page opened before the deploy displayed today's templates, not the frozen copy. |
| P5-A7 | New nullable column `orders.terms_customer_signed_at` | It stores the device signing time on the order (no history table). |
| P5-A8 | A read-only `terms:agreement-audit` command | "Report the condition" for legacy orders before any deploy. |

---

## 6. Expected files and components

**Backend:**
- New:
  - `app/Services/Terms/TermsAgreement.php` (with its canonicalization);
  - `app/Services/Terms/TermsAcceptanceService.php`;
  - `app/Http/Controllers/Api/Admin/V1/Orders/Terms/ShowController.php`, `AcceptController.php`;
  - `app/Http/Requests/Api/Admin/V1/Orders/Terms/AcceptRequest.php`;
  - `app/Console/Commands/TermsAgreementAudit.php`;
  - migration `…_add_terms_customer_signed_at_to_orders_table.php` (nullable timestamp).
- Changed:
  - `routes/api/admin/v1/orders/routes.php`;
  - `app/Enums/Api/ApiErrorCode.php` + translations;
  - `app/Models/Mobile/MobileSyncIssue.php`;
  - `app/Models/Orders/Order.php` (fillable, cast, immutability guard);
  - `Front/TermsAndConditions/IndexController.php`, `PostController.php`, `PostRequest.php`, `resources/views/front/terms_and_conditions/index.blade.php`;
  - `app/Services/Dispatch/Offline/DispatchOfflineMissionPackageBuilder.php`, `DispatchOfflineOrderSections.php`, `DispatchOfflineMissionRevision.php`.
- Contract:
  - `docs/mobile-integration/MOBILE_API_CONTRACT.md`;
  - `tests/Fixtures/mobile-contract/dispatch_offline_packages.json`;
  - new `terms_agreement_identity.json`.
- Tests:
  - new `tests/Feature/Terms/TermsAgreementTest.php`, `TermsSigningPageFrozenAgreementTest.php`, `tests/Feature/Api/Mobile/Terms/TermsAcceptContractTest.php`, `tests/Feature/Dispatch/Mobile/DispatchOfflineTermsSectionTest.php`;
  - updated `DispatchOfflinePackagesTest`, `DispatchOfflineRevisionCompletenessTest`, `DispatchContractFixturesTest`, `MobileSyncIssueTest` (j), `TermsRequestEmailTest` (the signing test sends the identity).

**Mobile:**
- Core new: `TermsAgreement.swift` (model + canonicalization + renderer), `TermsAgreementStore.swift`, `TermsSignOperations.swift`.
- Core changed: `DispatchOfflineContract.swift`, `DispatchOfflineFieldBridge.swift`, `DispatchOfflineMissionStore.swift`, `EffectiveFieldState.swift`, `LegCompletionRequirements.swift`.
- App new: `Sync/App/TermsSigningShell.swift`, `Sync/App/TermsAgreementClient.swift`, resources `RentnKing/Resources/TermsSigning/*`.
- App changed:
  - `TermsSyncHandler.swift`, `KabbaSync.swift`, `DispatchOfflineSync.swift`, `DispatchOfflineOrderBridge.swift` (the `.terms` cache case);
  - `TermsAndConditionViewController.swift`, `OrderDetailsViewController.swift`, `OrderListButtonAction.swift`, `EmptyDataView.swift`;
  - `project.pbxproj`.
- Tests:
  - Core new `TermsAgreementTests` (incl. the shared vector), `TermsAgreementStoreTests`, `TermsSignOperationsTests`;
  - updated `EffectiveFieldStateTests`, `LegCompletionEvaluatorTests`, `DispatchOfflineFieldBridgeTests`, `DispatchOfflineContractTests`;
  - hosted new `DispatchOfflineTermsHostedTests.swift`.

---

## 7. Tasks (TDD; each ends with a local commit)
**Backend**

0. **Baseline.** Record `tests/Feature/Terms` and `tests/Feature/CustomerPortal` results at `2f859c0a8`.
1. **`TermsAgreement` + canonicalization + the shared vector + the immutability guard + the audit command.** Red tests:
   - the identity is computed from the stored copy only (a template edit, a product-terms edit and a product removal all leave it unchanged);
   - order binding (the same text on two orders gives different identities);
   - every legacy reason;
   - the guard refuses a change and allows the first freeze;
   - the vector bytes and hash;
   - the audit counts.
2. **Web path.**
   - The page renders the frozen copy (not current templates) plus the identity field.
   - Unavailable shows no form.
   - A post with a matching identity records the frozen copy; a mismatched or missing identity gives 409; already accepted doesn't overwrite.
   - Approvals come from the frozen copy.
   - The existing Terms, portal and `MobileSyncIssueTest` (j) stay green.
3. **Package `terms` + `sections.terms` + revision seed.** Red tests:
   - Delivery/Pending ships the agreement;
   - Return, Accepted and Exempt give `not_applicable`;
   - legacy gives `unavailable`;
   - a failing section is isolated and repaired at the same revision;
   - the revision doesn't churn on template edits;
   - manifest ≤ 450 statements and package ≤ 130 per order.
4. **Live GET**, with parity to the package.
5. **Accept endpoint + service + error codes + sync-issue type + `terms_customer_signed_at`.** Red tests for every row of §3.3 and §3.5.
6. **Contract docs and fixtures**, then the full backend regression (§9).

**Mobile**

7. **Core `TermsAgreement`:** decode, canonical bytes and identity against the shared vector, verification, renderer markers and escaping.
8. **Core `TermsAgreementStore`:** tenancy, verified-only writes, retention, freshness.
9. **Core bridge `terms` section + ledger + readiness + same-revision repair**, and the pre-Phase-5 package (`notProvided`).
10. **Core `terms.sign` + satisfaction rule:**
    - healthy only;
    - identity-bound and order-bound;
    - Needs Attention never satisfies;
    - legacy `terms.accept` unchanged.
11. **App shell + inert rendering + screen resolver + message handling + live fetch + Order Details inputs,** with the hosted tests (§8.3).
12. **Full verification** (§9), break-a-rule probes, then a fresh independent review. Critical/Important findings are fixed and re-reviewed.

---

## 8. Tests

### 8.1 Backend
- **Identity:**
  - the shared vector;
  - determinism;
  - order binding;
  - CRLF/CR normalization;
  - null equals `""`;
  - non-ASCII text;
  - excluded fields (title, id, unique_id) don't matter;
  - the stored contents are never modified.
- **Frozen:** after creation, editing the global terms, a product's terms, attachments, product data or pricing, and removing a product (soft delete) all leave `forOrder()->identity()` and `contentHtml()` byte-identical.
- **Separate agreements:**
  - a reorder has its own identity;
  - an Enhancement is `no_stored_agreement`;
  - neither affects the parent.
- **Legacy:**
  - a valid copy is used verbatim;
  - null, malformed and empty copies give their reasons;
  - current templates are never read (a query-log assertion: no `terms_and_conditions` or `product_terms_children` query).
- **Web:**
  - the page body equals `contentHtml()` even when current templates differ;
  - the identity field is present;
  - matching, mismatched, missing, unavailable and already-accepted posts;
  - approvals come from the frozen copy.
- **Package and live:**
  - parity between them;
  - the section statuses;
  - isolation and repair;
  - no revision churn;
  - statement budgets.
- **Accept:**
  - every row of §3.3;
  - replay (ledger, same original body);
  - a second op id gives `already_accepted`;
  - another order's identity gives a mismatch with no write;
  - an unknown order stores nothing;
  - the device time goes to `terms_customer_signed_at` and the server time to `terms_accepted_at`;
  - the line's `tnc_status` is recorded;
  - exactly one history row;
  - one sync issue on a terminal rejection.

### 8.2 Mobile core (`swift test`)
- Decode and validation.
- The shared-vector identity.
- Verification, including the wrong order.
- The renderer.
- The store.
- Bridge states and readiness.
- The `terms.sign` builder and request.
- The satisfaction rules, and the screen-state resolver (every row of §4.3).

### 8.3 Hosted (Simulator, signed `RentnKingHostedTests`)
1. **Never opened online.**
   1. Reconcile a stubbed Delivery/Pending package with the agreement.
   2. Never open the mission.
   3. Go offline.
   4. Open T&C through the real screen: it resolves the stored, verified agreement.
   5. The page renders offline: every clause, both approval checkboxes and the sign button are present.
   6. Sign through the page.
   7. The op is durable before `termsSucess`.
   8. Leave and reopen: "Signed on this phone".
   9. Recreate the engine from the same folder: the op is still pending and T&C is still satisfied.
   10. Delivery completion lists no T&C override.
   11. Reconnect, using a stub that answers 200: exactly one POST with one `signature_media` part, the identity and the operation id.
2. **Inertness.** Content containing `<script>`, `onclick`, `<a href="javascript:…">`, `<iframe>`, `<object>` and a remote `<img>`:
   - no script runs, and no message is posted by content;
   - no navigation happens;
   - no network request is made;
   - signing still works.
3. **Verification failure:** a tampered agreement (the identity doesn't recompute) shows "Unable to Verify Order Terms"; nothing renders and no signing is possible.
4. **Missing agreement:** `sections.terms: failed` → offline "aren't downloaded yet" (no web load, no leftover spinner); the mission is not Delivery-ready.
5. **Replay:** the first send commits server-side but the response is lost; the retry gets a 200 replay; the op is synced once, with the same operation id both times.
6. **Binding:** an O1 op never satisfies O2; a 409 mismatch leaves the op in Needs Attention with its PNG kept, and T&C unsigned.
7. **Tenant:** a Company A agreement is invisible under B offline, and usable again under A.

---

## 9. Closing gate
- All §8 tests, red first then green.
- The complete mobile core suite and the signed hosted suite.
- The simulator build.
- The no-polling/timer/GPS/socket gate. The live GET fires only when the screen opens.
- Break-a-rule probes, one per rule in §2–§4.4, each caught.
- The backend regression **from the final HEAD**:
  - `tests/Feature/Dispatch`, `Api`, `Mobile`, `tests/Unit/Push`, `QueueLine`;
  - `tests/Feature/Terms`, `tests/Feature/CustomerPortal`, compared to the Task 0 baseline;
  - `tests/Feature/Orders` and `CustomerChecklists`, whose baseline failures must match **by test name**.
- The manifest at 50 missions ≤ **450** statements, with the verified count reported.
- Both worktrees clean with no upstream.
- A **fresh independent reviewer** reporting no Critical or Important issues.

Then stop and report.

---

## 10. Recorded risks, boundaries and deferred items

### 10.1 Accepted deferred risk — cross-customer Sync Engine queue ownership
- **The risk:** ops carry no company, so work queued under one Kabba customer instance could be sent with another's session after an unsynced company switch on the same phone.
- **It is accepted as a low-probability deferred risk:** three customers, devices geographically and operationally separate, and such a switch with unsynced work is considered exceptionally unlikely. It is out of scope for Phase 5.
- **T&C-specific check, not materially worse:**
  - A `terms.sign` op sent to the wrong company names an order that company doesn't have. It is refused (404) **before any write**, and it could never match an identity, which is bound to the order uid.
  - The signature image would reach that server in the refused request, the same exposure class as today's checklist signature and license photo ops.
  - The agreement store is tenant-scoped.

### 10.2 Watch items
- **Signature files outlive their records.** A synced signature file stays on disk after `pruneSynced` deletes its record (7 days). This is pre-existing for every non-media handler.
- **Reminders can overlap an unsynced signature.** The existing automatic Terms reminders can text a customer whose phone signature is still unsynced.
- **A rejected signature exists only on the phone** until a person discards it.
- **Legacy orders.** Pending orders without a trustworthy stored copy can no longer be signed on the web, where they showed today's templates before. `terms:agreement-audit` measures how many; production can't be checked from here.
- **Pre-existing, out of scope:**
  - the new-order success screen's T&C button never opens (`strOrderUniqueId` unset);
  - Order Details' T&C button checks `status == "Exempt"` instead of `terms_status`.

### 10.3 Scope boundaries
Phase 5 does not:
- redesign Dispatch or Order Details;
- revisit Phase 3/4 deferred items;
- build generic document signing, document storage, amendments or addenda;
- add freezing to the Order Enhancement flow;
- change the Warning override or its permissions;
- solve the cross-customer queue;
- begin Phase 6.
