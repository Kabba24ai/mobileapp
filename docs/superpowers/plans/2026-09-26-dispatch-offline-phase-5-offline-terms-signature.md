# Dispatch Offline Phase 5 — Offline Terms & Conditions + Signature — Implementation Plan

> **Status: PLAN ONLY — awaiting Gary's review (2026-09-26).** No product code has been written. Decisions P5-D1–P5-D12 (§5) need approval before implementation starts.
> Rules for execution after approval: TDD task by task (failing test → prove the failure → minimum code → focused and regression tests → review the diff → local commit). Local only: no push, merge, deploy, SSH, production data, feature flag, version/build bump, archive or App Store upload. Do not begin Phase 6.
> **Phase 5 closes only after all of these pass (§9):**
> - the backend parity, revision, idempotency and freshness tests (§8.1);
> - every mobile scenario in §8.2–§8.3, including the automated never-opened acceptance scenario;
> - the complete affected backend regression and the complete mobile core and signed hosted suites;
> - the simulator build and the no-polling gate;
> - a fresh independent reviewer reporting no Critical or Important issues.

**Goal:** a Dispatch mission that was **never opened while online** supports, with the iPhone **completely offline**:

`cached Dispatch → Driver Checklist → Order Details → Terms & Conditions → customer acceptance/signature → continue completion`

The signature is durable on the phone the moment it is captured, the workflow advances on that local evidence, and it later syncs to Laravel idempotently. The signature is always tied to the exact Terms revision the customer viewed.

**Spec:** `docs/superpowers/specs/2026-09-22-dispatch-offline-mission-cache-design.md`: §8 "Terms & Conditions", §9 (T&C accepted/exempt state and content/version change are revision triggers), §17 ("T&C content renders offline", "offline terms signature is durable and later syncs"), §18 step 5, §20 ("Unsigned T&C must be truly usable offline, not merely represented by a cached URL").

**Builds on (local branches, no upstream; `main` untouched in both repos):**
- Backend `feature/dispatch-offline-phase-5`, cut from Phase 4 HEAD `2f859c0a8`, in worktree `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline`. No commits yet.
- Mobile `feature/dispatch-offline-phase-5`, cut from Phase 4 HEAD `92daa7f`, in worktree `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p5`. This plan is its first commit.

**Baseline (Phase 4 final):**
- Mobile core `swift test`: 499/499.
- Signed hosted: 72/72.
- Simulator build: OK.
- Backend Dispatch 591, Api 200, Mobile 15, Unit/Push 6, QueueLine 293, all passing.
- Backend Orders fails 23 and CustomerChecklists fails 11: the same tests by name as the Phase 2 baseline copy.

---

## 0. What the inspection found

### 0.1 How Terms & Conditions are signed today
- **The phone never signs anything itself.** `TermsAndConditionViewController` is a `WKWebView` that loads the hosted page `GET terms-and-conditions/{order}/mobile` (`TermsService::signingUrl($order, 'mobile')`, exposed as `terms_page` in the orders resources and as `terms.page_url` in the Phase 1 package).
- **The page** (`resources/views/front/terms_and_conditions/index.blade.php`):
  - extends the full public site layout (Vite `app.css`/`app.js`, which provides `window.SignaturePad` from `signature_pad` ^5.0.9, plus `notyf`, `apiFetch` and the CSRF meta), and hides the navbar and footer with JS when `device=mobile`;
  - prints the three "Rental Agreement Header" lines (`Website Management Branding` settings `terms_condition_text_1..3`), the order number and an instruction;
  - renders the body inside `#terms-dynamic-content` from `TermsContentHelper::generateTermsContent($order)`;
  - opens a signature modal (signature_pad canvas → `toDataURL('image/png')`), then POSTs the form with `apiFetch`.
- **The body markup is part of the canonical content.** `generateTermsContentFromArray` injects a required `customer_approval[]` checkbox at every `[customer_approval][/customer_approval]` placeholder in product terms, and a "CLICK HERE TO SIGN" button (inline `onclick="openModal()"`) at `[customer_signature][/customer_signature]` in the global signature block. `[customer_name][/customer_name]` becomes the order's `customer_name`.
- **The write** (`Front/TermsAndConditions/PostController`, `POST terms-and-conditions/{order}/sign`):
  - The route is on the **front domain with `web` middleware**, so it has CSRF and no API authentication.
  - It sets exactly four order columns: `terms_status=Accepted`, `signature_image` (the data URL string, with no format or size check), `accepted_terms_content` and `terms_accepted_at=now()`.
  - It fires `OrderTermsSignedEvent`, which writes one "Terms accepted by customer." history row.
  - It is already wrapped in `MobileOperationService` (ledger type `terms.accept`) when an `operation_id` is sent; `MobileSyncIssueTest` (j) proves the replay. No phone code calls it that way today.
- **After the page shows its thank-you URL,** the app enqueues the Sync Engine op `terms.accept`. That op only posts `update-delivery-pickup-inputs` with `tnc_status="accepted"`, `complete_leg=false`, which records `order_products.{delivery|pickup}_tnc_status`. That column is written but read nowhere on the server. The op carries no signature and no Terms identity.
- **Entry points** to the screen:
  - Order Details (the Dispatch → Driver Checklist → Order Details path).
  - The Order List row button.
  - The new-order success screen. It never opens: `strOrderUniqueId` is never set (pre-existing; out of scope).

### 0.2 What the Terms content is — determined, not assumed

| Question | Answer (evidence) |
|---|---|
| Generated dynamically? | **Yes.** While Pending, the page renders `generateTermsContent($order)` from **live** rows on every view. |
| Stored HTML/text? | Admin-authored rich **HTML** in `terms_and_conditions.content` / `.signature_block`, with the placeholder shortcodes above. |
| A PDF/document? | **No.** There is no PDF anywhere in the terms path. |
| Company-configurable? | **Yes.** It is per Kabba customer instance (its own database): Configurations → Terms & Conditions, plus the header lines in Branding settings. |
| Versioned today? | **No.** Terms rows are edited in place (`UpdateController` → `fill()->save()`) and hard-deleted (`DeleteController`). There is no version, revision or hash for rental terms anywhere in `app/`, migrations or tests. (`LoyaltyTermsVersion` is a separate, immutable, published-version model for loyalty terms only; nothing references it here.) |
| Different by order? | **Yes, by product mix.** The global terms (the first `is_global='Yes'` row) are included only if some product on the order `is_general_term_type`. Each product's attached terms (`product_terms_children`) are then merged, deduplicated by id. |
| Different by customer? | **Yes, in rendering only.** The signature block prints the order's `customer_name`. |
| Different by location/store? | **No.** Terms have no store scoping. |
| Different by company? | **Yes.** Each company has its own rows and settings. |

### 0.3 The live page and the stored acceptance already disagree (online)
- The page shows the **live** terms. A Blade comment says so on purpose: `{{-- {!! $order->pending_terms_content !!} commented because before sign user may check latest update terms and then he can sign --}}`.
- `PostController` records `accepted_terms_content` from **`$order->terms_collection`**, the checkout-time snapshot (`Front/Checkout/PostController.php:616`).
- **So today, if the office edits the terms after checkout, the customer views B and the order records acceptance of A.** That is the core rule's failure in reverse, already live online. Phase 4 §10 flagged it.
- `PostRequest` also decides whether approvals are required from `pending_terms_content`, the checkout snapshot, not from what was shown.

### 0.4 Completion rules today (mobile)
- **T&C is a Delivery-only requirement** (`LegCompletionRequirements` matrix). Return ignores it as historical.
- **It is an order-level fact.** It is satisfied by the server's `terms_status` Accepted/Exempt, or by **any** durable `terms.accept` op for the order, in any retained state (`EffectiveFieldState.termsSatisfied`, `LegCompletionEvaluator.orderScoped`). A needs-attention op gives `satisfiedNeedsAttention`, which lets the driver proceed with the sync-attention treatment.
- **The evidence is revision-less today.** Once the office changes the terms, a signature of A cannot be told apart from one of B on the phone.
- **The Warning override** (`WarningViewController` → `fulfillment_inputs.update`, `complete_leg=false`) records a reason in `delivery_tnc_status` when T&C is missing. Phase 5 leaves it unchanged. Its reasons already include "No Internet / Cellular Service", which Phase 5 is meant to make unnecessary.
- **Order Details' in-memory "Accepted" flip (`termsSucess`) is overwritten** when the screen reappears and reloads its cached order. Only the durable op keeps T&C lit offline.

### 0.5 Sync Engine facts that shape the design
- **Durable enqueue.** `enqueue` persists before it returns (atomic write, `completeUntilFirstUserAuthentication`), and operations survive force-quit and restart (`syncing` is reset to `pending`).
- **Assets.** They are stored under `assets/<scope>/`, sent as multipart parts named by `fieldName`, and kept after acknowledgment unless the handler opts in to deletion. Needs-attention assets are deleted only by a person's **Discard**.
- **Responses.**
  - `error.retryable=false` → Needs Attention.
  - 409 without `retryable` → Needs Attention.
  - 5xx/429/transport → retry with backoff, never exhausted.
- **Idempotency and ordering.**
  - Idempotency is the server's job (`X-Operation-Id` + `operation_id`). The engine **never deduplicates**, so the screen must never enqueue twice for one signing.
  - Operations send FIFO per `orderingKey` = order product, else order.
- **No tenant field on operations** (accepted deferred risk, §10.1).

### 0.6 The package today
- **`terms` = `{status, page_url, offline_content_available: false}`**, with the comment "Phase 5 adds the versioned offline Terms snapshot". `DispatchOfflinePackagesTest` pins `offline_content_available === false`.
- **The mission revision** covers `terms_status` only (through `dispatch.order.terms_status`). A Terms content edit changes no revision.
- **The manifest** runs 438 of its 450-statement cap at 50 missions.

### 0.7 Mobile rendering dependencies
- The app bundles **no** HTML/CSS/JS resources.
- It uses no `loadHTMLString`, `WKUserContentController`, `WKScriptMessageHandler` or `evaluateJavaScript`.
- The storyboard web view has default configuration, and its only outlet is `objWebKit`.
- The only native signature pad is the checklist's `EPSignatureView`: landscape, JPEG, one image per screen.

---

## 1. Approach — the existing T&C screen, made local-first

1. **One canonical Terms document per order**, built by one server builder from the **same** source the signing page renders. It has an immutable, content-addressed **revision**. The mission package (Delivery missions whose terms are Pending) and a small live endpoint both carry it.
2. **The same screen** (`TermsAndConditionViewController` and its `WKWebView`) renders that document **locally**: the same `#terms-dynamic-content` markup, the same inline approval checkboxes, the same signature_pad library. This happens offline from the cached document, and online from a freshly fetched one (P5-D3).
3. **Signing is local-first:** signature → a durable Sync Engine op `terms.sign` (the signature file plus the revision) → T&C is treated as satisfied locally → the op syncs.
4. **Laravel decides per revision.** It records acceptance **only** of the revision that is current when the signature arrives. Anything else is kept (on the phone) and surfaced as Needs Attention, never relabelled (P5-D4/D5).

There is no second signing workflow, no second checklist cache and no generic document storage.

---

## 2. The canonical Terms identity (P5-D1)

### 2.1 The revision
`revision` = SHA-256 (64 lowercase hex, the mission-revision format) of this canonical JSON, encoded with the mission revision's `json_encode` flags:

```
{
  "schema": 1,
  "header": [text_1|null, text_2|null, text_3|null],          // Branding settings; "" → null
  "terms":  [ { "unique_id", "is_global", "content", "signature_block" }, … ]
                                                               // exactly generateTermsArrayFromOrder(), in its order
}
```

- **Content-addressed:** identical inputs give the identical revision, so **A → B → A returns revision A** (required case 5).
- **Server-issued:** only the server computes it, in the manifest, the package and the live endpoint, and it compares it by recomputation when a signature arrives.
- **Immutable:** a revision string can only ever mean one content.
- **In:** everything that changes what the customer reads or signs:
  - a Terms row's content or signature block;
  - attaching or detaching a product's terms;
  - global inclusion flipping (the product mix);
  - a header line.
- **Out:** fields that are not rendered (title, SEO fields, row ids other than `unique_id`), and the **customer name**, which is order data and not the terms. A name correction therefore does not make a signature stale.

### 2.2 The content hash
- **`content_sha256`** = SHA-256 of the exact rendered `content_html` (this includes the customer name).
- The phone (App layer, CryptoKit) **verifies it before displaying** a document. It never shows bytes other than the ones the server issued.
- The phone keeps each signed revision's document, with its content hash, as local evidence (§4.2).

### 2.3 Why no revision table
- Recording acceptance only when the presented revision **equals** the current one means the server never needs to recall an old revision's text. Equal hash means equal rendering inputs, so the server renders the accepted content from the current rows, exactly as the page did.
- Any other revision is refused and kept on the phone (P5-D5), so nothing server-side needs an old version.
- This keeps `TermsService`'s documented rule ("no terms agreement record … no signature record … the whole lifecycle is four columns on the order", pinned by `TermsRequestEmailTest::test_neither_transport_creates_a_terms_or_signature_record_of_its_own`).
- **One additive column** makes the order's acceptance self-describing: `orders.accepted_terms_revision` (nullable `string(64)`, no timestamp), written on every acceptance recorded after Phase 5.

---

## 3. Backend design

### 3.1 `App\Services\Terms\TermsDocument` (the one builder)
- **`forOrder(Order): TermsDocument`** is built **only** from `TermsContentHelper::generateTermsArrayFromOrder()` plus the Branding header lines. The global-terms row and the header settings are memoized per builder instance, so the manifest reads them once.
- **What it returns:**
  - `revision()`;
  - `contentHtml(customerName)`, which is `generateTermsContentFromArray(...)['terms_content']`;
  - `contentSha256()`;
  - `approvalsRequired()`, the number of approval placeholders in product terms;
  - `toArray()`, the wire shape in §3.2.
- **Used by:**
  - the package section;
  - the live endpoint;
  - the mission revision (Pending orders only);
  - the acceptance service;
  - the signing page itself if P5-D2 is approved.
- **Parity test:** `contentHtml` is **byte-identical** to `generateTermsContent($order)['terms_content']`, which is exactly what the signing page prints inside `#terms-dynamic-content`, ahead of its SUBMIT button. The test reads it from the served page.

### 3.2 Package and live contract
**`terms` on a Delivery package whose order's terms are Pending.** The `status`/`page_url` keys stay as they are:

```json
"terms": {
  "status": "Pending",
  "page_url": "https://…/terms-and-conditions/ORD…/mobile",
  "offline_content_available": true,
  "document": {
    "order_unique_id": "ORD-…",
    "revision": "<64 hex>",
    "content_sha256": "<64 hex>",
    "header": ["Rental Agreement", null, null],
    "order_number": "#1234",
    "customer_name": "Jane Doe",
    "content_html": "<div>…</div>",
    "approvals_required": 2
  }
},
"sections": { "order_details": "ok", "assembly": "ok", "terms": "ok" }
```

- **Terms Accepted / Exempt / Declined, or a Return package:** `document: null`, `offline_content_available: false`, `sections.terms: "not_applicable"` (P5-D7).
- **Build failure:** the section is isolated exactly like Phase 4's sections. It gives `document: null`, `sections.terms: "failed"`, and the rest of the package is unaffected. It is reported server-side with no exception detail.
- **Built once per order** in `withOrderSections`, after every requested mission's `buildContext()`.
- **Mission revision:** the seed gains `terms` = `TermsDocument::revision()` when the order's terms are Pending, otherwise `null`. A Terms edit therefore reaches offline phones through the normal manifest → wake → package path, while Accepted/Exempt orders never churn.
  - The selector adds `order.products.product.terms` to its eager loads.
  - Expected manifest cost: +4 statements (438 → about 442; the cap of 450 is unchanged, P5-D11).
- **Live endpoint `GET api/admin/v1/orders/terms/{orderUniqueId}`** (`auth:api_user`) returns `{success, data: <the same terms object>}` for any order. It is read-only and uses the same builder. A parity test proves it equals the package's `terms` exactly.

### 3.3 Acceptance endpoint `POST api/admin/v1/orders/terms/{orderUniqueId}/accept`
The Sync Engine op `terms.sign` posts here. It is multipart and wrapped in `MobileOperationService` with ledger type `terms.sign`.

| Field | Rule |
|---|---|
| `order_product_unique_id` | required; must belong to the order |
| `leg` | `delivery` \| `return` |
| `terms_revision` | required, 64 hex |
| `approvals_confirmed` | required integer ≥ 0 |
| `signature_media` | required image (png/jpeg), max 2 048 KB (the checklist signature rule) |
| `signature_client_media_id` | nullable, the media id format |
| `captured_at`, `operation_id` | the existing mobile contract |

- **The request is validated before anything is written.** An unknown order (for example another company's uid, §10.1) or a product from another order is rejected as a terminal 422/404, and **nothing is stored**: no ledger row, no sync issue, no file.

`TermsAcceptanceService::accept()` runs in one transaction with the order row locked (`lockForUpdate`, which serializes a web signing and a phone signing). The rows are checked in this order:

| Order state when the op arrives | Outcome | Writes |
|---|---|---|
| Already Accepted (web, or another phone) | **200 `already_accepted`** | none, and no second history row |
| Exempt | **200 `not_required`** | none |
| Pending, and `terms_revision` ≠ current. The same answer covers Declined, which no code writes today and which has no signable document. | **409 `TERMS_REVISION_STALE`, `retryable:false`**, `data.current_revision` | **None to the order.** The existing ledger path raises an order-scoped Mobile Sync Issue ("Customer Signature / Terms"). |
| Pending, revision current, `approvals_confirmed` < `approvals_required` | 422 terminal | none |
| Pending, revision current, approvals complete | **200 `accepted`** | See the list below. |

On `accepted`, the service writes:
- the same four columns the web path writes:
  - `terms_status=Accepted`;
  - `signature_image` = `data:image/png;base64,…` (the web format);
  - `accepted_terms_content` = `generateAcceptedTermsContentFromArray(current terms, customer_name, signature)`;
  - `terms_accepted_at` = the resolved `captured_at` (P5-D8);
- plus `accepted_terms_revision`;
- the line's `{delivery|pickup}_tnc_status='accepted'` (what the thank-you `terms.accept` op records today);
- `OrderTermsSignedEvent` once, whose history row gets source Api.

**Idempotency comes in two layers:**
1. The ledger replays the stored acknowledgment for the same `operation_id`. A lost response converges.
2. The business rule: an already-accepted order answers `already_accepted`.

A retry of a stale op after the office has resolved things re-executes (rejected ledger rows are re-claimable). It then converges to `accepted` (terms back at A) or `already_accepted` (B was signed).

**New codes and registry entries:**
- `ApiErrorCode::TermsRevisionStale` (409, not retryable), with a translation next to `checklist_execution_superseded`.
- `MobileSyncIssue::ACTIONABLE_OPERATION_TYPES` gains `terms.sign`, labelled "Customer Signature / Terms".

### 3.4 The web signing path (P5-D2, recommended)
- **`IndexController`/view** render the body from `TermsDocument` (byte-identical by the parity test) and add `<input type="hidden" name="terms_revision">`.
- **`PostController`** calls the same service on its web channel:
  - revision equal to current → record as today, but `accepted_terms_content` from the **displayed** (current) document instead of `terms_collection`, plus `accepted_terms_revision`;
  - revision different → 409 `{success:false, message:"These terms were updated while this page was open. Please review the updated terms and sign again."}` (`apiFetch` shows the message);
  - revision missing (a page loaded before the deploy) → treated as current.
- **`PostRequest`'s approval rule** reads the current document's `approvals_required` instead of `pending_terms_content`.
- **Unchanged:** the ledger type `terms.accept`, `terms_accepted_at=now()`, the event and the response. `terms_collection` and `pending_terms_content` are not touched: checkout still writes them, and the admin view and reports still read them.

### 3.5 Required freshness cases — server behavior

| # | Case | Outcome |
|---|---|---|
| 1 | Phone downloads A; customer signs A offline; server still A at sync | **Accepted** (A recorded; `accepted_terms_revision`=A). |
| 2 | Phone downloads A; server changes to B **before** the customer signs A offline | **Preserved + Needs Attention; re-signing B required.** 409 stale; the order stays Pending; the Mobile Sync Issue is raised; the phone keeps the A signature (P5-D5). |
| 3 | Customer signs A offline; server changes to B **before** the sync arrives | **Same as case 2** (P5-D4: the server cannot order the events with a trustworthy clock). |
| 4 | A's acceptance reached the server; the acknowledgment was lost; the phone retries | **Idempotent replay** (the ledger's stored 200, `X-Idempotent-Replay`); nothing re-executes. |
| 5 | Content returns to an earlier identical revision (A → B → A) | **Accepted**: the revision is content-addressed, so the current revision is A again. |
| — | Already accepted by another channel | `already_accepted`; the phone is satisfied by server truth. |
| — | A later retry of a case 2/3 op | Converges as §3.3 says. The original signature is never deleted by the server's answer. |

**Re-sign flow for cases 2 and 3.**
- The order stays Pending, so the existing automatic Terms SMS/email reminders keep asking the customer to sign the **current** terms on their own device.
- The office sees the Mobile Sync Issue.
- If the delivery is still in the phone's working set, the next package brings B, and the T&C tile shows unsigned again so the customer can sign B on the phone. A itself never satisfies B (§4.4).

---

## 4. Mobile design

### 4.1 Components
**Core (Foundation only, `swift test`):**
- **`TermsDocument`:** the model and decoder for `terms.document`, used by both the package and the live endpoint. It validates the revision and hash format, requires a non-empty body, and matches `order_unique_id` against the package's order.
- **`TermsDocumentStore`:**
  - Tenant-scoped and protected, following the Amendment B pattern: `<KabbaSync>/terms-documents/<tenantKey>/<orderUid>/<revision>.json` plus a newest-copy pointer.
  - It keeps every revision it received. Nothing is pruned in Phase 5, so a signed revision's document stays on the phone as evidence.
  - Freshness is a new per-cache stamp `terms` in the Phase 4 field ledger: the newest request time wins, whether a package or a live fetch wrote it.
- **`DispatchOfflinePackageSections.terms`** and **`DispatchOfflinePackageContent.termsDocument`.**
- **`DispatchOfflineFieldBridge`:**
  - A `terms` section state is added to the ledger's `Mission` (`decodeIfPresent`; an absent state is re-bridged idempotently).
  - It writes the store under the ledger lock when `sections.terms == ok`.
- **Readiness (Amendment A):**
  - A **Delivery** mission is field-ready only when context + order_details + assembly + **terms** are satisfied or not applicable.
  - A `failed`/`invalid` terms section is retried at the same revision.
  - **Return readiness is unchanged.** A pre-Phase-5 server (no `sections.terms`) gives `notProvided`: settled, never retried, and T&C stays "needs a connection" as in Phase 4.
- **`TermsSignOperations`:**
  - `TermsSignCapture` holds the order, order product, leg, revision, `approvals_confirmed`, employee, order number and `capturedAt`.
  - `TermsSignOperationBuilder.enqueue(_:signaturePNG:into:)` stores the signature as an asset: scope `terms-<order>`, `signature_media`, `image/png`.
  - `TermsSignRequestFactory` builds the POST, adding the `X-Operation-Id` header plus `operation_id` and `captured_at` in the body.
- **`EffectiveFieldState` / `LegCompletionEvaluator`** apply the revision-aware rule in §4.4. `LegCompletionInputs` gains `termsRevision` (the store's newest revision for the order).

**App:**
- **`TermsSigningShell`:**
  - A bundled local page composed at runtime from resource files: HTML skeleton, CSS subset, shell JS, and vendored `signature_pad` 5.x UMD with its MIT license (P5-D6). It reproduces the hosted page's header, order line, instruction, `#terms-dynamic-content` body, SUBMIT and signature modal.
  - **The page can only talk to native.** A CSP meta allows only the shell's nonce-tagged scripts (`default-src 'none'; script-src 'nonce-…'; style-src 'unsafe-inline'; img-src data: https:; connect-src 'none'`), so a script inside admin-authored content cannot run or post a fake signing.
  - Buttons are bound by id; the content's inline `onclick` attributes are inert.
  - **Submit** requires `form.reportValidity()` (every approval checkbox) and a signature, disables itself, and posts `{signature: <PNG data URL>, approvals_confirmed, revision}` to the `kabbaTermsSigned` message handler.
- **`TermsAndConditionViewController` (the same screen):**
  - The presentation states (§4.3) come from a pure resolver.
  - Local documents load with `loadHTMLString` (base URL nil).
  - The screen adds the message handler through a weak proxy.
  - It allows only the initial local load and cancels any other navigation. It no longer force-unwraps `navigationAction.request.url`.
  - **On a signing message**, it validates that the revision equals the rendered document's and that the data is a PNG under 2 MB, then enqueues `terms.sign`. Once that returns (durable), it shows the existing status toast, calls the existing `termsSucess`, and pops, exactly like the thank-you path.
  - **If the enqueue fails**, it says the signature could not be saved on this phone and flips nothing.
- **`TermsDocumentClient`:** the live `GET orders/terms/{uid}` on screen open when reachable. That one request replaces today's hosted-page load; there is no polling. The company is captured when the request is sent (the Phase 4 live-save rule), and the result is saved through `saveLiveCopy(.terms, …)`.
- **`TermsSignSyncHandler`**, registered with `KabbaSync` next to `TermsAcceptSyncHandler`.
- **Order Details / Order List** pass the order's `terms_status` to the screen. Order Details feeds `termsRevision` into its leg-completion inputs. The existing leg/product rules for the screen's ids are unchanged.
- **`EmptyDataView`** gains copy for the new states.

### 4.2 Durable artifacts per signing
| Artifact | Where |
|---|---|
| Signature image (PNG, the same format as the web pad) | Sync Engine asset `assets/terms-<order>/<clientMediaId>.png`, protected; kept until acknowledgment, and while Needs Attention until a person discards the op |
| Acceptance time | `capturedAt` on the op |
| Signer | the existing flow has no signer field; the signature block prints the order's customer name, which is in the document |
| Order / order product / leg | op identity (`orderUniqueId`, `orderProductUniqueId`) + payload `leg` |
| Exact terms identity | payload `terms_revision`; the document itself (with `content_sha256`) is kept in `TermsDocumentStore` under that revision |
| Approvals | payload `approvals_confirmed` |
| Idempotency key | the operation id (`X-Operation-Id` + `operation_id`) |
| Employee | payload `user_id` / identity `employeeId` (the signed-in user) |

### 4.3 Screen states (one pure resolver, unit-tested)
| Condition | Shows |
|---|---|
| Server truth Exempt | "Terms & Conditions aren't required for this order." |
| Server truth Accepted | "Terms & Conditions are already accepted for this order." |
| A durable `terms.sign` op for this order **at the newest known revision** | "Signed on this phone" with its sync state (Pending Sync / Synced / Needs Attention). No second signature can be captured at that revision (the engine does not deduplicate). |
| A verified document (live when reachable, else cached) | The local signing page |
| Online, no document, and a valid `page_url` (an older server, or an order this phone never received) | The existing hosted page, unchanged, with its thank-you → `terms.accept` path |
| Offline, no document (never downloaded, or the section failed) | "Terms & Conditions for this order aren't downloaded to this phone yet. Connect to the internet to load them." — never a blank web view |
| Online, no document, invalid link | The Phase 4 "aren't available for this order" state |

### 4.4 Local satisfaction — revision-aware
T&C (Delivery) is satisfied when any one of these holds:
- **server truth** is `terms_status` Accepted or Exempt (unchanged);
- **a legacy `terms.accept` op exists for the order** (unchanged: it is written only after the hosted page recorded acceptance on the server);
- **a durable `terms.sign` op exists for the order whose `terms_revision` equals `termsRevision`**, the newest revision this phone holds for the order. If the phone holds no document it cannot contradict the op, and the op counts.

As before, a needs-attention op gives `satisfiedNeedsAttention`. Consequences:
- **A signature of A never satisfies B** once the phone knows B (from a package or a live fetch).
- **A signature for order O never satisfies another order.**
- **Terms stay order-level (existing, P5-D12).** A signature captured on one Delivery line of an order covers that order's other Delivery lines, because the server records it once on the order.

### 4.5 Tenant safety
- **`TermsDocumentStore`** is tenant-scoped on read and write, and holds nothing without a tenant.
- **Live saves** are pinned to the company captured when the request was sent.
- The A → logout → B offline → back to A test (§8.3) covers the new store.
- `terms.sign` ops are not tenant-bound, like every other op (§10.1).

### 4.6 Scenario behavior
| Scenario | Behavior |
|---|---|
| Never opened, offline, terms Pending | The bridge already stored the document. Order Details → T&C renders it locally, the customer signs, the op is durable, T&C is satisfied, and Complete proceeds without the override. |
| Leave and reopen / force-quit / restart | The document, op and asset are durable. The screen shows "Signed on this phone", the Order Details tile stays satisfied, and completion is unchanged. |
| Prolonged offline, then reconnect | The op keeps retrying (never exhausted) and syncs once. The server answers accepted, or replays; the next orders/details and package show Accepted. |
| Terms changed after download (phone learns B) | The A op stops satisfying. The T&C tile is unsigned and the screen shows document B. The A op keeps syncing and becomes Needs Attention; it is never deleted. |
| Package has the mission but the terms section failed | The mission appears in Dispatch but is not field-ready for Delivery and is retried at the same revision. The T&C screen offline shows "aren't downloaded yet". |
| Order's terms accepted elsewhere | The new package or live answer brings Accepted, so T&C is satisfied by server truth. A queued phone op gets `already_accepted`. |
| Return mission | Unchanged: T&C is not required. A cached document from an earlier Delivery package can still be signed. |
| Online Dispatch T&C | The document is fetched fresh, then the same local signing runs. The op drains at once (P5-D3). |

---

## 5. Decisions requiring approval

| ID | Decision | Recommendation | Alternative(s) |
|---|---|---|---|
| **P5-D1** | Canonical identity | A content-addressed `revision` (§2.1) plus `content_sha256` of the rendered body (§2.2). No revision table. One nullable column: `orders.accepted_terms_revision`. | (a) An admin-published immutable version table like `LoyaltyTermsVersion`: changes the admin edit flow and still needs content hashing for product-mix documents. (b) Stateless HMAC-signed issue tokens with the phone echoing the document. (c) Include the customer name in the revision, so a name correction makes a signature stale. |
| **P5-D2** | Which revision is "currently applicable", and the web path | **The live terms the signing page shows** (the page's stated intent), not the checkout snapshot. **Fix the web path too** (§3.4), so web and phone both record what the customer viewed. | Leave the web path unchanged. The phone becomes exact, but a customer signing on their own device keeps the divergence in §0.3. |
| **P5-D3** | Online behavior of the Dispatch/Order T&C screen | **One local-first screen online and offline.** Online fetches the fresh document (one GET instead of the hosted-page load) and signs locally. The hosted page is only a fallback when no document is available. | Online keeps the hosted page and local signing is offline-only: two signing paths on the phone, and the online path keeps §0.3's divergence unless P5-D2 is approved. |
| **P5-D4** | Stale-revision policy | **The newer terms must be signed.** Any revision other than the current one is never recorded as acceptance: 409 terminal → Needs Attention on the phone, a Mobile Sync Issue for the office, and terms stay Pending (existing reminders plus on-phone re-signing). Cases 2 and 3 are treated the same. | Accept an older revision captured before the change. This needs Terms change history and trusts the device clock; not recommended. |
| **P5-D5** | Where a stale signature is kept | **On the phone:** the Needs Attention op and its PNG, kept until a person discards it through the existing sync-attention workflow (spec §5: field work stays "until … explicitly resolved through the existing sync-attention workflow"). Keeps `TermsService`'s documented "four columns on the order" rule. | An append-only `order_terms_acceptances` table (server-side preservation and audit of every phone signing). This contradicts the documented rule and adds a migration. |
| **P5-D6** | Signing surface | **A bundled local shell in the existing web view:** the same markup, the same `signature_pad` (vendored, MIT), a CSP that blocks content scripts, and a native message handler. It keeps inline approval checkboxes exactly where the terms put them. | Native `EPSignatureView` with a separate native approvals list. It cannot keep approvals inline with their clauses, and it is landscape and JPEG. |
| **P5-D7** | Which packages carry the document | **Delivery packages whose order terms are Pending** (the requirement matrix; the Phase 4 assembly precedent). Delivery readiness requires it; Return is unchanged. | Both legs, required only for Delivery: larger packages, and Return revisions churn on Terms edits. |
| **P5-D8** | `terms_accepted_at` for a phone signature | **The device capture time**, clamped by `MobileTimestamps` (when the customer actually signed). | Server receipt time, as the web does. An offline signature then reads hours late. |
| **P5-D9** | Remote images inside admin-authored terms | **Not carried offline:** all text and markup render, and an externally hosted image shows as missing while offline. Production content can't be checked from here (no production access). | Inline images as data URIs at build time: bigger packages and more code. |
| **P5-D10** | Operation type | **A new `terms.sign`** for a locally captured signature. It also records the line's `tnc_status`, so it **replaces** the thank-you `terms.accept` for this path. `terms.accept` stays for the hosted-page fallback and for ops already queued on phones. | Overload `terms.accept` with a second endpoint chosen by payload: ambiguous for handlers and for queued ops. |
| **P5-D11** | Manifest statement budget | About +4 statements (438 → about 442) stays under the **unchanged cap of 450**. Raising the cap would need approval. | — |
| **P5-D12** | Order-level scope (confirmation of existing behavior) | One signature satisfies T&C for **the order** (all its Delivery lines), because the server records it once on the order. It never satisfies another order or another revision. | Bind satisfaction to the signing line or leg. This would diverge from the server's order-level record. |

---

## 6. Expected files and components

**Backend (`kabba2_AI-dispatch-offline`):**
- New:
  - `app/Services/Terms/TermsDocument.php` (builder + value);
  - `app/Services/Terms/TermsAcceptanceService.php`;
  - `app/Http/Controllers/Api/Admin/V1/Orders/Terms/ShowController.php` and `AcceptController.php`;
  - `app/Http/Requests/Api/Admin/V1/Orders/Terms/AcceptRequest.php`;
  - migration `…_add_accepted_terms_revision_to_orders_table.php` (nullable `string(64)`).
- Changed:
  - `routes/api/admin/v1/orders/routes.php` (two routes);
  - `app/Enums/Api/ApiErrorCode.php` + its translation;
  - `app/Models/Mobile/MobileSyncIssue.php`;
  - `app/Models/Orders/Order.php` (fillable);
  - `app/Services/Dispatch/Offline/DispatchOfflineMissionPackageBuilder.php`, `DispatchOfflineOrderSections.php`, `DispatchOfflineMissionRevision.php`, `DispatchOfflineMissionSelector.php` (`WITH`).
- P5-D2 only: `Front/TermsAndConditions/IndexController.php`, `PostController.php`, `PostRequest.php`, `resources/views/front/terms_and_conditions/index.blade.php`.
- Contract:
  - `docs/mobile-integration/MOBILE_API_CONTRACT.md`;
  - `tests/Fixtures/mobile-contract/dispatch_offline_packages.json`;
  - new `terms_document.json` / `terms_accept.json` fixtures.
- Tests:
  - new `tests/Feature/Terms/TermsDocumentTest.php`, `tests/Feature/Api/Mobile/Terms/TermsAcceptContractTest.php`, `tests/Feature/Dispatch/Mobile/DispatchOfflineTermsSectionTest.php`;
  - P5-D2: `tests/Feature/Terms/TermsSigningPageRevisionTest.php`;
  - updated `DispatchOfflinePackagesTest`, `DispatchOfflineRevisionCompletenessTest`, `DispatchOfflineManifestPerformanceTest` (cap unchanged), `DispatchContractFixturesTest`.

**Mobile (`mobileapp-dispatch-offline-p5`):**
- Core new: `TermsDocument.swift`, `TermsDocumentStore.swift`, `TermsSignOperations.swift`.
- Core changed: `DispatchOfflineContract.swift`, `DispatchOfflineFieldBridge.swift`, `DispatchOfflineMissionStore.swift` (the `terms` stamp), `EffectiveFieldState.swift`, `LegCompletionRequirements.swift`, and `TermsOperations.swift` (its header comment only).
- App new:
  - `Sync/App/TermsSigningShell.swift`;
  - `Sync/App/TermsDocumentClient.swift`;
  - resources `RentnKing/Resources/TermsSigning/` (`terms-signing.html`, `terms-signing.css`, `terms-signing.js`, `signature_pad.umd.min.js`, `LICENSE-signature_pad.txt`).
- App changed:
  - `TermsSyncHandler.swift` (the `terms.sign` handler);
  - `KabbaSync.swift` (registration, store);
  - `DispatchOfflineSync.swift` (the live save for `.terms`);
  - `TermsAndConditionViewController.swift`, `OrderDetailsViewController.swift`, `OrderListButtonAction.swift`, `EmptyDataView.swift`;
  - `RentnKing.xcodeproj/project.pbxproj` (sources and bundle resources, via the Phase 4 `pbx_add.py` approach).
- Tests:
  - Core new `TermsDocumentTests`, `TermsDocumentStoreTests`, `TermsSignOperationsTests`;
  - updated `EffectiveFieldStateTests`, `LegCompletionEvaluatorTests`, `DispatchOfflineFieldBridgeTests`, `DispatchOfflineContractTests`, `TermsOperationsTests`;
  - hosted new `RentnKingTests/Hosted/DispatchOfflineTermsHostedTests.swift`.

---

## 7. Tasks (TDD, in order; each ends with a local commit)

**Backend**
1. **`TermsDocument` + revision.** Red tests:
   - byte parity with `generateTermsContent` and with the served page body;
   - the revision changes on content, signature block, attach/detach, global flip and header edits;
   - it does not change on a title/SEO edit or a customer-name change (whereas `content_sha256` does);
   - A → B → A returns A;
   - `approvals_required` counts placeholders.
2. **Package `terms` section + `sections.terms` + mission revision seed.** Red tests:
   - Delivery/Pending ships the document; Return, Accepted and Exempt give `not_applicable`;
   - a failing builder is isolated (`failed`, the rest intact) and repaired at the same revision;
   - revision completeness for Terms edits on Pending orders only;
   - manifest ≤ 450 statements and package ≤ 130 statements per order.
3. **Live `GET orders/terms/{uid}`.** Parity with the package's `terms`; auth required; read-only.
4. **`POST orders/terms/{uid}/accept` + `TermsAcceptanceService` + `TermsRevisionStale` + `terms.sign` sync-issue type + `accepted_terms_revision`.** Red tests for every row of §3.3 and every case in §3.5.
5. **(If P5-D2)** The web path binds to its displayed revision. The existing `MobileSyncIssueTest` (j), `TermsRequestEmailTest` and `SignedTermsAccessTest` must stay green.
6. **Contract fixtures + `MOBILE_API_CONTRACT.md`,** then the full affected backend regression (§9).

**Mobile**

7. **Core `TermsDocument` + `TermsDocumentStore`.** Decode and validation, tenant scoping, per-revision retention, newest-wins stamp, and the live-save company pin.
8. **Core bridge `terms` section.**
   - Ledger state and decoding a Phase 4 ledger that has no terms key.
   - Delivery readiness requires terms when Pending; Return is unchanged.
   - Same-revision repair of a failed terms section.
   - A pre-Phase-5 package gives `notProvided`.
9. **Core `terms.sign` + revision-aware satisfaction.**
   - Payload, request, multipart part, PNG asset, and durability across a store reload.
   - `EffectiveFieldState`/`LegCompletionEvaluator`: A never satisfies B, O1 never satisfies O2, legacy `terms.accept` is unchanged, and needs-attention gives `satisfiedNeedsAttention`.
10. **App signing shell + hosted shell tests.**
    - It renders offline.
    - Approvals are required, a signature is required, and submit is single-shot.
    - CSP blocks a `<script>` in content from posting.
    - Navigation away is cancelled.
11. **App screen states, message handling, live fetch, Order Details inputs,** then the hosted never-opened acceptance scenario (§8.3).
12. **Full verification** (§9), break-a-rule probes, then a fresh independent whole-Phase-5 review. Critical/Important findings are fixed and re-reviewed before closure.

---

## 8. Tests

### 8.1 Backend (parity, idempotency, freshness)
- **Parity:**
  - `TermsDocument::contentHtml` equals `generateTermsContent`, and the body the served signing page prints in `#terms-dynamic-content`;
  - the package `terms` equals `GET orders/terms/{uid}`;
  - the accepted content on the phone path equals what the web path would record for the same revision and signature.
- **Revision:** every input in §2.1 changes it; the excluded fields don't; A → B → A.
- **Mission freshness:** a Terms edit changes the revision of every **Pending** Delivery mission that uses it, and of no Accepted/Exempt one; an acceptance changes it (status).
- **Idempotency:**
  - the same op id twice gives one acceptance, one history row, one ledger row and a replay header;
  - a different op id on an accepted order gives `already_accepted` and no write;
  - a web and a phone signing racing give one acceptance (the row lock).
- **Stale:**
  - A-signed-after-B gives 409 `retryable:false`, **no** order write, and one deduplicated order-scoped Mobile Sync Issue;
  - a retry after the terms return to A gives `accepted`;
  - a retry after B was signed gives `already_accepted`.
- **Safety:**
  - an unknown order uid is rejected with no write of any kind (no order, ledger, sync issue or file);
  - a product from another order gives 422;
  - approvals short gives 422;
  - Exempt gives `not_required`.
- **P5-D2:** the hidden revision is rendered; a matching post records the displayed content; a mismatched post gives the 409 message; a missing revision is treated as current.

### 8.2 Mobile core (`swift test`)
- Document decode and validation.
- Store tenancy, freshness and retention.
- Bridge section states, readiness and repair.
- `terms.sign` builder and request.
- Revision-aware satisfaction, including the evaluator's Delivery/Return matrix.
- The screen-state resolver: a pure function, every row of §4.3.

### 8.3 Hosted (Simulator, signed `RentnKingHostedTests`)
1. **Never opened online, fully automated.**
   1. Reconcile online (a stubbed server with a Delivery/Pending package).
   2. Never open the mission.
   3. Go offline: `OfflineURLProtocol` fails every request, and the local page makes none.
   4. Order Details → T&C through the real screen resolves the cached document.
   5. The web view renders it offline: every clause's text, both approval checkboxes and the sign button are present.
   6. Sign through the page: `signaturePad.fromData`, save, approvals, submit.
   7. The op is durable before `termsSucess` fires.
   8. Leave and reopen: "Signed on this phone".
   9. Recreate the engine from the same folder (relaunch offline): the op is still pending and T&C is still satisfied.
   10. Delivery completion proceeds with no override section for T&C.
   11. Reconnect, using a stub transport that answers 200 `accepted`: exactly one POST, one `signature_media` part, `terms_revision` = A, and the `X-Operation-Id` header.
2. **Freshness:** signed A, then a newer package brings B. The A op no longer satisfies, and the screen offers B.
3. **Failure:** `sections.terms: failed`. Offline T&C shows "aren't downloaded yet" (no web load, no spinner left on screen), and the mission is not Delivery-ready.
4. **Replay:** the first send commits server-side but the response is lost (transport error); the retry gets a 200 replay. The op is synced, one op exists, and both sends carry the same operation id.
5. **Wrong mission/revision:** an O1/A op never satisfies O2, or O1 at B.
6. **Tenant:** the Company A document is invisible under B offline, and usable again under A.
7. **Stale answer:** a 409 `TERMS_REVISION_STALE` puts the op in Needs Attention with its PNG still on disk. It gives `satisfiedNeedsAttention` while the phone knows only A, and incomplete once it knows B.

---

## 9. Closing gate
- All §8 tests, red first then green.
- The complete mobile core and signed hosted suites (baseline 499 / 72).
- The simulator build.
- The no-polling/timer/GPS/socket gate. The live GET fires only on screen open.
- Break-a-rule probes for each rule in §3.3–§4.4. Each must be caught.
- The affected backend regression **from the final backend HEAD**:
  - `tests/Feature/Dispatch`, `tests/Feature/Api`, `tests/Feature/Mobile`, `tests/Unit/Push`, `tests/Feature/QueueLine`;
  - `tests/Feature/Terms`, `tests/Feature/CustomerPortal`;
  - `tests/Feature/Orders` and `tests/Feature/CustomerChecklists`, whose baseline failures must match **by test name**.
- Both worktrees clean with no upstream.
- A **fresh independent reviewer** reporting no Critical or Important issues.

Then stop before Phase 6.

---

## 10. Recorded risks, boundaries and deferred items

### 10.1 Accepted deferred risk — cross-customer Sync Engine queue ownership
- **The risk:** Sync Engine operations carry no company, so work queued under one Kabba customer instance could be sent with another's session after an unsynced company switch on the same phone.
- **It is accepted as a low-probability deferred risk:** Kabba currently has three customers, customer devices are geographically and operationally separate, and switching one device between Kabba customer instances while unsynced work exists is considered exceptionally unlikely. Phase 5 does not tenant-scope the Sync Engine.
- **T&C-specific check, which does not make the risk materially worse:**
  - A `terms.sign` op sent to the wrong company names an order uid that company doesn't have. The request is rejected (422/404) **before any write**, so no order, ledger row, sync issue or file is stored. The op parks as Needs Attention on the phone.
  - The customer's signature image would reach the other company's server in that rejected request. That is the same exposure class as today's checklist customer signature and license photo operations.
  - The new document cache is tenant-scoped (§4.5).

### 10.2 Watch items (not fixed in Phase 5)
- **Signature files outlive their records.** A synced signature file stays on disk after `pruneSynced` deletes its record after 7 days. This is pre-existing for every non-media handler; `terms.sign` follows the checklist signature.
- **Reminders can overlap an unsynced signature.** The existing automatic Terms reminders can text a customer whose signature is still unsynced on an offline phone.
- **A stale signature exists only on the phone (P5-D5).** A person's Discard, or deleting the app, removes it.
- **Terms documents on the phone are never pruned,** like Phase 4's bridged caches.
- **Pre-existing, out of scope:**
  - the new-order success screen's T&C button never opens (`strOrderUniqueId` unset);
  - Order Details' T&C button checks `status == "Exempt"` instead of `terms_status` (the new screen shows the "not required" state either way);
  - `Terms::global()->first()` has no ordering (kept identical so the parity holds).

### 10.3 Scope boundaries (unchanged)
Phase 5 does not:
- redesign Dispatch or Order Details;
- revisit Phase 3/4 deferred cosmetic items;
- build generic document signing or arbitrary document storage;
- solve the cross-customer queue issue;
- change the Warning override or its permissions;
- begin Phase 6 physical acceptance.

---

## 11. Evidence that the Phase 5 scope needs to change
1. **Online signing already breaks the core rule** (§0.3). Fixing it means touching the customer-facing web signing path (P5-D2). It is small, but it is outside "offline only".
2. **There is no Terms content API and no API-authenticated acceptance endpoint.** The only acceptance write is a public, CSRF-protected web route. Phase 5 needs two new mobile endpoints, `GET orders/terms/{uid}` and `POST orders/terms/{uid}/accept`, beyond the package section.
3. **`TermsService` documents a "no second terms or signature record" rule.** Server-side preservation of stale signatures would contradict it, so P5-D5 recommends phone-side preservation instead.
4. **Phase 5 introduces the app's first bundled web resources** (the shell and the vendored `signature_pad`, MIT) and its first script-message bridge.
5. **"Full content renders offline" holds for text and markup.** Remote images inside admin-authored terms cannot render offline (P5-D9); whether production content has any could not be checked from here.
6. **Online Dispatch signing changes too** if P5-D3 is approved: a locally rendered page instead of the hosted page. That is a visible behavior change for drivers who are online.
7. **The manifest budget is near its cap:** 438 of 450, with about 442 expected.
