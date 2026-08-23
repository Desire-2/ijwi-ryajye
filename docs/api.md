# API Reference

Base URL: `/api/v1` · Auth: `Authorization: Bearer <access_token>`

Total endpoints: **201**. All list endpoints accept `page` & `per_page`.

## Authentication & identity

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/admin/users` |
| POST | `/api/v1/admin/users/<user_id>/suspend` |
| POST | `/api/v1/admin/users/<user_id>/unsuspend` |
| GET | `/api/v1/admin/verifications` |
| POST | `/api/v1/admin/verifications/<verification_id>` |
| POST | `/api/v1/auth/login` |
| POST | `/api/v1/auth/logout` |
| POST | `/api/v1/auth/otp/request` |
| POST | `/api/v1/auth/otp/verify` |
| POST | `/api/v1/auth/refresh` |
| POST | `/api/v1/auth/register` |
| GET | `/api/v1/reputation/users/<user_id>` |
| GET | `/api/v1/users/<user_id>` |
| GET | `/api/v1/users/farmers` |
| GET | `/api/v1/users/me` |
| PATCH | `/api/v1/users/me` |
| POST | `/api/v1/users/me/deletion-request` |
| GET | `/api/v1/users/me/export` |
| POST | `/api/v1/verifications` |
| GET | `/api/v1/verifications/mine` |

## Farms & catalog

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/crops/<crop_id>/production-records` |
| GET | `/api/v1/farms` |
| POST | `/api/v1/farms` |
| DELETE | `/api/v1/farms/<farm_id>` |
| GET | `/api/v1/farms/<farm_id>` |
| PATCH | `/api/v1/farms/<farm_id>` |
| GET | `/api/v1/farms/<farm_id>/business-records` |
| POST | `/api/v1/farms/<farm_id>/business-records` |
| POST | `/api/v1/farms/<farm_id>/crops` |
| POST | `/api/v1/farms/<farm_id>/expenses` |
| POST | `/api/v1/farms/<farm_id>/livestock` |
| POST | `/api/v1/farms/<farm_id>/plans` |
| GET | `/api/v1/products` |

## Listings

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/listings` |
| POST | `/api/v1/listings` |
| GET | `/api/v1/listings/<listing_id>` |
| PATCH | `/api/v1/listings/<listing_id>` |
| POST | `/api/v1/listings/<listing_id>/accept-winning-bid` |
| GET | `/api/v1/listings/<listing_id>/bids` |
| POST | `/api/v1/listings/<listing_id>/close` |
| GET | `/api/v1/listings/<listing_id>/offers` |
| GET | `/api/v1/listings/<listing_id>/price-advice` |
| GET | `/api/v1/listings/mine` |

## Offers & negotiation

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/bids` |
| POST | `/api/v1/bids/<bid_id>/accept` |
| POST | `/api/v1/bids/<bid_id>/retract` |
| GET | `/api/v1/buyer-requests` |
| POST | `/api/v1/buyer-requests` |
| GET | `/api/v1/buyer-requests/<request_id>/matches` |
| POST | `/api/v1/offers` |
| POST | `/api/v1/offers/<offer_id>/accept` |
| POST | `/api/v1/offers/<offer_id>/counter` |
| POST | `/api/v1/offers/<offer_id>/reject` |
| POST | `/api/v1/offers/<offer_id>/withdraw` |
| GET | `/api/v1/offers/mine` |

## Orders & delivery

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/delivery-requests` |
| POST | `/api/v1/delivery-requests` |
| GET | `/api/v1/delivery-requests/<request_id>/quotes` |
| POST | `/api/v1/delivery-requests/<request_id>/quotes` |
| GET | `/api/v1/orders` |
| GET | `/api/v1/orders/<order_id>` |
| POST | `/api/v1/orders/<order_id>/cancel` |
| POST | `/api/v1/orders/<order_id>/payments` |
| GET | `/api/v1/orders/<order_id>/reviews` |
| POST | `/api/v1/orders/<order_id>/reviews` |
| POST | `/api/v1/orders/<order_id>/transition` |
| POST | `/api/v1/orders/draft` |

## Payments & wallet

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/admin/withdrawals` |
| POST | `/api/v1/admin/withdrawals/<withdrawal_id>` |
| GET | `/api/v1/payments` |
| POST | `/api/v1/payments/webhook/<provider>` |
| GET | `/api/v1/wallet` |
| GET | `/api/v1/wallet/ledger` |
| GET | `/api/v1/wallet/withdrawals` |
| POST | `/api/v1/wallet/withdrawals` |

## Messaging

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/conversations` |
| POST | `/api/v1/conversations` |
| GET | `/api/v1/conversations/<conversation_id>` |
| POST | `/api/v1/conversations/<conversation_id>/disappearing` |
| GET | `/api/v1/conversations/<conversation_id>/messages` |
| POST | `/api/v1/conversations/<conversation_id>/messages` |
| POST | `/api/v1/conversations/<conversation_id>/mute` |
| POST | `/api/v1/conversations/<conversation_id>/pin/<message_id>` |
| GET | `/api/v1/conversations/<conversation_id>/pinned` |
| POST | `/api/v1/conversations/<conversation_id>/read` |
| POST | `/api/v1/conversations/<conversation_id>/typing` |
| PATCH | `/api/v1/messages/<message_id>` |
| POST | `/api/v1/messages/<message_id>/delete-for-everyone` |
| POST | `/api/v1/messages/<message_id>/delete-for-me` |
| POST | `/api/v1/messages/<message_id>/react` |
| POST | `/api/v1/messages/forward` |
| POST | `/api/v1/messages/save` |
| GET | `/api/v1/messages/saved` |
| GET | `/api/v1/messages/search` |

## Groups

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/communities/<community_id>/groups` |
| GET | `/api/v1/groups` |
| POST | `/api/v1/groups` |
| GET | `/api/v1/groups/<group_id>` |
| POST | `/api/v1/groups/<group_id>/announcements` |
| GET | `/api/v1/groups/<group_id>/documents` |
| POST | `/api/v1/groups/<group_id>/documents` |
| POST | `/api/v1/groups/<group_id>/invites` |
| DELETE | `/api/v1/groups/<group_id>/invites/<code>` |
| POST | `/api/v1/groups/<group_id>/join` |
| GET | `/api/v1/groups/<group_id>/join-requests` |
| POST | `/api/v1/groups/<group_id>/join-requests/<request_id>` |
| GET | `/api/v1/groups/<group_id>/knowledge` |
| POST | `/api/v1/groups/<group_id>/knowledge` |
| POST | `/api/v1/groups/<group_id>/members` |
| DELETE | `/api/v1/groups/<group_id>/members/<user_id>` |
| POST | `/api/v1/groups/<group_id>/members/<user_id>/ban` |

## Communities & channels

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/channels` |
| POST | `/api/v1/channels` |
| POST | `/api/v1/channels/<channel_id>/follow` |
| GET | `/api/v1/channels/<channel_id>/posts` |
| POST | `/api/v1/channels/<channel_id>/posts` |
| POST | `/api/v1/channels/<channel_id>/unfollow` |
| GET | `/api/v1/communities` |
| POST | `/api/v1/communities` |
| GET | `/api/v1/communities/<community_id>` |
| POST | `/api/v1/communities/<community_id>/announcements` |
| POST | `/api/v1/communities/<community_id>/join` |
| GET | `/api/v1/communities/recommended` |

## Status, polls & events

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/events` |
| POST | `/api/v1/events` |
| POST | `/api/v1/events/<event_id>/rsvp` |
| POST | `/api/v1/events/dispatch-reminders` |
| POST | `/api/v1/polls` |
| POST | `/api/v1/polls/<poll_id>/close` |
| GET | `/api/v1/polls/<poll_id>/results` |
| POST | `/api/v1/polls/<poll_id>/vote` |
| GET | `/api/v1/statuses` |
| POST | `/api/v1/statuses` |
| POST | `/api/v1/statuses/<status_id>/react` |
| POST | `/api/v1/statuses/<status_id>/view` |
| POST | `/api/v1/statuses/expire` |
| POST | `/api/v1/statuses/from-listing` |

## Calls

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/calls` |
| POST | `/api/v1/calls/<call_id>/answer` |
| POST | `/api/v1/calls/<call_id>/end` |
| POST | `/api/v1/calls/<call_id>/signal` |

## Market intelligence

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/admin/alerts` |
| POST | `/api/v1/admin/alerts/<alert_id>/resolve` |
| GET | `/api/v1/advisory/articles` |
| GET | `/api/v1/advisory/articles/<article_id>` |
| GET | `/api/v1/advisory/questions` |
| POST | `/api/v1/advisory/questions` |
| POST | `/api/v1/advisory/voice-report` |
| POST | `/api/v1/ai/analyze-crop-image` |
| POST | `/api/v1/ai/chat` |
| POST | `/api/v1/ai/extract-listing` |
| POST | `/api/v1/ai/summarize-messages` |
| POST | `/api/v1/ai/translate` |
| GET | `/api/v1/market-prices` |
| POST | `/api/v1/market-prices/ingest` |
| GET | `/api/v1/market-prices/trend` |
| GET | `/api/v1/weather` |

## Notifications & account

| Method | Path |
| ------ | ---- |
| POST | `/api/v1/admin/disputes/<dispute_id>` |
| GET | `/api/v1/admin/disputes/<dispute_id>/evidence` |
| POST | `/api/v1/devices` |
| GET | `/api/v1/disputes` |
| POST | `/api/v1/disputes` |
| POST | `/api/v1/disputes/<dispute_id>/evidence` |
| GET | `/api/v1/notifications` |
| POST | `/api/v1/notifications/<notification_id>/read` |
| GET | `/api/v1/notifications/preferences` |
| PUT | `/api/v1/notifications/preferences` |
| POST | `/api/v1/notifications/read-all` |
| GET | `/api/v1/reputation/me` |

## Opportunities

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/opportunities` |

## Search / sync / uploads / platform

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/favorites` |
| POST | `/api/v1/favorites` |
| DELETE | `/api/v1/favorites/<listing_id>` |
| GET | `/api/v1/saved-searches` |
| POST | `/api/v1/saved-searches` |
| DELETE | `/api/v1/saved-searches/<search_id>` |
| GET | `/api/v1/search` |
| GET | `/api/v1/sync/pull` |
| POST | `/api/v1/sync/push` |
| POST | `/api/v1/uploads/<category>` |

## Admin

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/admin/analytics/overview` |
| GET | `/api/v1/admin/audit-logs` |
| GET | `/api/v1/admin/deletion-requests` |
| GET | `/api/v1/admin/export-requests` |
| GET | `/api/v1/admin/fees` |
| PUT | `/api/v1/admin/fees` |
| GET | `/api/v1/admin/risk-events` |

## Other

| Method | Path |
| ------ | ---- |
| GET | `/api/v1/categories` |
| GET | `/api/v1/deliveries` |
| POST | `/api/v1/deliveries/<delivery_id>/advance` |
| GET | `/api/v1/emergency-alerts` |
| POST | `/api/v1/quotes/<quote_id>/accept` |
| POST | `/api/v1/recommendations/suppliers` |
| GET | `/api/v1/vehicles` |
| POST | `/api/v1/vehicles` |
| GET | `/api/v1/voice-rooms` |
| POST | `/api/v1/voice-rooms` |
| POST | `/api/v1/voice-rooms/<room_id>/end` |
| POST | `/api/v1/voice-rooms/<room_id>/join` |
| POST | `/api/v1/voice-rooms/<room_id>/speaker-decision` |
| POST | `/api/v1/voice-rooms/<room_id>/speaker-request` |
