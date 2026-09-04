import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_db.dart';
import 'marketplace_models.dart';

/// Paginated response shape used by every backend list endpoint.
class Paged<T> {
  Paged({required this.items, required this.page, required this.perPage, required this.total});

  final List<T> items;
  final int page;
  final int perPage;
  final int total;

  bool get hasMore => page * perPage < total;
}

/// Typed access to every marketplace backend endpoint.
///
/// Screens never call `ApiClient` directly — they go through this repository
/// so models, pagination and error handling stay in one place.
class MarketplaceRepository {
  MarketplaceRepository(this._api, {Future<LocalDb> Function()? localDb})
      : _localDb = localDb;

  final ApiClient _api;
  final Future<LocalDb> Function()? _localDb;

  // ---- catalog & discovery ----

  Future<List<Category>> categories() async {
    final res = await _api.getJson('/categories');
    return (res['categories'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  Future<List<ProductSummary>> products({String? category, String? q}) async {
    final res = await _api.getJson('/products', query: {
      'per_page': '300',
      if (category != null && category.isNotEmpty) 'category': category,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return (res['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductSummary.fromJson)
        .toList();
  }

  Future<Paged<Listing>> listings({
    String? product,
    String? category,
    String? region,
    String? qualityGrade,
    String? listingType,
    double? minQuantity,
    bool? negotiable,
    bool? verified,
    String sort = 'recent',
    int page = 1,
    int perPage = 20,
  }) async {
    final res = await _api.getJson('/listings', query: {
      'page': '$page',
      'per_page': '$perPage',
      'sort': sort,
      if (product != null && product.isNotEmpty) 'product': product,
      if (category != null && category.isNotEmpty) 'category': category,
      if (region != null && region.isNotEmpty) 'region': region,
      if (qualityGrade != null && qualityGrade.isNotEmpty)
        'quality_grade': qualityGrade,
      if (listingType != null && listingType.isNotEmpty)
        'listing_type': listingType,
      if (minQuantity != null && minQuantity > 0)
        'min_quantity': '$minQuantity',
      if (negotiable == true) 'negotiable': 'true',
      if (verified == true) 'verified': 'true',
    });
    final rawItems = (res['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    // Write-through: remember the latest feed so the home can still show
    // produce offline. Fire-and-forget; the cache never blocks a response.
    _cacheListings(rawItems);
    final pagination = (res['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged<Listing>(
      items: rawItems.map(Listing.fromJson).toList(),
      page: (pagination['page'] as num?)?.toInt() ?? page,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? perPage,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Best-effort write-through of raw listing rows into the local cache.
  void _cacheListings(List<Map<String, dynamic>> rows) {
    final db = _localDb;
    if (db == null || rows.isEmpty) return;
    Future(() async {
      try {
        final local = await db();
        for (final row in rows) {
          final id = row['id'];
          if (id is String) await local.upsertCache('listings', id, row);
        }
      } catch (_) {
        // cache is best-effort
      }
    });
  }

  /// Listings saved locally from earlier feeds — the offline fallback for the
  /// marketplace home. Never throws: returns an empty list on any failure.
  Future<List<Listing>> cachedListings({int limit = 60}) async {
    final db = _localDb;
    if (db == null) return const [];
    try {
      final rows = await (await db()).readCollection('listings', limit: limit);
      return rows.map(Listing.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<(Listing, List<ListingMedia>)> listing(String listingId) async {
    final res = await _api.getJson('/listings/$listingId');
    final l = Listing.fromJson(res['listing'] as Map<String, dynamic>);
    final media = (res['media'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ListingMedia.fromJson)
        .toList();
    return (l, media);
  }

  Future<Paged<Listing>> myListings({int page = 1, int perPage = 50}) async {
    final res = await _api.getJson('/listings/mine', query: {
      'page': '$page',
      'per_page': '$perPage',
    });
    final pagination = (res['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged<Listing>(
      items: (res['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Listing.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? page,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? perPage,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SearchResults> search(String q, {String scope = 'all'}) async {
    final res = await _api.getJson('/search', query: {'q': q, 'scope': scope});
    return SearchResults.fromJson(res, query: q);
  }

  // ---- seller tools ----

  Future<Listing> createListing(Map<String, dynamic> payload) async {
    final res = await _api.postJson('/listings', payload);
    return Listing.fromJson(res['listing'] as Map<String, dynamic>);
  }

  Future<Listing> updateListing(String listingId, Map<String, dynamic> patch) async {
    final res = await _api.patchJson('/listings/$listingId', patch);
    return Listing.fromJson(res['listing'] as Map<String, dynamic>);
  }

  Future<Listing> closeListing(String listingId) async {
    final res = await _api.postJson('/listings/$listingId/close', {});
    return Listing.fromJson(res['listing'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> priceAdvice({
    required String productId,
    String? region,
    required int priceMinor,
    String unitCode = 'kg',
  }) async {
    return _api.getJson('/price-advice', query: {
      'product_id': productId,
      if (region != null && region.isNotEmpty) 'region': region,
      'price_minor': '$priceMinor',
      'unit_code': unitCode,
    });
  }

  // ---- offers & negotiation ----

  Future<Paged<Offer>> offers({
    String role = 'buyer',
    String? state,
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _api.getJson('/offers/mine', query: {
      'role': role,
      if (state != null) 'state': state,
      'page': '$page',
      'per_page': '$perPage',
    });
    final pagination = (res['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged<Offer>(
      items: (res['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Offer.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? page,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? perPage,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Offer> createOffer(Map<String, dynamic> payload) async {
    final res = await _api.postJson('/offers', payload);
    return Offer.fromJson(res['offer'] as Map<String, dynamic>);
  }

  Future<Offer> counterOffer(String offerId, {required int priceMinor, double? quantity, String message = ''}) async {
    final res = await _api.postJson('/offers/$offerId/counter', {
      'price_minor': priceMinor,
      if (quantity != null) 'quantity_value': quantity,
      'message': message,
    });
    return Offer.fromJson(res['offer'] as Map<String, dynamic>);
  }

  Future<OrderJson> acceptOffer(String offerId) async {
    final res = await _api.postJson('/offers/$offerId/accept', {});
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<Offer> rejectOffer(String offerId) async {
    final res = await _api.postJson('/offers/$offerId/reject', {});
    return Offer.fromJson(res['offer'] as Map<String, dynamic>);
  }

  Future<Offer> withdrawOffer(String offerId) async {
    final res = await _api.postJson('/offers/$offerId/withdraw', {});
    return Offer.fromJson(res['offer'] as Map<String, dynamic>);
  }

  Future<List<Offer>> listingOffers(String listingId) async {
    final res = await _api.getJson('/listings/$listingId/offers');
    return (res['offers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Offer.fromJson)
        .toList();
  }

  // ---- bids ----

  Future<Bid> placeBid({
    required String listingId,
    required int amountMinor,
    required double quantityValue,
  }) async {
    final res = await _api.postJson('/bids', {
      'listing_id': listingId,
      'amount_minor': amountMinor,
      'quantity_value': quantityValue,
    });
    return Bid.fromJson(res['bid'] as Map<String, dynamic>);
  }

  Future<List<Bid>> bids(String listingId) async {
    final res = await _api.getJson('/listings/$listingId/bids');
    return (res['bids'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Bid.fromJson)
        .toList();
  }

  Future<OrderJson> acceptWinningBid(String listingId) async {
    final res = await _api.postJson('/listings/$listingId/accept-winning-bid', {});
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  // ---- buyer requests & opportunities ----

  Future<Paged<BuyerRequest>> buyerRequests({int page = 1, int perPage = 30}) async {
    final res = await _api.getJson('/buyer-requests', query: {
      'page': '$page',
      'per_page': '$perPage',
    });
    final pagination = (res['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged<BuyerRequest>(
      items: (res['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BuyerRequest.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? page,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? perPage,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<BuyerRequest> createBuyerRequest(Map<String, dynamic> payload) async {
    final res = await _api.postJson('/buyer-requests', payload);
    return BuyerRequest.fromJson(res['request'] as Map<String, dynamic>);
  }

  Future<List<RequestMatch>> requestMatches(String requestId) async {
    final res = await _api.getJson('/buyer-requests/$requestId/matches');
    return (res['matches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RequestMatch.fromJson)
        .toList();
  }

  Future<List<Opportunity>> opportunities() async {
    final res = await _api.getJson('/opportunities', query: {'limit': '30'});
    return (res['opportunities'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Opportunity.fromJson)
        .toList();
  }

  // ---- orders ----

  Future<Paged<OrderJson>> orders({String? state, String? role, int page = 1, int perPage = 50}) async {
    final res = await _api.getJson('/orders', query: {
      if (state != null) 'state': state,
      if (role != null) 'role': role,
      'page': '$page',
      'per_page': '$perPage',
    });
    final pagination = (res['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged<OrderJson>(
      items: (res['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OrderJson.fromJson)
          .toList(),
      page: (pagination['page'] as num?)?.toInt() ?? page,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? perPage,
      total: (pagination['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<OrderJson> order(String orderId) async {
    final res = await _api.getJson('/orders/$orderId');
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<OrderJson> createOrderDraft({required String listingId, required double quantity}) async {
    final res = await _api.postJson('/orders/draft', {
      'listing_id': listingId,
      'quantity_value': quantity,
    });
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<OrderJson> transitionOrder(String orderId, String state, {String reason = ''}) async {
    final res = await _api.postJson('/orders/$orderId/transition', {
      'state': state,
      'reason': reason,
    });
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<OrderJson> cancelOrder(String orderId, {String reason = ''}) async {
    final res = await _api.postJson('/orders/$orderId/cancel', {'reason': reason});
    return OrderJson.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> initiatePayment(String orderId, {String provider = 'mock', String? method, String? phone}) async {
    return _api.postJson('/orders/$orderId/payments', {
      'provider': provider,
      'method': method ?? 'mobile_money',
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
  }

  Future<Map<String, dynamic>> reviewOrder(
    String orderId, {
    required String subjectRole,
    required int overall,
    String comment = '',
  }) async {
    return _api.postJson('/orders/$orderId/reviews', {
      'subject_role': subjectRole,
      'overall_rating': overall,
      'comment': comment,
    });
  }

  // ---- wallet ----

  Future<WalletSummary> wallet() async {
    final res = await _api.getJson('/wallet');
    return WalletSummary.fromJson(res);
  }

  Future<List<WalletLedgerEntry>> walletLedger({int perPage = 30}) async {
    final res = await _api.getJson('/wallet/ledger', query: {'per_page': '$perPage'});
    return (res['entries'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WalletLedgerEntry.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> withdraw({
    required int amountMinor,
    String method = 'mobile_money',
    required String destinationDetail,
  }) async {
    return _api.postJson('/wallet/withdrawals', {
      'amount_minor': amountMinor,
      'method': method,
      'destination_detail': destinationDetail,
    });
  }

  // ---- favorites & saved searches ----

  Future<List<Listing>> favorites() async {
    final res = await _api.getJson('/favorites');
    return (res['favorites'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Listing.fromJson)
        .toList();
  }

  Future<void> addFavorite(String listingId) async {
    await _api.postJson('/favorites', {'listing_id': listingId});
  }

  Future<void> removeFavorite(String listingId) async {
    await _api.delete('/favorites/$listingId');
  }

  Future<List<SavedSearch>> savedSearches() async {
    final res = await _api.getJson('/saved-searches');
    return (res['saved_searches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavedSearch.fromJson)
        .toList();
  }

  Future<SavedSearch> createSavedSearch(
      {required String label, required Map<String, dynamic> query, bool notify = true}) async {
    final res = await _api.postJson('/saved-searches', {
      'name': label,
      'query_json': query,
      'notify': notify,
    });
    return SavedSearch.fromJson((res['saved_search'] as Map<String, dynamic>)..['query'] = query);
  }

  Future<void> deleteSavedSearch(String searchId) async {
    await _api.delete('/saved-searches/$searchId');
  }

  // ---- chat bridge ----

  /// Starts a conversation with a user and returns the conversation id.
  Future<String> startConversation({
    required String withUserId,
    String context = 'listing',
    String? listingId,
  }) async {
    final res = await _api.postJson('/conversations', {
      'with_user_id': withUserId,
      'context': context,
      if (listingId != null) 'listing_id': listingId,
    });
    return (res['conversation'] as Map<String, dynamic>)['id'] as String;
  }

  // ---- market prices ----

  Future<List<MarketPriceRow>> marketPrices({String? product, String? region, int days = 7}) async {
    final res = await _api.getJson('/market-prices', query: {
      'days': '$days',
      'limit': '60',
      if (product != null && product.isNotEmpty) 'product': product,
      if (region != null && region.isNotEmpty) 'region': region,
    });
    return (res['prices'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MarketPriceRow.fromJson)
        .toList();
  }

  // ---- seller dashboard ----

  /// Server-aggregated selling metrics for the current user.
  Future<SellerDashboard> sellerDashboard() async {
    final res = await _api.getJson('/seller/dashboard');
    return SellerDashboard.fromJson(res);
  }

  // ---- reputation & reviews ----

  /// Aggregate rating/tier for a user (farmer, buyer or logistics).
  Future<ReputationSummary> reputationSummary(String userId) async {
    final res = await _api.getJson('/reputation/users/$userId');
    return ReputationSummary.fromJson(res);
  }

  /// Reviews received by a user, newest first, with order/listing context.
  Future<List<UserReview>> userReviews(String userId) async {
    final res = await _api.getJson('/users/$userId/reviews');
    return (res['reviews'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UserReview.fromJson)
        .toList();
  }
}

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  return MarketplaceRepository(ref.watch(apiClientProvider),
      localDb: () => ref.read(localDbProvider.future));
});