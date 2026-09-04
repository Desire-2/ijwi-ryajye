"""URL registry: maps every route onto the /api/v1 namespace."""


def register_api(app):
    from app.api import (
        account,
        admin,
        users as users_api,
        calls,
        commerce,
        dashboard,
        farms,
        groups,
        intelligence,
        marketplace,
        messaging,
        opportunities,
        platform,
        posts,
        social_api,
        social_features,
        trade,
    )
    from app.api.auth import register_auth_routes

    add = app.add_url_rule

    # ---- Auth ----
    add("/api/v1/auth/register", view_func=register_auth_routes["register"], methods=["POST"])
    add("/api/v1/auth/login", view_func=register_auth_routes["login"], methods=["POST"])
    add("/api/v1/auth/otp/request", view_func=register_auth_routes["request_otp"], methods=["POST"])
    add("/api/v1/auth/otp/verify", view_func=register_auth_routes["verify_otp"], methods=["POST"])
    add("/api/v1/auth/refresh", view_func=register_auth_routes["refresh_token_exchange"], methods=["POST"])
    add("/api/v1/auth/logout", view_func=register_auth_routes["logout"], methods=["POST"])

    # ---- Users / account ----
    add("/api/v1/users/farmers", view_func=users_api.list_farmers, methods=["GET"])
    add("/api/v1/users/me", view_func=users_api.me, methods=["GET"])
    add("/api/v1/users/me", view_func=users_api.patch_me, methods=["PATCH"])
    add("/api/v1/users/me/export", view_func=users_api.export_my_data, methods=["GET"])
    add("/api/v1/users/me/deletion-request", view_func=users_api.request_account_deletion, methods=["POST"])
    add("/api/v1/users/<farmer_id>", view_func=users_api.get_farmer, methods=["GET"])

    # ---- Farms ----
    add("/api/v1/farms", view_func=farms.create_farm, methods=["POST"])
    add("/api/v1/farms", view_func=farms.list_farms, methods=["GET"])
    add("/api/v1/farms/<farm_id>", view_func=farms.get_farm, methods=["GET"])
    add("/api/v1/farms/<farm_id>", view_func=farms.patch_farm, methods=["PATCH"])
    add("/api/v1/farms/<farm_id>", view_func=farms.delete_farm, methods=["DELETE"])
    add("/api/v1/farms/<farm_id>/crops", view_func=farms.add_crop, methods=["POST"])
    add("/api/v1/farms/<farm_id>/livestock", view_func=farms.add_livestock, methods=["POST"])
    add("/api/v1/crops/<crop_id>/production-records", view_func=farms.record_production, methods=["POST"])
    add("/api/v1/farms/<farm_id>/expenses", view_func=farms.record_expense, methods=["POST"])
    add("/api/v1/farms/<farm_id>/plans", view_func=farms.create_plan, methods=["POST"])
    add("/api/v1/farms/<farm_id>/business-records", view_func=farms.add_business_record, methods=["POST"])
    add("/api/v1/farms/<farm_id>/business-records", view_func=farms.business_records, methods=["GET"])

    # ---- Catalog & marketplace ----
    add("/api/v1/products", view_func=intelligence.list_products_catalog, methods=["GET"])
    add("/api/v1/categories", view_func=marketplace.list_categories, methods=["GET"])
    add("/api/v1/units", view_func=marketplace.list_units, methods=["GET"])
    add("/api/v1/listings", view_func=marketplace.create_listing, methods=["POST"])
    add("/api/v1/listings", view_func=marketplace.list_listings, methods=["GET"])
    add("/api/v1/listings/mine", view_func=marketplace.my_listings, methods=["GET"])
    add("/api/v1/listings/<listing_id>", view_func=marketplace.get_listing, methods=["GET"])
    add("/api/v1/listings/<listing_id>", view_func=marketplace.patch_listing, methods=["PATCH"])
    add("/api/v1/listings/<listing_id>/publish", view_func=marketplace.publish_listing, methods=["POST"])
    add("/api/v1/listings/<listing_id>/media", view_func=marketplace.add_listing_media, methods=["POST"])
    add("/api/v1/listings/<listing_id>/close", view_func=marketplace.close_listing, methods=["POST"])
    add("/api/v1/listings/<listing_id>/price-advice", view_func=marketplace.listing_price_advisor, methods=["GET"])
    add("/api/v1/price-advice", view_func=marketplace.listing_price_advisor, methods=["GET"])
    add("/api/v1/buyer-requests", view_func=marketplace.create_buyer_request, methods=["POST"])
    add("/api/v1/buyer-requests", view_func=marketplace.list_buyer_requests, methods=["GET"])
    add("/api/v1/buyer-requests/<request_id>/matches", view_func=opportunities.buyer_request_matches, methods=["GET"])

    # ---- Offers / bids ----
    add("/api/v1/offers", view_func=trade.create_offer, methods=["POST"])
    add("/api/v1/offers/mine", view_func=trade.list_my_offers, methods=["GET"])
    add("/api/v1/offers/<offer_id>/counter", view_func=trade.counter_offer, methods=["POST"])
    add("/api/v1/offers/<offer_id>/accept", view_func=trade.accept_offer, methods=["POST"])
    add("/api/v1/offers/<offer_id>/reject", view_func=trade.reject_offer, methods=["POST"])
    add("/api/v1/offers/<offer_id>/withdraw", view_func=trade.withdraw_offer, methods=["POST"])
    add("/api/v1/listings/<listing_id>/offers", view_func=trade.list_listing_offers, methods=["GET"])
    add("/api/v1/bids", view_func=trade.place_bid, methods=["POST"])
    add("/api/v1/bids/<bid_id>/retract", view_func=trade.retract_bid, methods=["POST"])
    add("/api/v1/bids/<bid_id>/accept", view_func=trade.accept_bid, methods=["POST"])
    add("/api/v1/listings/<listing_id>/bids", view_func=trade.list_bids, methods=["GET"])
    add("/api/v1/listings/<listing_id>/accept-winning-bid", view_func=trade.accept_winning_bid, methods=["POST"])

    # ---- Orders ----
    add("/api/v1/orders/draft", view_func=trade.create_order_draft, methods=["POST"])
    add("/api/v1/orders", view_func=trade.list_orders, methods=["GET"])
    add("/api/v1/orders/<order_id>", view_func=trade.get_order, methods=["GET"])
    add("/api/v1/orders/<order_id>/transition", view_func=trade.transition_order, methods=["POST"])
    add("/api/v1/orders/<order_id>/cancel", view_func=trade.cancel_order, methods=["POST"])

    # ---- Payments / wallet ----
    add("/api/v1/orders/<order_id>/payments", view_func=commerce.initiate_payment, methods=["POST"])
    add("/api/v1/payments/webhook/<provider>", view_func=commerce.payment_webhook, methods=["POST"])
    add("/api/v1/payments", view_func=commerce.list_my_payments, methods=["GET"])
    add("/api/v1/wallet", view_func=commerce.wallet_summary, methods=["GET"])
    add("/api/v1/wallet/ledger", view_func=commerce.wallet_ledger, methods=["GET"])
    add("/api/v1/wallet/withdrawals", view_func=commerce.request_withdrawal, methods=["POST"])
    add("/api/v1/wallet/withdrawals", view_func=commerce.list_withdrawals, methods=["GET"])

    # ---- Logistics ----
    add("/api/v1/delivery-requests", view_func=commerce.create_delivery_request, methods=["POST"])
    add("/api/v1/delivery-requests", view_func=commerce.list_delivery_requests, methods=["GET"])
    add("/api/v1/delivery-requests/<request_id>/quotes", view_func=commerce.submit_quote, methods=["POST"])
    add("/api/v1/delivery-requests/<request_id>/quotes", view_func=commerce.list_quotes, methods=["GET"])
    add("/api/v1/quotes/<quote_id>/accept", view_func=commerce.accept_quote, methods=["POST"])
    add("/api/v1/deliveries/<delivery_id>/advance", view_func=commerce.advance_delivery, methods=["POST"])
    add("/api/v1/deliveries", view_func=commerce.my_deliveries, methods=["GET"])
    add("/api/v1/vehicles", view_func=commerce.register_vehicle, methods=["POST"])
    add("/api/v1/vehicles", view_func=commerce.my_vehicles, methods=["GET"])

    # ---- Messaging ----
    add("/api/v1/conversations", view_func=messaging.list_conversations, methods=["GET"])
    add("/api/v1/conversations", view_func=messaging.start_conversation, methods=["POST"])
    add("/api/v1/conversations/<conversation_id>", view_func=messaging.get_conversation, methods=["GET"])
    add("/api/v1/conversations/<conversation_id>/messages", view_func=messaging.send_message, methods=["POST"])
    add("/api/v1/conversations/<conversation_id>/messages", view_func=messaging.list_messages, methods=["GET"])
    add("/api/v1/conversations/<conversation_id>/read", view_func=messaging.mark_read, methods=["POST"])
    add("/api/v1/messages/<message_id>/react", view_func=messaging.react, methods=["POST"])
    add("/api/v1/messages/<message_id>", view_func=messaging.edit_message, methods=["PATCH"])
    add("/api/v1/messages/<message_id>/delete-for-everyone", view_func=messaging.delete_message_for_everyone, methods=["POST"])
    add("/api/v1/messages/<message_id>/delete-for-me", view_func=messaging.delete_message_for_me, methods=["POST"])
    add("/api/v1/messages/forward", view_func=messaging.forward_messages, methods=["POST"])
    add("/api/v1/messages/save", view_func=messaging.save_message, methods=["POST"])
    add("/api/v1/messages/saved", view_func=messaging.list_saved, methods=["GET"])
    add("/api/v1/messages/search", view_func=messaging.search_messages, methods=["GET"])
    add("/api/v1/conversations/<conversation_id>/pin/<message_id>", view_func=messaging.pin_message, methods=["POST"])
    add("/api/v1/conversations/<conversation_id>/pinned", view_func=messaging.pinned_messages, methods=["GET"])
    add("/api/v1/conversations/<conversation_id>/typing", view_func=messaging.typing, methods=["POST"])
    add("/api/v1/conversations/<conversation_id>/disappearing", view_func=messaging.set_disappearing, methods=["POST"])
    add("/api/v1/conversations/<conversation_id>/mute", view_func=messaging.mute_conversation, methods=["POST"])

    # ---- Groups ----
    add("/api/v1/groups", view_func=groups.create_group, methods=["POST"])
    add("/api/v1/groups", view_func=groups.list_groups, methods=["GET"])
    add("/api/v1/groups/<group_id>", view_func=groups.get_group, methods=["GET"])
    add("/api/v1/groups/<group_id>/members", view_func=groups.add_members, methods=["POST"])
    add("/api/v1/groups/<group_id>/members/<user_id>", view_func=groups.remove_member, methods=["DELETE"])
    add("/api/v1/groups/<group_id>/members/<user_id>/ban", view_func=groups.ban_member, methods=["POST"])
    add("/api/v1/groups/<group_id>/join", view_func=groups.join_group, methods=["POST"])
    add("/api/v1/groups/<group_id>/join-requests", view_func=groups.list_join_requests, methods=["GET"])
    add("/api/v1/groups/<group_id>/join-requests/<request_id>", view_func=groups.review_join_request, methods=["POST"])
    add("/api/v1/groups/<group_id>/invites", view_func=groups.create_invite, methods=["POST"])
    add("/api/v1/groups/<group_id>/invites/<code>", view_func=groups.revoke_invite, methods=["DELETE"])
    add("/api/v1/groups/<group_id>/announcements", view_func=groups.announce, methods=["POST"])
    add("/api/v1/groups/<group_id>/knowledge", view_func=groups.knowledge_items, methods=["GET"])
    add("/api/v1/groups/<group_id>/knowledge", view_func=groups.add_knowledge, methods=["POST"])
    add("/api/v1/groups/<group_id>/documents", view_func=groups.documents, methods=["GET"])
    add("/api/v1/groups/<group_id>/documents", view_func=groups.upload_document, methods=["POST"])

    # ---- Communities / channels ----
    add("/api/v1/communities", view_func=social_api.list_communities, methods=["GET"])
    add("/api/v1/communities", view_func=social_api.create_community, methods=["POST"])
    add("/api/v1/communities/recommended", view_func=social_api.recommended_communities, methods=["GET"])
    add("/api/v1/communities/<community_id>", view_func=social_api.community_detail, methods=["GET"])
    add("/api/v1/communities/<community_id>/join", view_func=social_api.join_community, methods=["POST"])
    add("/api/v1/communities/<community_id>/groups", view_func=social_api.attach_group_to_community, methods=["POST"])
    add("/api/v1/communities/<community_id>/announcements", view_func=social_api.community_announce, methods=["POST"])
    add("/api/v1/channels", view_func=social_api.list_channels, methods=["GET"])
    add("/api/v1/channels", view_func=social_api.create_channel, methods=["POST"])
    add("/api/v1/channels/<channel_id>/follow", view_func=social_api.follow_channel, methods=["POST"])
    add("/api/v1/channels/<channel_id>/unfollow", view_func=social_api.unfollow_channel, methods=["POST"])
    add("/api/v1/channels/<channel_id>/posts", view_func=social_api.channel_posts, methods=["GET"])
    add("/api/v1/channels/<channel_id>/posts", view_func=social_api.create_channel_post, methods=["POST"])

    # ---- Posts / comments / reactions ----
    add("/api/v1/posts", view_func=posts.create_post, methods=["POST"])
    add("/api/v1/posts", view_func=posts.list_posts, methods=["GET"])
    add("/api/v1/posts/saved", view_func=posts.saved_posts, methods=["GET"])
    add("/api/v1/posts/<post_id>", view_func=posts.post_detail, methods=["GET"])
    add("/api/v1/posts/<post_id>", view_func=posts.patch_post, methods=["PATCH"])
    add("/api/v1/posts/<post_id>", view_func=posts.delete_post, methods=["DELETE"])
    add("/api/v1/posts/<post_id>/pin", view_func=posts.pin_post, methods=["POST"])
    add("/api/v1/posts/<post_id>/best-answer", view_func=posts.mark_best_answer, methods=["POST"])
    add("/api/v1/posts/<post_id>/comments", view_func=posts.list_comments, methods=["GET"])
    add("/api/v1/posts/<post_id>/comments", view_func=posts.create_comment, methods=["POST"])
    add("/api/v1/posts/<post_id>/react", view_func=posts.react_post, methods=["POST"])
    add("/api/v1/posts/<post_id>/save", view_func=posts.save_post, methods=["POST"])
    add("/api/v1/comments/<comment_id>/replies", view_func=posts.list_replies, methods=["GET"])
    add("/api/v1/comments/<comment_id>", view_func=posts.delete_comment, methods=["DELETE"])
    add("/api/v1/comments/<comment_id>/react", view_func=posts.react_comment, methods=["POST"])

    # ---- Follows / reports ----
    add("/api/v1/users/<user_id>/follow", view_func=posts.follow_user, methods=["POST"])
    add("/api/v1/users/<user_id>/unfollow", view_func=posts.unfollow_user, methods=["POST"])
    add("/api/v1/reports", view_func=posts.report_content, methods=["POST"])

    # ---- Status / polls / events ----
    add("/api/v1/statuses", view_func=social_features.create_status, methods=["POST"])
    add("/api/v1/statuses", view_func=social_features.list_statuses, methods=["GET"])
    add("/api/v1/statuses/<status_id>/view", view_func=social_features.view_status, methods=["POST"])
    add("/api/v1/statuses/<status_id>/react", view_func=social_features.react_status, methods=["POST"])
    add("/api/v1/statuses/from-listing", view_func=social_features.convert_listing_to_status, methods=["POST"])
    add("/api/v1/statuses/expire", view_func=social_features.expire_statuses, methods=["POST"])
    add("/api/v1/polls", view_func=social_features.create_poll, methods=["POST"])
    add("/api/v1/polls/<poll_id>/vote", view_func=social_features.vote_poll, methods=["POST"])
    add("/api/v1/polls/<poll_id>/close", view_func=social_features.close_poll, methods=["POST"])
    add("/api/v1/polls/<poll_id>/results", view_func=social_features.poll_results, methods=["GET"])
    add("/api/v1/events", view_func=social_features.create_event, methods=["POST"])
    add("/api/v1/events", view_func=social_features.list_events, methods=["GET"])
    add("/api/v1/events/<event_id>/rsvp", view_func=social_features.rsvp_event, methods=["POST"])
    add("/api/v1/events/dispatch-reminders", view_func=social_features.dispatch_reminders, methods=["POST"])

    # ---- Calls / voice rooms ----
    add("/api/v1/calls", view_func=calls.start_call, methods=["POST"])
    add("/api/v1/calls/<call_id>/answer", view_func=calls.answer_call, methods=["POST"])
    add("/api/v1/calls/<call_id>/end", view_func=calls.end_call, methods=["POST"])
    add("/api/v1/calls/<call_id>/signal", view_func=calls.relay_signal, methods=["POST"])
    add("/api/v1/voice-rooms", view_func=calls.create_voice_room, methods=["POST"])
    add("/api/v1/voice-rooms", view_func=calls.list_voice_rooms, methods=["GET"])
    add("/api/v1/voice-rooms/<room_id>/join", view_func=calls.join_voice_room, methods=["POST"])
    add("/api/v1/voice-rooms/<room_id>/speaker-request", view_func=calls.request_speaker, methods=["POST"])
    add("/api/v1/voice-rooms/<room_id>/speaker-decision", view_func=calls.decide_speaker, methods=["POST"])
    add("/api/v1/voice-rooms/<room_id>/end", view_func=calls.end_voice_room, methods=["POST"])

    # ---- Market intelligence ----
    add("/api/v1/market-prices", view_func=intelligence.list_market_prices, methods=["GET"])
    add("/api/v1/market-prices/trend", view_func=intelligence.price_trend, methods=["GET"])
    add("/api/v1/weather", view_func=intelligence.weather, methods=["GET"])
    add("/api/v1/market-prices/ingest", view_func=intelligence.ingest_price, methods=["POST"])
    add("/api/v1/advisory/questions", view_func=intelligence.ask_expert, methods=["POST"])
    add("/api/v1/advisory/questions", view_func=intelligence.my_advisory_questions, methods=["GET"])
    add("/api/v1/advisory/articles", view_func=intelligence.advisory_articles, methods=["GET"])
    add("/api/v1/advisory/articles/<article_id>", view_func=intelligence.article_detail, methods=["GET"])
    add("/api/v1/advisory/voice-report", view_func=intelligence.report_voice, methods=["POST"])
    add("/api/v1/emergency-alerts", view_func=intelligence.emergency_alerts, methods=["GET"])
    add("/api/v1/opportunities", view_func=opportunities.farmer_opportunities, methods=["GET"])
    add("/api/v1/recommendations/suppliers", view_func=opportunities.supplier_recommendations, methods=["POST"])

    # ---- AI assistant ----
    add("/api/v1/ai/chat", view_func=intelligence.ai_assistant_chat, methods=["POST"])
    add("/api/v1/ai/extract-listing", view_func=intelligence.ai_extract_listing, methods=["POST"])
    add("/api/v1/ai/translate", view_func=intelligence.ai_translate, methods=["POST"])
    add("/api/v1/ai/analyze-crop-image", view_func=intelligence.ai_analyze_crop_image, methods=["POST"])
    add("/api/v1/ai/summarize-messages", view_func=intelligence.ai_summarize_messages, methods=["POST"])

    # ---- Notifications / verification / reviews / disputes ----
    add("/api/v1/notifications", view_func=account.list_notifications, methods=["GET"])
    add("/api/v1/notifications/read-all", view_func=account.mark_all_notifications_read, methods=["POST"])
    add("/api/v1/notifications/<notification_id>/read", view_func=account.mark_notification_read, methods=["POST"])
    add("/api/v1/notifications/preferences", view_func=account.notification_preferences, methods=["GET"])
    add("/api/v1/notifications/preferences", view_func=account.update_notification_preferences, methods=["PUT"])
    add("/api/v1/devices", view_func=account.register_device_token, methods=["POST"])
    add("/api/v1/verifications", view_func=account.submit_verification, methods=["POST"])
    add("/api/v1/verifications/mine", view_func=account.my_verifications, methods=["GET"])
    add("/api/v1/orders/<order_id>/reviews", view_func=account.create_review, methods=["POST"])
    add("/api/v1/orders/<order_id>/reviews", view_func=account.order_reviews, methods=["GET"])
    add("/api/v1/reputation/me", view_func=account.reputation_summary, methods=["GET"])
    add("/api/v1/reputation/users/<user_id>", view_func=account.user_reputation, methods=["GET"])
    add("/api/v1/users/<user_id>/reviews", view_func=account.user_reviews, methods=["GET"])
    add("/api/v1/disputes", view_func=account.open_dispute, methods=["POST"])
    add("/api/v1/disputes", view_func=account.my_disputes, methods=["GET"])
    add("/api/v1/disputes/<dispute_id>/evidence", view_func=account.add_dispute_evidence, methods=["POST"])

    # ---- Search / favorites / sync / uploads ----
    add("/api/v1/search", view_func=platform.global_search, methods=["GET"])
    add("/api/v1/favorites", view_func=platform.add_favorite, methods=["POST"])
    add("/api/v1/favorites", view_func=platform.list_favorites, methods=["GET"])
    add("/api/v1/favorites/<listing_id>", view_func=platform.remove_favorite, methods=["DELETE"])
    add("/api/v1/saved-searches", view_func=platform.create_saved_search, methods=["POST"])
    add("/api/v1/saved-searches", view_func=platform.list_saved_searches, methods=["GET"])
    add("/api/v1/saved-searches/<search_id>", view_func=platform.delete_saved_search, methods=["DELETE"])
    add("/api/v1/sync/push", view_func=platform.sync_push, methods=["POST"])
    add("/api/v1/sync/pull", view_func=platform.sync_pull, methods=["GET"])
    add("/api/v1/uploads/<category>", view_func=platform.upload_file, methods=["POST"])

    # ---- Seller dashboard ----
    add("/api/v1/seller/dashboard", view_func=dashboard.seller_dashboard, methods=["GET"])

    # ---- Admin ----
    add("/api/v1/admin/users", view_func=admin.list_users, methods=["GET"])
    add("/api/v1/admin/users/<user_id>/suspend", view_func=admin.suspend_user, methods=["POST"])
    add("/api/v1/admin/users/<user_id>/unsuspend", view_func=admin.unsuspend_user, methods=["POST"])
    add("/api/v1/admin/fees", view_func=admin.list_fees, methods=["GET"])
    add("/api/v1/admin/fees", view_func=admin.set_fee, methods=["PUT"])
    add("/api/v1/admin/verifications", view_func=admin.list_verifications, methods=["GET"])
    add("/api/v1/admin/verifications/<verification_id>", view_func=admin.review_verification, methods=["POST"])
    add("/api/v1/admin/disputes/<dispute_id>", view_func=admin.review_dispute, methods=["POST"])
    add("/api/v1/admin/disputes/<dispute_id>/evidence", view_func=admin.dispute_evidence, methods=["GET"])
    add("/api/v1/admin/withdrawals", view_func=admin.pending_withdrawals, methods=["GET"])
    add("/api/v1/admin/withdrawals/<withdrawal_id>", view_func=admin.process_withdrawal, methods=["POST"])
    add("/api/v1/admin/alerts", view_func=admin.create_emergency_alert, methods=["POST"])
    add("/api/v1/admin/alerts/<alert_id>/resolve", view_func=admin.resolve_alert, methods=["POST"])
    add("/api/v1/admin/risk-events", view_func=admin.risk_events, methods=["GET"])
    add("/api/v1/admin/audit-logs", view_func=admin.audit_logs, methods=["GET"])
    add("/api/v1/admin/export-requests", view_func=admin.export_requests, methods=["GET"])
    add("/api/v1/admin/deletion-requests", view_func=admin.deletion_requests, methods=["GET"])
    add("/api/v1/admin/analytics/overview", view_func=admin.analytics_overview, methods=["GET"])

    # ---- Health ----
    add("/health", view_func=platform.health, methods=["GET"])
    add("/ready", view_func=platform.ready, methods=["GET"])
