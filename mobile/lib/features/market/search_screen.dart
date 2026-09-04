import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';
import 'marketplace_widgets.dart';

/// Search-first marketplace experience.
///
/// - Predictive suggestions (products / farmers / groups) via `/search`
/// - Results from `/listings` with backend-side filters + sorting + pagination
/// - Mobile filter bottom sheet, individually removable active chips
/// - Save searches for later matching
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _Filters {
  String? product;
  String? category;
  String? region;
  String? qualityGrade;
  String? listingType;
  int? minPriceMinor;
  int? maxPriceMinor;
  double? minQuantity;
  bool negotiable = false;
  bool verified = false;
  String sort = 'recent';

  Map<String, dynamic> toQuery() => {
        if (product != null && product!.isNotEmpty) 'product': product,
        if (category != null && category!.isNotEmpty) 'category': category,
        if (region != null && region!.isNotEmpty) 'region': region,
        if (qualityGrade != null && qualityGrade!.isNotEmpty)
          'quality_grade': qualityGrade,
        if (listingType != null && listingType!.isNotEmpty)
          'listing_type': listingType,
        if (minQuantity != null && minQuantity! > 0) 'min_quantity': minQuantity,
        'negotiable': negotiable,
        'verified': verified,
      };

  bool get hasActiveFilters =>
      region != null ||
      qualityGrade != null ||
      listingType != null ||
      minPriceMinor != null ||
      maxPriceMinor != null ||
      minQuantity != null ||
      negotiable ||
      verified;
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryCtl = TextEditingController();
  Timer? _debounce;
  int _debounceSeq = 0;

  final _filters = _Filters();
  SearchResults? _suggestions;
  Paged<Listing>? _results;
  bool _loadingResults = false;
  String? _error;
  bool _showEmpty = false;

  // Preserve scroll intent across result reloads.
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _queryCtl.addListener(_onQueryChanged);
    _restoreExtras();
    _fetchResults();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Routes push this screen with `extra: {category, browse}` from the home
  /// category rail and section "See all" links.
  void _restoreExtras() {
    final extra = GoRouterState.of(context).extra;
    if (extra is Map<String, dynamic>) {
      final cat = extra['category'];
      if (cat is Category) {
        _filters.category = cat.slug;
        _filters.product = null;
        _queryCtl.text = '';
        setState(() {});
        return;
      }
      final catSlug = extra['category_slug'];
      if (catSlug is String) _filters.category = catSlug;
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _queryCtl.text.trim();
    if (q.length < 2) {
      _suggestions = null;
      if (mounted) setState(() {});
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_debounceSeq;
      try {
        final res = await ref
            .read(marketplaceRepositoryProvider)
            .search(q);
        if (!mounted || seq != _debounceSeq) return;
        setState(() => _suggestions = res);
      } catch (_) {
        // suggestions are best-effort
      }
    });
  }

  Future<void> _fetchResults() async {
    setState(() {
      _loadingResults = true;
      _error = null;
    });
    final repo = ref.read(marketplaceRepositoryProvider);
    final q = _queryCtl.text.trim();
    final f = _filters;
    try {
      final res = await repo.listings(
        product: q.isEmpty ? f.product : q,
        category: f.category,
        region: f.region,
        qualityGrade: f.qualityGrade,
        listingType: f.listingType,
        minQuantity: f.minQuantity,
        negotiable: f.negotiable,
        verified: f.verified,
        sort: f.sort,
        perPage: 30,
      );
      if (!mounted) return;
      setState(() {
        _results = res;
        _loadingResults = false;
        _showEmpty = res.items.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingResults = false;
        _error = ApiClient.errorMessage(e);
      });
    }
  }

  void _applyFilters(_Filters next) {
    _filters
      ..product = next.product
      ..category = next.category
      ..region = next.region
      ..qualityGrade = next.qualityGrade
      ..listingType = next.listingType
      ..minPriceMinor = next.minPriceMinor
      ..maxPriceMinor = next.maxPriceMinor
      ..minQuantity = next.minQuantity
      ..negotiable = next.negotiable
      ..verified = next.verified
      ..sort = next.sort;
    setState(() {});
    _fetchResults();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_Filters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: IjwiColors.surface,
      builder: (context) => _FilterSheet(initial: _filters),
    );
    if (result != null) _applyFilters(result);
  }

  Future<void> _openSort() async {
    final labels = {
      'recent': 'Newest',
      'price_asc': 'Price: low → high',
      'price_desc': 'Price: high → low',
      'quantity_desc': 'Highest quantity',
      'rated': 'Highest rated',
      'ending_soon': 'Ending soon',
    };
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: IjwiColors.surface,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Sort by',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final entry in labels.entries)
            RadioListTile<String>(
              dense: true,
              title: Text(entry.value),
              value: entry.key,
              groupValue: _filters.sort,
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ]),
      ),
    );
    if (chosen != null) {
      _filters.sort = chosen;
      setState(() {});
      _fetchResults();
    }
  }

  Future<void> _saveSearch() async {
    if (_queryCtl.text.trim().isEmpty && !_filters.hasActiveFilters) return;
    final labelCtl = TextEditingController(
        text: _queryCtl.text.trim().isNotEmpty
            ? _queryCtl.text.trim()
            : 'My search');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save this search'),
        content: TextField(
          controller: labelCtl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(marketplaceRepositoryProvider).createSavedSearch(
            label: labelCtl.text.trim(),
            query: {
              'q': _queryCtl.text.trim(),
              ..._filters.toQuery(),
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Search saved — we’ll notify you on new matches'),
          backgroundColor: IjwiColors.green));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  void _clearFilters() {
    _filters
      ..product = null
      ..category = null
      ..region = null
      ..qualityGrade = null
      ..listingType = null
      ..minPriceMinor = null
      ..maxPriceMinor = null
      ..minQuantity = null
      ..negotiable = false
      ..verified = false
      ..sort = 'recent';
    setState(() {});
    _fetchResults();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _queryCtl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _fetchResults(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Search products, farmers, buyers…',
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon:
                  const Icon(Icons.search, color: Colors.white, size: 20),
              suffixIcon: _queryCtl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      onPressed: () {
                        _queryCtl.clear();
                        _fetchResults();
                      })
                  : null,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Save search',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _saveSearch,
          ),
        ],
      ),
      body: Column(children: [
        _buildFilterBar(),
        Divider(height: 1, color: const Color(0xFFD7E2DA).withOpacity(0.4)),
        Expanded(child: _buildResults()),
      ]),
    );
  }

  Widget _buildFilterBar() {
    final f = _filters;
    final chips = <Widget>[];
    int chipIndex = 0;
    void addChip(String label, VoidCallback onRemove) {
      chips.add(InputChip(
        key: ValueKey('chip-${chipIndex++}'),
        visualDensity: VisualDensity.compact,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon:
            const Icon(Icons.close, size: 14, color: IjwiColors.muted),
        onDeleted: onRemove,
      ));
    }

    if (f.category != null) addChip('Category', () {
      _filters.category = null;
      setState(() {});
      _fetchResults();
    });
    if (f.region != null) addChip(f.region!, () {
      _filters.region = null;
      setState(() {});
      _fetchResults();
    });
    if (f.qualityGrade != null) addChip(f.qualityGrade!, () {
      _filters.qualityGrade = null;
      setState(() {});
      _fetchResults();
    });
    if (f.listingType != null) addChip(f.listingType!, () {
      _filters.listingType = null;
      setState(() {});
      _fetchResults();
    });
    if (f.minPriceMinor != null) addChip('Min ${(f.minPriceMinor! / 100).toStringAsFixed(0)}', () {
      _filters.minPriceMinor = null;
      setState(() {});
      _fetchResults();
    });
    if (f.maxPriceMinor != null) addChip('Max ${(f.maxPriceMinor! / 100).toStringAsFixed(0)}', () {
      _filters.maxPriceMinor = null;
      setState(() {});
      _fetchResults();
    });
    if (f.minQuantity != null) addChip('≥ ${f.minQuantity} ${'kg'}', () {
      _filters.minQuantity = null;
      setState(() {});
      _fetchResults();
    });
    if (f.negotiable) addChip('Negotiable', () {
      _filters.negotiable = false;
      setState(() {});
      _fetchResults();
    });
    if (f.verified) addChip('Verified', () {
      _filters.verified = false;
      setState(() {});
      _fetchResults();
    });

    return SizedBox(
      height: 52,
      child: Row(children: [
        IconButton(
          tooltip: 'Filters',
          onPressed: _openFilters,
          icon: Badge(
            isLabelVisible: f.hasActiveFilters,
            child: const Icon(Icons.tune, color: IjwiColors.green),
          ),
        ),
        Expanded(
          child: chips.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('Filter results',
                        style: TextStyle(color: IjwiColors.muted, fontSize: 13)),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ...chips,
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear all',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
        ),
        TextButton.icon(
          onPressed: _openSort,
          icon: const Icon(Icons.swap_vert, size: 18),
          label: Text(_sortLabel(f.sort), style: const TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  String _sortLabel(String s) => switch (s) {
        'price_asc' => 'Price ↑',
        'price_desc' => 'Price ↓',
        'quantity_desc' => 'Quantity',
        'rated' => 'Rated',
        'ending_soon' => 'Ending',
        _ => 'Newest',
      };

  Widget _buildResults() {
    final suggestions = _suggestions;
    if (_queryCtl.text.trim().length >= 2 && suggestions != null &&
        !_loadingResults && _results == null) {
      return _buildSuggestions(suggestions);
    }
    if (_loadingResults && _results == null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: const [
          Skeleton(height: 84), SizedBox(height: 8),
          Skeleton(height: 84), SizedBox(height: 8),
          Skeleton(height: 84),
        ],
      );
    }
    if (_error != null && _results == null) {
      return ListView(children: [ErrorBox(_error!, onRetry: _fetchResults)]);
    }
    final results = _results;
    if (results == null || results.items.isEmpty) {
      return MarketplaceEmpty(
        icon: _showEmpty ? Icons.search_off : Icons.storefront_outlined,
        title: _showEmpty
            ? 'No results'
            : 'Browse the marketplace',
        message: _showEmpty
            ? 'Try a different product, widen the location, or remove filters.'
            : 'Search for produce, farmers and buyer requests.',
        actionLabel: _showEmpty ? 'Clear filters' : null,
        onAction: _showEmpty ? _clearFilters : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchResults,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: results.items.length,
        itemBuilder: (context, i) => ListingRow(listing: results.items[i]),
      ),
    );
  }

  Widget _buildSuggestions(SearchResults s) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (s.products.isNotEmpty) ...[
          const _SuggestionHeader('Products'),
          for (final p in s.products.take(6))
            ListTile(
              dense: true,
              leading: Text(p.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.north_west,
                  size: 16, color: IjwiColors.muted),
              onTap: () {
                _filters.product = p.name;
                _queryCtl.text = p.name;
                _queryCtl.selection =
                    TextSelection.collapsed(offset: _queryCtl.text.length);
                _fetchResults();
              },
            ),
        ],
        if (s.listings.isNotEmpty) ...[
          const _SuggestionHeader('Listings'),
          for (final l in s.listings.take(5))
            ListTile(
              dense: true,
              leading: Text(l.productEmoji, style: const TextStyle(fontSize: 20)),
              title: Text(l.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${l.productName} · ${l.locationLabel.isNotEmpty ? l.locationLabel : 'Marketplace'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              onTap: () => context.push('/listing/${l.id}'),
            ),
        ],
        if (s.farmers.isNotEmpty) ...[
          const _SuggestionHeader('Farmers'),
          for (final f in s.farmers.take(5))
            ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: IjwiColors.greenLight,
                child: Icon(Icons.person, size: 18, color: IjwiColors.green),
              ),
              title: Text(f.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(f.region ?? 'Farmer',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => context.push('/community/farmer/${f.id}'),
            ),
        ],
        if (s.groups.isNotEmpty) ...[
          const _SuggestionHeader('Groups'),
          for (final g in s.groups.take(5))
            ListTile(
              dense: true,
              leading: const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE8EEFB),
                child:
                    Icon(Icons.groups_2, size: 18, color: IjwiColors.blue),
              ),
              title: Text(g.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${g.memberCount} members',
                  style: const TextStyle(fontSize: 12)),
              onTap: () => context.push('/community/group/${g.id}'),
            ),
        ],
        if (s.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No suggestions yet — press search to see all results.',
                style: TextStyle(color: IjwiColors.muted)),
          ),
      ],
    );
  }
}

class _SuggestionHeader extends StatelessWidget {
  const _SuggestionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: IjwiColors.green),
          textAlign: TextAlign.left),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final _Filters initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _Filters f = _Filters()
    ..product = widget.initial.product
    ..category = widget.initial.category
    ..region = widget.initial.region
    ..qualityGrade = widget.initial.qualityGrade
    ..listingType = widget.initial.listingType
    ..minPriceMinor = widget.initial.minPriceMinor
    ..maxPriceMinor = widget.initial.maxPriceMinor
    ..minQuantity = widget.initial.minQuantity
    ..negotiable = widget.initial.negotiable
    ..verified = widget.initial.verified
    ..sort = widget.initial.sort;
  final _regionCtl = TextEditingController();
  final _minPriceCtl = TextEditingController();
  final _maxPriceCtl = TextEditingController();
  final _minQtyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _regionCtl.text = widget.initial.region ?? '';
    _minPriceCtl.text = widget.initial.minPriceMinor == null
        ? ''
        : (widget.initial.minPriceMinor! / 100).toStringAsFixed(0);
    _maxPriceCtl.text = widget.initial.maxPriceMinor == null
        ? ''
        : (widget.initial.maxPriceMinor! / 100).toStringAsFixed(0);
    _minQtyCtl.text = widget.initial.minQuantity?.toStringAsFixed(0) ?? '';
  }

  @override
  void dispose() {
    _regionCtl.dispose();
    _minPriceCtl.dispose();
    _maxPriceCtl.dispose();
    _minQtyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Spacer(),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                TextField(
                  controller: _regionCtl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Location / region'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _minPriceCtl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Min price (RWF)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxPriceCtl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Max price (RWF)'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _minQtyCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Min quantity (kg)'),
                ),
                const SizedBox(height: 14),
                const Text('Quality grade',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final g in ['UNGRADED', 'STANDARD', 'GRADE_B', 'GRADE_A', 'PREMIUM'])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(g.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 12)),
                        selected: f.qualityGrade == g,
                        onSelected: (_) => setState(
                            () => f.qualityGrade = f.qualityGrade == g ? null : g),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Listing type',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in ['FIXED_PRICE', 'NEGOTIABLE', 'AUCTION', 'FORWARD_CONTRACT', 'GROUP_SALE'])
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(t.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 12)),
                        selected: f.listingType == t,
                        onSelected: (_) => setState(
                            () => f.listingType = f.listingType == t ? null : t),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Price negotiable',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  value: f.negotiable,
                  onChanged: (v) => setState(() => f.negotiable = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Verified sellers only',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  value: f.verified,
                  onChanged: (v) => setState(() => f.verified = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context, _buildResult());
                  },
                  child: const Text('Apply filters'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  _Filters _buildResult() {
    f
      ..region = _regionCtl.text.trim().isEmpty ? null : _regionCtl.text.trim()
      ..minPriceMinor =
          (double.tryParse(_minPriceCtl.text.trim()) ?? 0) <= 0
              ? null
              : ((double.tryParse(_minPriceCtl.text.trim()) ?? 0) * 100).round()
      ..maxPriceMinor =
          (double.tryParse(_maxPriceCtl.text.trim()) ?? 0) <= 0
              ? null
              : ((double.tryParse(_maxPriceCtl.text.trim()) ?? 0) * 100).round()
      ..minQuantity = (double.tryParse(_minQtyCtl.text.trim()) ?? 0) <= 0
          ? null
          : double.tryParse(_minQtyCtl.text.trim());
    return f;
  }
}