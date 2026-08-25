from app.models.identity import FarmerProfile, User, Verification
from app.models.marketplace import Listing


def user_private(user):
    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "phone": user.phone if user.visibility_phone else None,
        "email": user.email,
        "country_code": user.country_code,
        "region": user.region,
        "district": user.district if user.visibility_location_exact else None,
        "languages": (user.languages or "").split(","),
        "primary_role": user.primary_role,
        "roles": sorted(user.role_codes()),
        "phone_verified": bool(user.phone_verified_at),
        "data_saver": user.data_saver,
        "transcription_opt_in": user.transcription_opt_in,
        "created_at": user.created_at.isoformat(),
    }


def farmer_card(user, profile=None):
    profile = profile or getattr(user, "farmer_profile", None)
    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "region": user.region,
        "district": None if not user.visibility_location_exact else user.district,
        "main_crops": [c for c in (profile.main_crops or "").split(",") if c] if profile else [],
        "years_experience": profile.years_experience if profile else 0,
        "rating_avg": float(profile.rating_avg or 0) if profile else 0,
        "completed_transactions": profile.completed_transactions if profile else 0,
        "reputation_tier": profile.reputation_tier if profile else "NEW_MEMBER",
    }


def listing_json(listing, seller=None):
    product = listing.product
    return {
        "id": listing.id,
        "title": listing.title,
        "listing_type": listing.listing_type,
        "state": listing.state,
        "product": {"id": product.id, "name": product.name, "slug": product.slug, "emoji": product.emoji},
        "variety": listing.variety,
        "quantity_value": float(listing.quantity_value),
        "available_quantity": float(listing.available_quantity),
        "sold_quantity": float(listing.sold_quantity or 0),
        "unit_code": listing.unit_code,
        "quality_grade": listing.quality_grade,
        "production_method": listing.production_method,
        "certification": listing.certification,
        "location_region": listing.location_region,
        "location_district": listing.location_district,
        "price_minor": listing.price_minor,
        "currency_code": listing.currency_code,
        "price_type": listing.price_type,
        "negotiable": bool(listing.negotiable),
        "minimum_order_value": float(listing.minimum_order_value or 0),
        "maximum_order_value": float(listing.maximum_order_value) if listing.maximum_order_value else None,
        "expected_harvest_date": str(listing.expected_harvest_date) if listing.expected_harvest_date else None,
        "delivery_options": (listing.delivery_options or "").split(","),
        "promoted_until": listing.promoted_until.isoformat() if listing.promoted_until else None,
        "auction_end_at": listing.auction_end_at.isoformat() if listing.auction_end_at else None,
        "reserve_price_minor": listing.reserve_price_minor,
        "seller": farmer_card(seller) if seller is not None else {"id": listing.seller_id},
        "expires_at": listing.expires_at.isoformat() if listing.expires_at else None,
        "created_at": listing.created_at.isoformat(),
    }


def order_json(order, viewer_id=None):
    data = {
        "id": order.id,
        "order_number": order.order_number,
        "state": order.state,
        "buyer_id": order.buyer_id,
        "seller_id": order.seller_id,
        "quantity_value": float(order.quantity_value),
        "unit_code": order.unit_code,
        "unit_price_minor": order.unit_price_minor,
        "total_amount_minor": order.total_amount_minor,
        "platform_fee_minor": order.platform_fee_minor,
        "currency_code": order.currency_code,
        "delivery_option": order.delivery_option,
        "payment_terms": order.payment_terms,
        "has_contract": bool(order.contract_id),
        "delivery_id": order.delivery_id,
        "items": [
            {
                "product_id": i.product_id,
                "description": i.description,
                "quantity_value": float(i.quantity_value),
                "unit_code": i.unit_code,
                "line_total_minor": i.line_total_minor,
            }
            for i in order.items
        ],
        "cancelled_reason": order.cancelled_reason,
        "completed_at": order.completed_at.isoformat() if order.completed_at else None,
        "created_at": order.created_at.isoformat(),
    }
    if viewer_id in (order.buyer_id, order.seller_id):
        pass
    return data


def message_json(message):
    from app.services.messaging_service import _serialize

    return _serialize(message)


def conversation_json(conv, member=None):
    members = [
        {"user_id": m.user_id, "role": m.role, "last_read_sequence": m.last_read_sequence}
        for m in conv.members
        if m.left_at is None
    ]
    unread = 0
    if member is not None and conv.last_message_at:
        last_seq = conv.server_sequence
        unread = max(0, last_seq - member.last_read_sequence)
    return {
        "id": conv.id,
        "conversation_type": conv.conversation_type,
        "title": conv.title,
        "group_id": conv.group_id,
        "community_id": conv.community_id,
        "listing_id": conv.listing_id,
        "order_id": conv.order_id,
        "server_sequence": conv.server_sequence,
        "last_message_at": conv.last_message_at.isoformat() if conv.last_message_at else None,
        "disappearing_seconds": conv.disappearing_seconds,
        "members": members,
        "unread_count": unread,
    }


def group_json(group, my_role=None):
    return {
        "id": group.id,
        "name": group.name,
        "description": group.description,
        "group_type": group.group_type,
        "is_private": group.is_private,
        "require_approval": group.require_approval,
        "member_count": group.member_count,
        "community_id": group.community_id,
        "my_role": my_role,
        "invite_code": group.invite_code,
        "photo_key": group.photo_key,
        "created_at": group.created_at.isoformat(),
    }


def offer_json(offer):
    return {
        "id": offer.id,
        "listing_id": offer.listing_id,
        "buyer_request_id": offer.buyer_request_id,
        "parent_offer_id": offer.parent_offer_id,
        "buyer_id": offer.buyer_id,
        "seller_id": offer.seller_id,
        "state": offer.state,
        "quantity_value": float(offer.quantity_value),
        "unit_code": offer.unit_code,
        "price_minor": offer.price_minor,
        "currency_code": offer.currency_code,
        "delivery_option": offer.delivery_option,
        "payment_terms": offer.payment_terms,
        "message": offer.message,
        "expires_at": offer.expires_at.isoformat() if offer.expires_at else None,
        "created_at": offer.created_at.isoformat(),
    }


def bid_json(bid):
    return {
        "id": bid.id,
        "listing_id": bid.listing_id,
        "bidder_id": bid.bidder_id,
        "amount_minor": bid.amount_minor,
        "quantity_value": float(bid.quantity_value),
        "unit_code": bid.unit_code,
        "currency_code": bid.currency_code,
        "state": bid.state,
        "is_winning": bid.is_winning,
        "placed_at": bid.placed_at.isoformat(),
    }


def buyer_request_json(br):
    p = br.product
    return {
        "id": br.id,
        "title": br.title,
        "description": br.description,
        "state": br.state,
        "product": {"id": p.id, "name": p.name, "slug": p.slug},
        "quantity_value": float(br.quantity_value),
        "unit_code": br.unit_code,
        "quality_grade": br.quality_grade,
        "destination_region": br.destination_region,
        "destination_district": br.destination_district,
        "required_by_date": str(br.required_by_date) if br.required_by_date else None,
        "budget_min_minor": br.budget_min_minor,
        "budget_max_minor": br.budget_max_minor,
        "currency_code": br.currency_code,
        "expires_at": br.expires_at.isoformat() if br.expires_at else None,
        "created_at": br.created_at.isoformat(),
    }
