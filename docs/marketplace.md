# Marketplace — Audit, Gap Matrix & Implementation Plan

**Date:** 2026-09-04
**Scope:** Flutter mobile client (`mobile/`) + Flask backend (`backend/`).
**Method:** AUDIT → UNDERSTAND → MAP → REFACTOR → IMPLEMENT → CONNECT → TEST → POLISH

---

## 1. What exists today

### Backend (rich, largely complete)
- **Domain models** (`backend/app/models/`): catalog (products/categories/units), marketplace (listings, inventory + reservations, buyer requests, promotions, favorites, saved searches), trade (offers, bids, contracts), orders (+ order events, reviews), payments (transactions, webhooks, wallet + double-entry ledger, withdrawals, platform fees, subscriptions), logistics (vehicles, delivery requests, quotes, deliveries, events), identity (users, roles, farmer/buyer/supplier/logistics/expert profiles, cooperatives, verification, certifications, devices), farms (farms, crops, livestock, production/expense/business records, plans), community (groups, channels, posts, statuses), intelligence (market prices, advisory, alerts), notifications, admin (audit logs, risk events, reports).
- **Services** (`backend/app/services/`): listing, inventory (reservation/locking), offer (negotiation state machine), bid (anti-sniping auctions), order (transition FSM), payment (webhooks, idempotency, escrow), wallet, delivery, matching engine (opportunities), recommendation, reputation, risk, notification, realtime (socket.io rooms `user:{id}`, `conversation:{id}`, `product:{id}`, `alerts`), sync (push/pull with cursors + client idempotency), storage/uploads, aggregation (cooperative settlement).
- **API** (~205 routes, all mapped in `docs/api.md`). Error envelope: `{"error": {"code", "message", "details"}}`. Lists return `{"items": [...], "pagination": {...}}`.
- **Tests**: e2e marketplace loop, communication loop, business-rule failures, concurrency/webhook failure modes. `pytest` suite green baseline.

### Flutter client (thin, partially connected)
- Stack: Riverpod, go_router, dio (+JWT refresh), sqflite offline cache + outbox sync engine, socket_io_client realtime, cached_network_image, geolocator, image_picker, share_plus, fl_chart.
- Screens: splash, onboarding, auth, home tab (dashboard), **market (basic listing list + price strip)**, listing detail (minimal offer/bid bottom sheet), offers (list + accept/reject), orders (list + pay), wallet, sell hub + create-listing wizard, plus community/chat/intelligence/notifications.
- **Gap:** no repository layer, API calls inside widgets, thin models, no filters/sorting UI, no buyer-request UI, no favorites UI, no saved-search UI, no search-first experience, no rich seller/trust/quality surfaces, no order detail/timeline, limited realtime consumption.

---

## 2. Confirmed bugs found during audit (backend)

| File | Bug | Impact |
| ---- | --- | ------ |
| `backend/app/api/platform.py` | `add_favorite`/`remove_favorite`/`list_favorites` use `Favorite.listing_id` and `Listing.favorite_count` — neither column exists (Favorite is `user_id/subject_type/subject_id`; Listing has no counter). | **Favorites endpoints 500.** |
| `backend/app/api/platform.py` | `create_saved_search`/`list_saved_searches` use `SavedSearch(name=, notify_push=)`; model fields are `label` and `notify_on_new_matches`. | **Saved searches 500 / broken payload.** |
| `backend/app/api/platform.py` | `global_search` farmers scope queries `FarmerProfile.is_searchable`, which does not exist. | **Global search 500.** |

All three are fixed in this work item.

**Bonus bug found via concurrency test:** `inventory_service.reserve()` read availability
without locking, so two buyers racing for the last units could both reserve the same stock
(lost update / oversell). Rows are now locked `SELECT … FOR UPDATE` in id order; the existing
`test_no_oversell_under_concurrency` went from failing to passing.

**Bonus route mismatch:** `listing_price_advisor` was registered at
`/listings/<listing_id>/price-advice` but the handler reads `product_id` from the JSON body
on a GET — unusable by any client. Added `/api/v1/price-advice` and made the handler accept
query params. Saved-search also stored a dict into a `Text` column (crash) — now JSON-encoded.

---

## 3. Feature gap matrix

Legend: ✅ WORKING · 🟡 PARTIAL · 🔶 BACKEND-ONLY · 🟥 BROKEN · ⬜ MISSING · ♻️ NEEDS REFACTOR

| Feature | Backend | Frontend | API connected | Realtime | Offline | Permissions | Notifications | Tests | Status |
| ------- | ------- | -------- | ------------- | -------- | ------- | ----------- | ------------- | ----- | ------ |
| Catalog products/categories | ✅ | 🟡 (sell wizard only) | 🟡 | – | 🟡 | – | – | ✅ | 🟡 partial |
| Listings browse | ✅ | 🟡 (flat list) | ✅ | 🟡 | 🟡 | ✅ | – | ✅ | 🟡 partial |
| Listing create | ✅ | ✅ wizard | ✅ | ✅ emit | ✅ outbox | ✅ | – | ✅ | ✅ |
| Listing detail | ✅ | 🟡 minimal | ✅ | – | – | ✅ | – | ✅ | 🟡 partial |
| Listing media | ✅ | ⬜ | ⬜ | – | – | ✅ | – | – | 🔶 backend-only |
| Listing edit/pause/close | ✅ | 🟡 close only | ✅ | – | – | ✅ | – | ✅ | 🟡 partial |
| Listing price advisor | ✅ | ⬜ | ⬜ | – | – | ✅ | – | – | 🔶 backend-only |
| Offers (make/counter/accept/reject/withdraw) | ✅ | 🟡 (accept/reject only) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 partial |
| Bids / auctions | ✅ | 🟡 (place only) | ✅ | ✅ | – | ✅ | ✅ | ✅ | 🟡 partial |
| Buyer requests (RFQ) | ✅ | 🟥 none | ⬜ | – | – | ✅ | ✅ | ✅ | 🔶 backend-only |
| Buyer request matching / opportunities | ✅ | 🟡 (community-only view) | 🟡 | – | – | ✅ | ✅ | – | 🟡 partial |
| Cart | ⬜ (deliberate: offer→order loop) | ⬜ | – | – | – | – | – | – | ⬜ deferred (see §6) |
| Orders list/detail | ✅ | 🟡 list only | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 partial |
| Order transitions / timeline | ✅ | 🟥 none | 🟡 | ✅ | – | ✅ | ✅ | ✅ | 🟡 partial |
| Payments (initiate/webhook) | ✅ | ✅ pay | ✅ | ✅ | – | ✅ | ✅ | ✅ | ✅ |
| Wallet / ledger / withdrawal | ✅ | 🟡 (wallet only; withdraw payload mismatch) | 🟡 | ✅ | – | ✅ | ✅ | ✅ | 🟡 partial |
| Logistics (requests/quotes/deliveries) | ✅ | 🟥 none | ⬜ | – | – | ✅ | ✅ | ✅ | 🔶 backend-only |
| Reviews / reputation | ✅ | 🟥 none | 🟡 | – | – | ✅ | ✅ | ✅ | 🔶 backend-only |
| Favorites | 🟥 broken | 🟥 none | 🟥 | – | 🟡 | ✅ | – | – | 🟥 broken |
| Saved searches | 🟥 broken | 🟥 none | 🟥 | – | – | ✅ | – printed | – | 🟥 broken |
| Global search (products/listings/farmers/groups) | 🟥 broken | 🟥 none | 🟥 | – | – | – | – | – | 🟥 broken |
| Price alerts / market prices | ✅ | 🟡 price strip | ✅ | ✅ | 🟡 | – | – | – | 🟡 partial |
| Notifications (list/prefs/deeplinks) | ✅ | ✅ list | ✅ | ✅ | 🟡 | ✅ | ✅ | – | 🟡 partial |
| Sell dashboard (views/offers/orders/revenue) | ✅ data exists | 🟥 none | 🟡 | – | – | ✅ | – | – | 🔶 backend-only |
| Community ↔ marketplace (share listing) | ✅ | 🟡 (status bridge only) | 🟡 | – | – | ✅ | – | – | 🟡 partial |
| Chat from listing ("message seller") | ✅ | 🟥 none | ⬜ | ✅ | ✅ | ✅ | ✅ | ✅ | 🔶 backend-only |
| Currency display (minor units) | ✅ | 🟡 RWF-only labels | ✅ | – | – | – | – | – | 🟡 partial |
| Offline marketplace browse | 🟡 sync cache | 🟡 (cache exists, not surfaced) | 🟡 | – | ✅ | – | – | – | 🟡 partial |
| Admin marketplace mgmt | ✅ | ⬜ (web/ops tool out of scope) | – | – | – | ✅ | – | ✅ | ✅ backend |

---

## 4. API contract map (frontend → backend)

All amounts are **integer minor units** (100 minor = 1 RWF). Auth `Authorization: Bearer <access_token>`. Lists paginated via `page`/`per_page`.

### Catalog & discovery
| Dart call | Backend | Notes |
| --------- | ------- | ----- |
| `categories()` | GET `/categories` | `{categories: [{id,name,slug,icon}]}` |
| `products({category,q})` | GET `/products` | paginated `items[]` with `id,name,slug,emoji,category{id,name}` |
| `listings({product,region,quality_grade,listing_type,min_quantity,sort,page})` | GET `/listings` | `items[]: Listing` |
| `listing(id)` | GET `/listings/{id}` | `listing: Listing` + `media[{type,storage_key,caption}]` |
| `search(q,{scope})` | GET `/search` | `{products[], listings[], farmers[], groups[], query}` |

### Trade
| Dart call | Backend | Notes |
| --------- | ------- | ----- |
| `createOffer` | POST `/offers` | body: listing_id or buyer_request_id, quantity_value, price_minor, unit_code, currency_code, delivery_option, payment_terms, message, expires_in_hours |
| `counterOffer(id, price)` | POST `/offers/{id}/counter` | returns new Offer (state COUNTERED on parent) |
| `acceptOffer(id)` | POST `/offers/{id}/accept` | returns Order (201) |
| `rejectOffer / withdrawOffer` | POST `/offers/{id}/reject` · `/withdraw` | |
| `offers(role,state)` | GET `/offers/mine?role=buyer\|seller` | paginated `items[]: Offer` |
| `listingOffers(id)` | GET `/listings/{id}/offers` | seller sees all; buyer sees own |
| `placeBid` | POST `/bids` | `{listing_id, amount_minor, quantity_value}` |
| `listBids(id)` | GET `/listings/{id}/bids` | `bids[]` |
| `acceptWinningBid(id)` | POST `/listings/{id}/accept-winning-bid` | |
| `buyerRequests()` | GET `/buyer-requests` | paginated `items[]: BuyerRequest` |
| `createBuyerRequest` | POST `/buyer-requests` | |
| `requestMatches(id)` | GET `/buyer-requests/{id}/matches` | `{matches[]}` w/ match score |
| `farmerOpportunities()` | GET `/opportunities` | `{opportunities[]}` |

### Orders & payments
| Dart call | Backend | Notes |
| --------- | ------- | ----- |
| `createOrderDraft(listing,qty)` | POST `/orders/draft` | returns Order state PAYMENT_PENDING (inventory reserved) |
| `orders({state,role})` | GET `/orders` | paginated `items[]: Order` |
| `order(id)` | GET `/orders/{id}` | `order` + `events[]` timeline |
| `transitionOrder(id,state,reason)` | POST `/orders/{id}/transition` | backend FSM enforced; PAID blocked (webhook-only) |
| `cancelOrder(id,reason)` | POST `/orders/{id}/cancel` | |
| `initiatePayment(orderId, provider, method, phone)` | POST `/orders/{id}/payments` | never mark paid locally; poll order/query wallet |
| `wallet()` / `walletLedger()` | GET `/wallet` · `/wallet/ledger` | |
| `withdraw(amount_minor, method, destination_detail)` | POST `/wallet/withdrawals` | ⚠️ current Flutter sends wrong keys (`destination`) |
| `createReview(orderId,…)` | POST `/orders/{id}/reviews` | only completed orders; one per party |

### Seller & social
| Dart call | Backend | Notes |
| --------- | ------- | ----- |
| `farmers()` / `farmer(id)` | GET `/users/farmers` · `/users/{id}` | farmer card (rating, crops, tier) |
| `favorites()` / `addFavorite(listing)` / `removeFavorite(id)` | GET/POST `/favorites` · DELETE `/favorites/{id}` | fixed in this change |
| `savedSearches()` / `createSavedSearch` / `deleteSavedSearch` | GET/POST/DELETE `/saved-searches` · `/saved-searches/{id}` | fixed in this change |
| `startConversation(withUserId, context, listingId)` | POST `/conversations` | returns convo id → open `/chat/{id}` |
| `uploadFile(category)` | POST `/uploads/{category}` | multipart `file` |

---

## 5. Architecture

```
UI (marketplace screens)
  ↓
Controllers/ViewModels (Riverpod Notifier/Provider per screen; no API in widgets)
  ↓
MarketplaceRepository (features/market/marketplace_repository.dart)
  ↓
ApiClient (dio, JWT refresh)          LocalDb cache + SyncEngine outbox
  ↓
Flask API (backend) / SQLite cache
```

- **Source of truth:** backend owns inventory, pricing, fees, order state, offer/bid validity, permissions, payments. Flutter renders state and only drives user intent.
- **Realtime:** socket events are consumed by screen controllers through a shared `MarketRealtime` mixin (`features/market/market_realtime.dart`) that debounces bursts (e.g. rapid `bid.placed`) before reloading, so the UI tracks live state without manual pull and without hammering the API.
- **Offline:** browse cached `listings`/`categories`; mutations go through `SyncEngine.enqueue` where the backend supports idempotent client ops; financial operations require connectivity.

## 6. Scope decisions (this iteration)

1. **No cart UI**: backend deliberately routes purchases through offer → order (direct `Buy Now` uses `/orders/draft` for fixed-price listings). A multi-seller cart is out of the backend's current model; keep the offer/order loop as the canonical flow.
2. **RWF only in UI for now**: backend stores `currency_code`; UI renders symbol + code from the amount's currency rather than hardcoding RWF, but conversion is not implemented (no exchange-rate feed). Converted amounts are never fabricated.
3. **No fake data**: all screens render real API responses; empty/error states are first-class.
4. Backend changes are limited to fixing real bugs and the minimal additions the frontend legitimately needs (none new beyond fixes, initially).

## 6b. What this work item delivered

### Backend (all fixes covered by new regression tests in `tests/integration/test_marketplace_discovery.py`)
- Favorites fixed and round-trip tested (`Favorite` subject model + listing serializer).
- Saved searches fixed (JSON storage, correct fields) and round-trip tested.
- Global search farmers scope fixed (removed non-existent `is_searchable`) and tested.
- `/listings` gains `category` (slug), `negotiable`, `verified` filters and `sort=`
  `price_asc|price_desc|recent|quantity_desc|rated|ending_soon`.
- `/api/v1/price-advice` route (query-param friendly) added.
- `inventory_service.reserve()` row locking prevents oversell under concurrency.
- Test suite: **29 passed** (23 pre-existing + 6 new), including the concurrency race.

### Flutter marketplace
- Data layer: `marketplace_models.dart` (models mirror the backend serializers exactly) and
  `marketplace_repository.dart` (`Paged<T>` lists, typed methods for every endpoint below).
- Marketplace home (`/market`): search entry, category rail, market-price strip, buyer
  opportunities with in-card “Respond with offer”, for-you listings, latest-harvest rail.
- Search (`/market/search`): predictive suggestions (products/listings/farmers/groups),
  backend-filtered results, mobile filter bottom sheet, active filter chips, sort sheet,
  “Save this search”.
- Listing detail: availability/quality/listing-type badges, auction panel (countdown, live
  bids, accept winning bid for the seller), details incl. delivery options & certification,
  seller trust card (verification, rating, view profile), favorite/share, Message seller
  (starts a real conversation), sticky Buy now / Make offer / Bid bar.
- Buyer Requests (`/market/requests`) browse + post; favorites (`/market/favorites`).
- Offers: fixed broken GET `/offers` → `/offers/mine`, Received/Sent tabs, accept / counter /
  reject / withdraw.
- Orders: state filters, order detail with backend timeline, role-aware transitions,
  payment initiation, cancel, and post-completion review flow.
- Sell flow: quality grade, delivery options, available quantity, auction end time, live
  market-range price advice; my-listings pause / activate / close.
- Wallet withdrawal fixed to backend schema (`method` + `destination_detail`).
- Router: `/market/search`, `/market/requests`, `/market/favorites`, `/orders/:id`; money
  helpers now render each listing’s own currency code; 26 marketplace i18n keys added to
  en/rw/fr/sw.

### Realtime wiring (marketplace)
- `socket_service.dart` registers the marketplace event fan-out the backend actually emits:
  `listing.created`, `offer.created/updated/accepted`, `order.created/updated`,
  `delivery.updated`, `bid.placed/accepted`, `wallet.updated`.
- `MarketRealtime` mixin: screens subscribe per-event with a debounce; detach on dispose.
- Marketplace home refreshes on `listing.created`; offers screen on `offer.*`; orders list on
  `order.*`; order detail reloads only when `order.updated.order_id` / `delivery.updated`
  match the open order; listing detail updates the auction end time + bid list live on
  `bid.placed`/`bid.accepted` (filtered to that listing); wallet refreshes on `wallet.updated`.
- Backend: `wallet_service.post_entry` (single funnel for every balance mutation) now emits
  `wallet.updated` to the wallet owner, so balance changes from payments, escrow releases
  and withdrawals appear live.

### Offline marketplace home (spec §93–94)
- `MarketplaceRepository` write-through-caches listing feed rows into `LocalDb`
  (`listings` collection, shared with the sync engine) on every successful fetch;
  `cachedListings()` reads them back.
- New `ApiClient.isOfflineError` (connection timeouts / socket / DNS failures). When the
  marketplace home fails with one, `MarketScreen` renders an amber offline banner +
  “Saved listings” from the cache instead of an error, with Retry / pull-to-refresh;
  on first-ever launch with no cache it still shows the retryable error box.

### Seller dashboard (spec §66/§128–130)
- New `GET /api/v1/seller/dashboard` (`app/api/dashboard.py`): one round trip of
  server-aggregated metrics from the seller's own rows — summary (active listings, total
  views from real `Listing.view_count`, pending/total offers, open/completed/closed-out
  orders, gross sales, platform fees, net revenue), wallet (available/pending/total
  earned), per-listing performance (views, pending offers, order count, sold value),
  and recent offers/orders enriched with counterparty name + listing title.
- Flutter: `SellerDashboardScreen` at `/sell/dashboard` (entry: Insights icon in the Sell
  hub). Revenue + escrow header, rating/reputation tier, KPI grid, listing performance,
  recent orders (→ order detail) and incoming offers (→ offers). Live refresh via the
  `MarketRealtime` mixin on `offer.created/updated`, `order.updated`, `wallet.updated`;
  empty state guides new sellers to publish.
- Regression test: `tests/integration/test_seller_dashboard.py` — asserts counts, views,
  revenue and wallet credits reflect real offer/order activity.

### Reviews on farmer profiles & listing detail (spec §81–83)
- New `GET /api/v1/users/<id>/reviews` (`account.user_reviews`): a user's received reviews
  newest-first with reviewer, order and listing context. Regression-tested end-to-end
  (complete order → review → aggregates update).
- Fixed latent bug: `GET /users/<id>` always 500'd (route converter `user_id` vs handler
  param `farmer_id` mismatch); `farmer_card` now exposes `rating_count`.
- Flutter: `ReputationSummary`/`UserReview` models + repository methods, shared
  `review_widgets.dart` (`StarRow`, `ReviewCard`, `ReputationHeader`, self-loading
  `SellerReviewsPreview`). Listing detail shows the seller's recent reviews + aggregate
  under the seller card (hidden when none); farmer profiles get a Reviews section from
  `/reputation/users/<id>` + `/users/<id>/reviews` (best-effort, never blocks the page).

## 7. Traceability of spec coverage

- §5 API mapping → §4, §8–16 home/search/filters/cards, §17–21 seller/trust/quality, §23–24 availability/units, §28–29 checkout (offer→order), §30–35 negotiation/auctions, §36–40 RFQ/matching/opportunities, §50–52 favorites/saved searches/price alerts, §55–58 chat/orders/timeline, §61–63 payments/fees, §80–83 reviews/reputation/trust, §66/§128–130 seller dashboard/analytics/insights, §81–83 reviews/reputation/trust badges, §84–87 realtime events/notifications/inventory, §88–94 search performance/discovery/offline, §93–94 low-bandwidth/offline browsing, §97–101 listing forms, §136 deep links, §138–139 localization, §140–150 visual design/states, §152–157 pagination/caching/state, §160 backend authority, §170 API error mapping, §226–229 no fakes/duplicates, §231 cleanup.