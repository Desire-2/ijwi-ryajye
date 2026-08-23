# Ijwi Ryajye Mobile — Master Build Prompt

> The canonical specification for the Flutter frontend. Any engineer (human or
> AI) extending this app must follow it. The Flask backend in `backend/` is the
> single source of truth for every API contract.

## Mission

**IJWI RYAJYE** — *"Your voice. Your farm. Your market."*
A global farmer network: marketplace, offers/bidding, orders & payments,
logistics, WhatsApp-grade messaging, groups/communities/channels/status,
market intelligence, weather, advisory, AI assistance, reputation.
One coherent ecosystem — not glued-together demos.

## Non-negotiable rules

1. **Audit before building.** Inspect existing code; modify/refactor rather
   than duplicating (`home_screen_new.dart` patterns are forbidden).
2. **Backend is authoritative.** Never invent endpoints, response shapes,
   order states, or permissions. Verify against `backend/app/api/__init__.py`
   and serializers. Money = integer minor units (100 minor = 1 RWF).
3. **No fake data in production screens. No dead buttons. No disconnected
   screens.** Every action navigates, submits, or is disabled with a reason.
4. **Offline-first where safe:** reads served from sqflite cache; chat sends
   queue to the outbox; payments/withdrawals require connectivity.
5. **Realtime over polling:** socket.io rooms `user:{id}`, `conversation:{id}`,
   `product:{id}`, `alerts`; events listed below.
6. **Farmer-first UX:** large targets, clear labels, voice-friendly,
   low-bandwidth tolerant, works on inexpensive Android phones.

## Architecture

```
UI (screens/widgets)  →  Controllers (Riverpod StateNotifiers)
      →  Repositories  →  ApiClient (dio) / LocalDb (sqflite) / SocketService
```

- Feature-first layout under `lib/features/<feature>/`.
- One centralized `ApiClient` (auth header injection, single-flight token
  refresh on 401, error envelope parsing).
- One `SyncEngine`: outbox ops `{client_op_id, op_type, payload}` →
  `POST /sync/push` (server dedupes by client_op_id); incremental cache via
  `GET /sync/pull?collections=a,b&a_cursor=<ts>`.
- go_router with auth redirect; deep links:
  `/listing/{id}`, `/chat/{id}`, `/order/{id}`, `/group/{id}`.

## API integration map (verified against backend)

| Feature | Endpoints | Response wrapper |
| --- | --- | --- |
| Auth | `/auth/register`, `/auth/verify_otp`, `/auth/login`, `/auth/refresh`, `/auth/logout`, `/users/me` | flat tokens; verify_otp nests `tokens` |
| Farms | `/farms`, `POST /farms` | `{farms:[to_dict]}` / `{farm}` |
| Listings | `/listings?product=&page=`, `/listings/mine`, `POST /listings`, `/listings/{id}` | `{items,pagination}` / `{listing}` |
| Buyer requests | `/buyer-requests` | `{items,pagination}` |
| Offers/Bids | `/offers`, `/offers/{id}/accept|reject|counter`, `/bids`, `/listings/{id}/offers` | `{offer}` / `{items}` |
| Orders/Payments | `/orders`, `/orders/{id}/payments`, `/payments/webhook/{provider}` | `{order}` / `{payment}` |
| Wallet | `/wallet`, `/wallet/ledger`, `/wallet/withdrawals` | flat summary `{available_minor,pending_minor,…}`, `{entries,…}` |
| Delivery | `/delivery-requests(+/{id}/quotes)`, `/deliveries/{id}/advance` | |
| Messaging | `/conversations` (+`type=GROUP`), `POST /conversations {with_user_id,context,listing_id}`, `/conversations/{id}/messages?limit=&before_sequence=`, `/conversations/{id}/read`, `/messages/{id}/react {emoji}`, search/save/pin/delete-for-* | `{conversations}` / `{message,duplicate}` / `{messages}` |
| Message payload | `{client_message_id*, message_type, body_text, reply_to_message_id, entity_ref_type, entity_ref_id, entity_snapshot, attachments[{type,storage_key,file_name,size_bytes,duration_ms}], voice_duration_ms, waveform}` | message types: text,image,video,voice,document,location,listing_card,order_card,offer_card,poll_card,event_card,system |
| Groups | `/groups`, `/groups/{id}`, members/join/invites/knowledge/documents/announcements | `{groups}` / `{group}` |
| Communities/Channels | `/communities`, `/channels`, `/channels/{id}/posts` | |
| Status | `/statuses`, `POST /statuses`, react/view | `{statuses}` |
| Intelligence | `/market-prices?days=1&limit=`, `/market-prices/trend?product=`, `/weather`, `/advisory/articles`, `/ai/chat {messages:[{role,content}]}` → `{reply:{answer}}` | prices public; others JWT |
| Notifications | `/notifications`, `/notifications/read-all`, `/notifications/{id}/read` | `{items,pagination}` |
| Opportunities | `/opportunities` | personalized list |
| Uploads | `POST /uploads/{category}` multipart `file` → `{storage_key,content_type,size_bytes}` | media URL = `$MEDIA_BASE/uploads/<storage_key>` |

Error envelope: `{error: {code, message, details?, request_id}}`.
Pagination envelope: `{items: [...], pagination: {page, per_page, total}}`.

## Realtime events consumed

`notification`, `message.new`, `message.read`, `typing`, `conversation.updated`,
`offer.updated`, `order.updated`, `wallet.updated`, `price.alert`,
`emergency.alert`, `call.signal`, `group.member_joined`, `group.member_removed`,
`group.announcement`, `sync.pushed`. Handshake auth: `{'token': accessJwt}`.
Emitted by client: `conversation.join|leave`, `typing`, `message.read`,
`product.subscribe`, `alerts.subscribe`.

## Design system

Material 3 base; semantic tokens in `core/theme/design_system.dart`
(`IjwiColors.green #1B7A43`, amber `#F5A623`, ink `#17251D`; radii 8/14/22;
48px minimum touch height). Shared components live in `lib/shared/widgets/ui.dart`
(EmptyState, ErrorBox, SectionHeader, StatChip, Skeleton). Splash animation ends:

```
IJWI RYAJYE
Your voice. Your farm. Your market.
powered by AfriTech Bridge        ← exact casing, bottom of splash
```

## Localization

Runtime-loaded JSON under `assets/lang/{en,rw,fr,sw}.json`;
`trProvider` returns `t(key)`; never hardcode user-facing strings.
Prefer farmer language: "Sell Your Harvest", "Find Buyers", "Ask Ijwi".

## Definition of done (per screen)

loading skeleton · empty state · error state · offline behavior · realtime
updates where relevant · deep-linkable route · analyzer-clean · wired to real
endpoints only.
