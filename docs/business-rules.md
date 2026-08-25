# Business Rules

## Money & wallet

- **Units**: all amounts are integer minor units; 100 minor = 1 RWF. The
  mobile client formats via `formatRwf()` — never floats in the API/DB.
- **Ledger**: `wallet_ledger_entries` is append-only. Balances are snapshots
  maintained transactionally (`balance_after_minor`), never recomputed from
  sums at request time.
- **Idempotency**: every ledger write carries a unique idempotency key
  (webhook `event_id`, sync `client_op_id`, withdrawal reference). Replays are
  detected and return the original outcome without side effects.
- **Escrow**: on payment success the seller's gross goes to
  `pending_balance_minor`; after `ESCROW_CLEARANCE_HOURS` (default 48, beat
  task) it moves to available.
- **Platform fee** (default 2.5%): charged to the seller at credit time as a
  separate DEBIT entry against the `platform-fee-sink` system wallet.
- **Withdrawals**: only from available balance; states PENDING → APPROVED →
  SENT / REJECTED; admin action required.

## Offer negotiation state machine

```
PENDING ──accept──> ACCEPTED            (creates Order, locks inventory)
   │ ├────reject───> REJECTED
   │ ├────counter──> COUNTERED ──(new child offer PENDING; parent closed)
   │ └────withdraw─> WITHDRAWN     (only by creator while PENDING)
   └──expiry task──> EXPIRED
```

- Only the listing's buyer counterparties can offer; the seller cannot offer
  on their own listing (`SELF_OFFER`).
- Counter-offers preserve original buyer/seller roles regardless of who
  counters.
- Accepting decrements `inventories.quantity_reserved`; overselling is
  impossible under concurrency (row-locked conditional UPDATE).
- Terminal offers cannot transition again.

## Auctions

- Bids must exceed current highest bid by ≥ min increment.
- **Anti-sniping**: a bid inside the final window extends `ends_at` by the
  extension interval.
- Auction close (beat task) awards the highest bidder, creates an Order, and
  rejects losers with notification.
- Fixed-price listings reject bids with `NOT_AN_AUCTION`.

## Orders

```
PENDING_PAYMENT → PROCESSING → READY_FOR_PICKUP → PICKED_UP → IN_TRANSIT
      │                …                → DELIVERED → COMPLETED
      └→ CANCELLED (buyer before payment; admin/system after)
                      DISPUTED (from any active state; freezes transitions)
```

- Payment transitions are owned exclusively by the payment webhook
  (`PAYMENT_SYSTEM_ONLY` otherwise).
- COMPLETED bumps both parties' `completed_transactions` and rating averages
  once reviews exist; disputes freeze completion until resolved.
- Delivery chain: farmer/buyer requests delivery → couriers quote → acceptance
  schedules pickup → courier advances PICKED_UP → IN_TRANSIT → DELIVERED.

## Payments & webhooks

- Providers are configured as `<name>:<webhook_secret>` pairs.
- Signature: HMAC-SHA256 over `{timestamp}.{raw_body}` in headers
  `X-Ijwi-Timestamp` / `X-Ijwi-Signature`. Stale timestamps (>10 min) and bad
  signatures are rejected (`400 INVALID_WEBHOOK_SIGNATURE`).
- Transaction states: INITIATED → SUCCEEDED / FAILED / TIMEOUT. Success
  triggers escrow credit + order advance exactly once.

## Messaging

- Every message carries a client-generated `client_message_id`; duplicates
  return the original message flagged `duplicate: true` (offline-safe sends).
- Group conversations enforce per-role permissions
  (`can_message`, `can_add_members`, `can_edit_group`, …) from
  `DEFAULT_ROLE_PERMISSIONS` with optional per-group overrides.
- Banned members: `GroupBan` row + `is_banned` flag; banned users receive
  `GROUP_BANNED` on send/join attempts even if stale membership rows linger.
- Direct chats: blocking is bidirectional-enforced at send time
  (`BLOCKED_BY_USER` / `YOU_BLOCKED_USER`).

## Sync protocol (offline-first)

- Push: `POST /sync/push {operations: [{client_op_id, op_type, payload}]}`
  → per-op results `OK | DUPLICATE | RETRY | REJECTED`. Supported ops:
  `message.send`, `listing.create_draft`, `status.create`,
  `farm.crop.record`.
- Pull: `GET /sync/pull?collections=a,b&a_cursor=<ts>` → changed entities +
  new cursors based on `updated_at`.

## Rate limits

Login/OTP: strict per-IP+phone buckets. AI assistant: 20/hour/user.
Voice reports: 30/day/user. Webhook endpoint: exempt. Uploads: 30/min.
