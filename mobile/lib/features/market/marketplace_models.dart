/// Marketplace domain models mirroring `backend/app/api/serializers.py`.
///
/// Amounts are integer minor units (100 minor = 1 RWF). Only fields actually
/// returned by the backend are modelled — nothing is invented.
library;

class ProductSummary {
  ProductSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        slug = j['slug'] as String? ?? '',
        emoji = j['emoji'] as String? ?? '🌱',
        categoryName =
            (j['category'] as Map<String, dynamic>?)?['name'] as String?,
        categorySlug =
            (j['category'] as Map<String, dynamic>?)?['slug'] as String?,
        categoryIcon =
            (j['category'] as Map<String, dynamic>?)?['icon'] as String?,
        defaultUnit = j['default_unit'] as String? ?? 'kg';

  final String id;
  final String name;
  final String slug;
  final String emoji;
  final String defaultUnit;
  final String? categoryName;
  final String? categorySlug;
  final String? categoryIcon;
}

/// One row of GET /units — the backend-managed unit catalogue.
class UnitOption {
  UnitOption.fromJson(Map<String, dynamic> j)
      : code = j['code'] as String? ?? '',
        label = j['label'] as String? ?? '',
        dimension = j['dimension'] as String?;

  final String code;
  final String label;
  final String? dimension;
}

class Category {
  Category.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        slug = j['slug'] as String? ?? '',
        icon = j['icon'] as String? ?? '';

  final String id;
  final String name;
  final String slug;
  final String icon;
}

/// `farmer_card` payload from serializers.py.
class SellerCard {
  SellerCard.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        username = j['username'] as String? ?? '',
        fullName = j['full_name'] as String? ?? '',
        region = j['region'] as String?,
        district = j['district'] as String?,
        mainCrops = ((j['main_crops'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        yearsExperience = (j['years_experience'] as num?)?.toInt() ?? 0,
        ratingAvg = ((j['rating_avg'] as num?) ?? 0).toDouble(),
        ratingCount = (j['rating_count'] as num?)?.toInt() ?? 0,
        completedTransactions =
            (j['completed_transactions'] as num?)?.toInt() ?? 0,
        reputationTier = j['reputation_tier'] as String? ?? 'NEW_MEMBER';

  final String id;
  final String username;
  final String fullName;
  final String? region;
  final String? district;
  final List<String> mainCrops;
  final int yearsExperience;
  final double ratingAvg;
  final int ratingCount;
  final int completedTransactions;
  final String reputationTier;

  bool get isVerified =>
      completedTransactions > 0 || reputationTier != 'NEW_MEMBER';
}

/// `listing_json` payload.
class Listing {
  Listing.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        listingType = j['listing_type'] as String? ?? 'FIXED_PRICE',
        state = j['state'] as String? ?? 'ACTIVE',
        productId = (j['product'] as Map<String, dynamic>?)?['id'] as String?,
        productName =
            (j['product'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        productEmoji =
            (j['product'] as Map<String, dynamic>?)?['emoji'] as String? ??
                '🌱',
        description = j['description'] as String? ?? '',
        attributes =
            (j['attributes'] as Map<String, dynamic>?) ?? const {},
        variety = j['variety'] as String? ?? '',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        availableQuantity = (j['available_quantity'] as num?)?.toDouble() ?? 0,
        soldQuantity = (j['sold_quantity'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        qualityGrade = j['quality_grade'] as String? ?? 'UNGRADED',
        productionMethod = j['production_method'] as String?,
        certification = j['certification'] as String? ?? '',
        locationRegion = j['location_region'] as String?,
        locationDistrict = j['location_district'] as String?,
        priceMinor = (j['price_minor'] as num?)?.toInt(),
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        priceType = j['price_type'] as String? ?? 'PER_UNIT',
        negotiable = (j['negotiable'] as bool?) ?? false,
        minimumOrderValue = (j['minimum_order_value'] as num?)?.toDouble() ?? 0,
        maximumOrderValue = (j['maximum_order_value'] as num?)?.toDouble(),
        expectedHarvestDate = j['expected_harvest_date'] as String?,
        deliveryOptions = ((j['delivery_options'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        promotedUntil = j['promoted_until'] as String?,
        auctionEndAt = j['auction_end_at'] as String?,
        // `auctionEndAt` is intentionally mutable: auction anti-sniping can
        // extend the close server-side and realtime pushes the new end time.
        reservePriceMinor = (j['reserve_price_minor'] as num?)?.toInt(),
        expiresAt = j['expires_at'] as String?,
        createdAt = j['created_at'] as String?,
        sellerJson = j['seller'] as Map<String, dynamic>?;

  final String id;
  final String title;
  final String listingType;
  final String state;
  final String? productId;
  final String productName;
  final String productEmoji;
  final String description;
  final Map<String, dynamic> attributes;
  final String variety;
  final double quantityValue;
  final double availableQuantity;
  final double soldQuantity;
  final String unitCode;
  final String qualityGrade;
  final String? productionMethod;
  final String certification;
  final String? locationRegion;
  final String? locationDistrict;
  final int? priceMinor;
  final String currencyCode;
  final String priceType;
  final bool negotiable;
  final double minimumOrderValue;
  final double? maximumOrderValue;
  final String? expectedHarvestDate;
  final List<String> deliveryOptions;
  final String? promotedUntil;
  String? auctionEndAt;
  final int? reservePriceMinor;
  final String? expiresAt;
  final String? createdAt;
  final Map<String, dynamic>? sellerJson;

  late final SellerCard? seller = sellerJson == null ? null : SellerCard.fromJson(sellerJson!);

  bool get isAuction => listingType == 'AUCTION';
  bool get isNegotiable => negotiable || listingType == 'NEGOTIABLE';
  bool get isSoldOut => availableQuantity <= 0 || state == 'SOLD_OUT';
  bool get isActive => state == 'ACTIVE';

  String get availabilityLabel => switch (state) {
        'PAUSED' => 'Paused',
        'CLOSED' => 'Closed',
        'EXPIRED' => 'Expired',
        'SOLD_OUT' => 'Sold out',
        _ => isSoldOut ? 'Sold out' : 'Available',
      };

  String get locationLabel {
    if (locationRegion == null && locationDistrict == null) return '';
    return [locationDistrict, locationRegion].whereType<String>().join(', ');
  }
}

class ListingMedia {
  ListingMedia.fromJson(Map<String, dynamic> j)
      : type = j['type'] as String? ?? 'image',
        storageKey = j['storage_key'] as String? ?? '',
        caption = j['caption'] as String? ?? '';

  final String type;
  final String storageKey;
  final String caption;
}

class Offer {
  Offer.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        listingId = j['listing_id'] as String?,
        buyerRequestId = j['buyer_request_id'] as String?,
        parentOfferId = j['parent_offer_id'] as String?,
        buyerId = j['buyer_id'] as String?,
        sellerId = j['seller_id'] as String?,
        state = j['state'] as String? ?? 'PENDING',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        deliveryOption = j['delivery_option'] as String? ?? 'PICKUP',
        paymentTerms = j['payment_terms'] as String? ?? '',
        message = j['message'] as String? ?? '',
        expiresAt = j['expires_at'] as String?,
        createdAt = j['created_at'] as String?;

  final String id;
  final String? listingId;
  final String? buyerRequestId;
  final String? parentOfferId;
  final String? buyerId;
  final String? sellerId;
  final String state;
  final double quantityValue;
  final String unitCode;
  final int priceMinor;
  final String currencyCode;
  final String deliveryOption;
  final String paymentTerms;
  final String message;
  final String? expiresAt;
  final String? createdAt;

  bool get isPending => state == 'PENDING';
  bool get isActionable => isPending;
  int get totalMinor => (priceMinor * quantityValue).round();
}

class Bid {
  Bid.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        listingId = j['listing_id'] as String?,
        bidderId = j['bidder_id'] as String?,
        amountMinor = (j['amount_minor'] as num?)?.toInt() ?? 0,
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        state = j['state'] as String? ?? 'ACTIVE',
        isWinning = (j['is_winning'] as bool?) ?? false,
        placedAt = j['placed_at'] as String?;

  final String id;
  final String? listingId;
  final String? bidderId;
  final int amountMinor;
  final double quantityValue;
  final String unitCode;
  final String currencyCode;
  final String state;
  final bool isWinning;
  final String? placedAt;
}

class BuyerRequest {
  BuyerRequest.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        description = j['description'] as String? ?? '',
        state = j['state'] as String? ?? 'OPEN',
        productId = (j['product'] as Map<String, dynamic>?)?['id'] as String?,
        productName =
            (j['product'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        qualityGrade = j['quality_grade'] as String? ?? 'UNGRADED',
        destinationRegion = j['destination_region'] as String?,
        destinationDistrict = j['destination_district'] as String?,
        requiredByDate = j['required_by_date'] as String?,
        budgetMinMinor = (j['budget_min_minor'] as num?)?.toInt(),
        budgetMaxMinor = (j['budget_max_minor'] as num?)?.toInt(),
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        expiresAt = j['expires_at'] as String?,
        createdAt = j['created_at'] as String?;

  final String id;
  final String title;
  final String description;
  final String state;
  final String? productId;
  final String productName;
  final double quantityValue;
  final String unitCode;
  final String qualityGrade;
  final String? destinationRegion;
  final String? destinationDistrict;
  final String? requiredByDate;
  final int? budgetMinMinor;
  final int? budgetMaxMinor;
  final String currencyCode;
  final String? expiresAt;
  final String? createdAt;

  bool get isOpen => state == 'OPEN' || state == 'MATCHING';

  String get destinationLabel {
    if (destinationRegion == null && destinationDistrict == null) return '';
    return [destinationDistrict, destinationRegion].whereType<String>().join(', ');
  }
}

class OrderItemJson {
  OrderItemJson.fromJson(Map<String, dynamic> j)
      : productId = j['product_id'] as String?,
        description = j['description'] as String? ?? '',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        lineTotalMinor = (j['line_total_minor'] as num?)?.toInt() ?? 0;

  final String? productId;
  final String description;
  final double quantityValue;
  final String unitCode;
  final int lineTotalMinor;
}

class OrderJson {
  OrderJson.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        orderNumber = j['order_number'] as String? ?? j['id'] as String,
        state = j['state'] as String? ?? 'DRAFT',
        buyerId = j['buyer_id'] as String?,
        sellerId = j['seller_id'] as String?,
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        unitPriceMinor = (j['unit_price_minor'] as num?)?.toInt() ?? 0,
        totalAmountMinor = (j['total_amount_minor'] as num?)?.toInt() ?? 0,
        platformFeeMinor = (j['platform_fee_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        deliveryOption = j['delivery_option'] as String? ?? 'PICKUP',
        paymentTerms = j['payment_terms'] as String? ?? '',
        hasContract = (j['has_contract'] as bool?) ?? false,
        deliveryId = j['delivery_id'] as String?,
        items = ((j['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrderItemJson.fromJson)
            .toList(),
        cancelledReason = j['cancelled_reason'] as String?,
        completedAt = j['completed_at'] as String?,
        createdAt = j['created_at'] as String?,
        events = ((j['events'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OrderEventJson.fromJson)
            .toList();

  final String id;
  final String orderNumber;
  final String state;
  final String? buyerId;
  final String? sellerId;
  final double quantityValue;
  final String unitCode;
  final int unitPriceMinor;
  final int totalAmountMinor;
  final int platformFeeMinor;
  final String currencyCode;
  final String deliveryOption;
  final String paymentTerms;
  final bool hasContract;
  final String? deliveryId;
  final List<OrderItemJson> items;
  final String? cancelledReason;
  final String? completedAt;
  final String? createdAt;
  final List<OrderEventJson> events;

  bool get needsPayment => state == 'PAYMENT_PENDING';
  int get deliveryFeeMinor => 0; // delivery is quoted/logistics, not part of order totals
}

class OrderEventJson {
  OrderEventJson.fromJson(Map<String, dynamic> j)
      : eventType = j['event_type'] as String? ?? '',
        fromState = j['from_state'] as String?,
        toState = j['to_state'] as String?,
        at = j['at'] as String?;

  final String eventType;
  final String? fromState;
  final String? toState;
  final String? at;
}

/// An explainable match between a buyer request and a listing.
class RequestMatch {
  RequestMatch.fromJson(Map<String, dynamic> j)
      : listingId = j['listing_id'] as String?,
        sellerId = j['seller_id'] as String?,
        matchScore = (j['match_score'] as num?)?.toInt() ?? 0,
        reasons = ((j['reasons'] as List?) ?? const [])
            .whereType<String>()
            .toList();

  final String? listingId;
  final String? sellerId;
  final int matchScore;
  final List<String> reasons;
}

/// A matching opportunity shown to a farmer (from `/opportunities`).
class Opportunity {
  Opportunity.fromJson(Map<String, dynamic> j)
      : buyerRequestId = j['buyer_request_id'] as String?,
        title = j['title'] as String? ?? '',
        productId = j['product_id'] as String?,
        quantity = (j['quantity'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        budgetRangeMinor = ((j['budget_range_minor'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        destinationRegion = j['destination_region'] as String?,
        requiredByDate = j['required_by_date'] as String?,
        youQualify = (j['you_qualify'] as bool?) ?? false,
        yourAvailableQuantity = (j['your_available_quantity'] as num?)?.toDouble(),
        why = ((j['why'] as List?) ?? const []).whereType<String>().toList();

  final String? buyerRequestId;
  final String title;
  final String? productId;
  final double quantity;
  final String unitCode;
  final List<int> budgetRangeMinor;
  final String currencyCode;
  final String? destinationRegion;
  final String? requiredByDate;
  final bool youQualify;
  final double? yourAvailableQuantity;
  final List<String> why;
}

class MarketPriceRow {
  MarketPriceRow.fromJson(Map<String, dynamic> j)
      : productName =
            (j['product'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
        region = j['region'] as String?,
        marketName = j['market_name'] as String?,
        observedOn = j['observed_on'] as String?,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        unitCode = j['unit_code'] as String? ?? 'kg',
        lowMinor = (j['price_low_minor'] as num?)?.toInt(),
        midMinor = (j['price_mid_minor'] as num?)?.toInt(),
        highMinor = (j['price_high_minor'] as num?)?.toInt(),
        sourceName =
            (j['source'] as Map<String, dynamic>?)?['name'] as String?;

  final String productName;
  final String? region;
  final String? marketName;
  final String? observedOn;
  final String currencyCode;
  final String unitCode;
  final int? lowMinor;
  final int? midMinor;
  final int? highMinor;
  final String? sourceName;
}

class SavedSearch {
  SavedSearch.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String? ?? 'Search',
        query = j['query'] as Map<String, dynamic>? ?? const {},
        notify = (j['notify'] as bool?) ?? true,
        createdAt = j['created_at'] as String?;

  final String id;
  final String label;
  final Map<String, dynamic> query;
  final bool notify;
  final String? createdAt;
}

class SearchResults {
  SearchResults.fromJson(Map<String, dynamic> j, {String query = ''})
      : query = query,
        products = ((j['products'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ProductSummary.fromJson)
            .toList(),
        listings = ((j['listings'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Listing.fromJson)
            .toList(),
        farmers = ((j['farmers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((f) => FarmerSearchHit.fromJson(f))
            .toList(),
        groups = ((j['groups'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((g) => GroupSearchHit.fromJson(g))
            .toList();

  final String query;
  final List<ProductSummary> products;
  final List<Listing> listings;
  final List<FarmerSearchHit> farmers;
  final List<GroupSearchHit> groups;

  bool get isEmpty =>
      products.isEmpty && listings.isEmpty && farmers.isEmpty && groups.isEmpty;
}

class FarmerSearchHit {
  FarmerSearchHit.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        fullName = j['full_name'] as String? ?? '',
        region = j['region'] as String?;

  final String id;
  final String fullName;
  final String? region;
}

class GroupSearchHit {
  GroupSearchHit.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        memberCount = (j['member_count'] as num?)?.toInt() ?? 0;

  final String id;
  final String name;
  final int memberCount;
}

class WalletSummary {
  WalletSummary.fromJson(Map<String, dynamic> j)
      : availableMinor = (j['available_minor'] as num?)?.toInt() ?? 0,
        pendingMinor = (j['pending_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF';

  final int availableMinor;
  final int pendingMinor;
  final String currencyCode;
}

class WalletLedgerEntry {
  WalletLedgerEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        entryType = j['entry_type'] as String? ?? '',
        reasonCode = j['reason_code'] as String? ?? '',
        amountMinor = (j['amount_minor'] as num?)?.toInt() ?? 0,
        balanceAfterMinor = (j['balance_after_minor'] as num?)?.toInt() ?? 0,
        referenceType = j['reference_type'] as String? ?? '',
        referenceId = j['reference_id'] as String? ?? '',
        description = j['description'] as String? ?? '',
        createdAt = j['created_at'] as String?;

  final String id;
  final String entryType;
  final String reasonCode;
  final int amountMinor;
  final int balanceAfterMinor;
  final String referenceType;
  final String referenceId;
  final String description;
  final String? createdAt;
}

/// Aggregate reputation for a user from `/reputation/users/<id>`.
class ReputationSummary {
  ReputationSummary.fromJson(Map<String, dynamic> j)
      : tier = j['tier'] as String? ?? 'NEW_MEMBER',
        score = (j['score'] as num?)?.toInt() ?? 0,
        ratingAvg = ((j['rating_avg'] as num?) ?? 0).toDouble(),
        ratingCount = (j['rating_count'] as num?)?.toInt() ?? 0,
        completedTransactions =
            (j['completed_transactions'] as num?)?.toInt() ?? 0,
        completedPurchases =
            (j['completed_purchases'] as num?)?.toInt() ?? 0,
        completedDeliveries =
            (j['completed_deliveries'] as num?)?.toInt() ?? 0;

  final String tier;
  final int score;
  final double ratingAvg;
  final int ratingCount;
  final int completedTransactions;
  final int completedPurchases;
  final int completedDeliveries;

  int get completedActivity =>
      completedTransactions + completedPurchases + completedDeliveries;
}

/// One review left about a user, from `/users/<id>/reviews`.
class UserReview {
  UserReview.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        subjectRole = j['subject_role'] as String? ?? '',
        overallRating = (j['overall_rating'] as num?)?.toInt() ?? 5,
        comment = j['comment'] as String? ?? '',
        verifiedTransaction = (j['verified_transaction'] as bool?) ?? false,
        createdAt = j['created_at'] as String?,
        reviewerName =
            (j['reviewer'] as Map<String, dynamic>?)?['full_name'] as String? ??
                (j['reviewer'] as Map<String, dynamic>?)?['username'] as String? ??
                'Buyer',
        orderNumber =
            (j['order'] as Map<String, dynamic>?)?['order_number'] as String?,
        orderQuantity =
            ((j['order'] as Map<String, dynamic>?)?['quantity_value'] as num?)
                ?.toDouble(),
        orderUnit =
            (j['order'] as Map<String, dynamic>?)?['unit_code'] as String? ??
                'kg',
        listingTitle =
            (j['listing'] as Map<String, dynamic>?)?['title'] as String?,
        productName =
            (j['listing'] as Map<String, dynamic>?)?['product'] as String?;

  final String id;
  final String subjectRole;
  final int overallRating;
  final String comment;
  final bool verifiedTransaction;
  final String? createdAt;
  final String reviewerName;
  final String? orderNumber;
  final double? orderQuantity;
  final String orderUnit;
  final String? listingTitle;
  final String? productName;
}

/// Aggregated seller dashboard from `/seller/dashboard` (server-computed from the
/// seller's own listings/offers/orders/wallet rows).
class SellerDashboard {
  SellerDashboard.fromJson(Map<String, dynamic> j)
      : summary = SellerSummary.fromJson(
            (j['summary'] as Map<String, dynamic>?) ?? const {}),
        wallet = WalletSummary.fromJson(
            (j['wallet'] as Map<String, dynamic>?) ?? const {}),
        listings = ((j['listings'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashboardListingRow.fromJson)
            .toList(),
        recentOffers = ((j['recent_offers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashboardOfferRow.fromJson)
            .toList(),
        recentOrders = ((j['recent_orders'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashboardOrderRow.fromJson)
            .toList();

  final SellerSummary summary;
  final WalletSummary wallet;
  final List<DashboardListingRow> listings;
  final List<DashboardOfferRow> recentOffers;
  final List<DashboardOrderRow> recentOrders;
}

class SellerSummary {
  SellerSummary.fromJson(Map<String, dynamic> j)
      : listingsTotal = (j['listings_total'] as num?)?.toInt() ?? 0,
        listingsActive = (j['listings_active'] as num?)?.toInt() ?? 0,
        totalViews = (j['total_views'] as num?)?.toInt() ?? 0,
        offersTotal = (j['offers_total'] as num?)?.toInt() ?? 0,
        offersPending = (j['offers_pending'] as num?)?.toInt() ?? 0,
        ordersTotal = (j['orders_total'] as num?)?.toInt() ?? 0,
        ordersOpen = (j['orders_open'] as num?)?.toInt() ?? 0,
        ordersCompleted = (j['orders_completed'] as num?)?.toInt() ?? 0,
        ordersClosedOut = (j['orders_closed_out'] as num?)?.toInt() ?? 0,
        grossSalesMinor = (j['gross_sales_minor'] as num?)?.toInt() ?? 0,
        feesMinor = (j['fees_minor'] as num?)?.toInt() ?? 0,
        netRevenueMinor = (j['net_revenue_minor'] as num?)?.toInt() ?? 0,
        ratingAvg = (j['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount = (j['rating_count'] as num?)?.toInt() ?? 0,
        reputationTier = j['reputation_tier'] as String? ?? 'NEW_MEMBER',
        completedTransactions =
            (j['completed_transactions'] as num?)?.toInt() ?? 0;

  final int listingsTotal;
  final int listingsActive;
  final int totalViews;
  final int offersTotal;
  final int offersPending;
  final int ordersTotal;
  final int ordersOpen;
  final int ordersCompleted;
  final int ordersClosedOut;
  final int grossSalesMinor;
  final int feesMinor;
  final int netRevenueMinor;
  final double ratingAvg;
  final int ratingCount;
  final String reputationTier;
  final int completedTransactions;
}

/// One of the seller's own listings with its live performance numbers.
class DashboardListingRow {
  DashboardListingRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        state = j['state'] as String? ?? 'ACTIVE',
        listingType = j['listing_type'] as String? ?? 'FIXED_PRICE',
        emoji = (j['product'] as Map<String, dynamic>?)?['emoji'] as String? ?? '🌱',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        unitCode = j['unit_code'] as String? ?? 'kg',
        availableQuantity = (j['available_quantity'] as num?)?.toDouble() ?? 0,
        viewCount = (j['view_count'] as num?)?.toInt() ?? 0,
        offersPending = (j['offers_pending'] as num?)?.toInt() ?? 0,
        ordersTotal = (j['orders_total'] as num?)?.toInt() ?? 0,
        soldValueMinor = (j['sold_value_minor'] as num?)?.toInt() ?? 0;

  final String id;
  final String title;
  final String state;
  final String listingType;
  final String emoji;
  final int priceMinor;
  final String currencyCode;
  final String unitCode;
  final double availableQuantity;
  final int viewCount;
  final int offersPending;
  final int ordersTotal;
  final int soldValueMinor;
}

/// Offer received by the seller (from dashboard `recent_offers`).
class DashboardOfferRow {
  DashboardOfferRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        listingId = j['listing_id'] as String?,
        state = j['state'] as String? ?? 'PENDING',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        buyerName =
            (j['buyer'] as Map<String, dynamic>?)?['full_name'] as String? ??
                (j['buyer'] as Map<String, dynamic>?)?['username'] as String? ??
                'Buyer',
        listingTitle =
            (j['listing'] as Map<String, dynamic>?)?['title'] as String?,
        createdAt = j['created_at'] as String?;

  final String id;
  final String? listingId;
  final String state;
  final double quantityValue;
  final String unitCode;
  final int priceMinor;
  final String currencyCode;
  final String buyerName;
  final String? listingTitle;
  final String? createdAt;
}

/// Order on the seller's account (from dashboard `recent_orders`).
class DashboardOrderRow {
  DashboardOrderRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        orderNumber = j['order_number'] as String? ?? j['id'] as String,
        state = j['state'] as String? ?? 'DRAFT',
        quantityValue = (j['quantity_value'] as num?)?.toDouble() ?? 0,
        unitCode = j['unit_code'] as String? ?? 'kg',
        totalAmountMinor = (j['total_amount_minor'] as num?)?.toInt() ?? 0,
        currencyCode = j['currency_code'] as String? ?? 'RWF',
        buyerName =
            (j['buyer'] as Map<String, dynamic>?)?['full_name'] as String? ??
                (j['buyer'] as Map<String, dynamic>?)?['username'] as String? ??
                'Buyer',
        listingTitle =
            (j['listing'] as Map<String, dynamic>?)?['title'] as String?,
        createdAt = j['created_at'] as String?;

  final String id;
  final String orderNumber;
  final String state;
  final double quantityValue;
  final String unitCode;
  final int totalAmountMinor;
  final String currencyCode;
  final String buyerName;
  final String? listingTitle;
  final String? createdAt;
}