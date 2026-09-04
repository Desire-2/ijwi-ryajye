import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../market/marketplace_models.dart';
import '../market/marketplace_repository.dart';
import 'listing_wizard_engine.dart';

/// A photo the seller picked for this listing. Uploads happen right after
/// picking so each file shows its own state and can retry independently.
class _MediaItem {
  _MediaItem(this.path);

  final String path;
  String? storageKey;
  double progress = 0;
  bool uploading = false;
  bool failed = false;
}

/// Universal "Create Listing" wizard — ONE listing engine for the whole
/// agricultural economy (produce, livestock, inputs, equipment, rentals,
/// services, transport, storage). Categories and products come from the
/// backend; the wizard only renders the per-kind extra fields on top.
class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key, this.initialListingId});

  /// Resume/continue an existing DRAFT listing.
  final String? initialListingId;

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  static const _steps = [
    'Offer', 'Details', 'Quantity', 'Pricing', 'Location', 'Photos', 'Review',
  ];

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _reserve = TextEditingController();
  final _increment = TextEditingController();
  final _minOrder = TextEditingController();
  final _variety = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();

  /// Per-kind dynamic attribute values (keyed by engine field id).
  final Map<String, dynamic> _attrs = {};

  final _pendingMedia = <_MediaItem>[];

  // ---- catalog ----
  List<Category>? _categories;
  List<ProductSummary> _products = const [];
  ProductSummary? _product;
  Category? _category;
  List<UnitOption> _units = const [];
  String? _selectedCategorySlug;

  // ---- form state ----
  int _step = 0;
  bool _busy = false;
  String? _error;
  bool _loading = true;

  // ---- choices ----
  String _unitCode = 'kg';
  String _quality = 'UNGRADED';
  String? _productionMethod;
  String? _certification;
  final Set<String> _delivery = {'PICKUP', 'NEGOTIABLE'};
  bool _negotiable = false;
  String _mode = 'FIXED_PRICE'; // FIXED_PRICE | AUCTION
  DateTime? _availableFrom;
  DateTime? _expectedHarvest;
  DateTime? _auctionEnd;
  String? _priceAdvice;
  Timer? _adviceDebounce;

  // ---- lifecycle ----
  String? _listingId; // set once a draft exists server-side
  List<String> _serverMediaKeys = const []; // media already attached server-side
  Listing? _published;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _adviceDebounce?.cancel();
    _title.dispose();
    _description.dispose();
    _qty.dispose();
    _price.dispose();
    _reserve.dispose();
    _increment.dispose();
    _minOrder.dispose();
    _variety.dispose();
    _region.dispose();
    _district.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- loading

  Future<void> _bootstrap() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.categories(),
        repo.units(),
        repo.products(),
        _loadUserRegion(),
      ]);
      final cats = results[0] as List<Category>;
      final units = results[1] as List<UnitOption>;
      final products = results[2] as List<ProductSummary>;
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _units = units;
        _products = products;
        _loading = false;
      });
      _pickUnitIfMissing(units);
      if (widget.initialListingId != null) {
        await _loadDraft(widget.initialListingId!, repo, products);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorMessage(e);
      });
    }
  }

  Future<void> _loadUserRegion() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/users/me');
      final u = res['user'] as Map<String, dynamic>? ?? const {};
      final region = u['region'] as String?;
      final district = u['district'] as String?;
      if (!mounted) return;
      setState(() {
        if (region != null && region.isNotEmpty) _region.text = region;
        if (district != null && district.isNotEmpty) _district.text = district;
      });
    } catch (_) {
      // prefilling location is best-effort
    }
  }

  void _pickUnitIfMissing(List<UnitOption> units) {
    if (units.isEmpty) return;
    if (!units.any((u) => u.code == _unitCode)) {
      _unitCode = units.first.code;
    }
  }

  Future<void> _loadDraft(String id, MarketplaceRepository repo,
      List<ProductSummary> products) async {
    try {
      final (listing, media) = await repo.listing(id);
      if (!mounted) return;
      // Find the matching product in the catalog so the wizard shows the kind.
      ProductSummary? match;
      for (final p in products) {
        if (p.id == listing.productId) {
          match = p;
          break;
        }
      }
      final catSlug = match?.categorySlug;
      setState(() {
        _listingId = id;
        if (match != null) {
          _product = match;
          _category = _categories
              ?.where((c) => c.slug == catSlug)
              .firstOrNull;
          _selectedCategorySlug = catSlug;
        }
        _title.text = listing.title;
        _description.text = listing.description;
        _qty.text = _trimNum(listing.quantityValue);
        _unitCode = listing.unitCode;
        _quality = listing.qualityGrade;
        _productionMethod = listing.productionMethod;
        _certification = listing.certification.isEmpty
            ? null
            : listing.certification;
        _region.text = listing.locationRegion ?? '';
        _district.text = listing.locationDistrict ?? '';
        _delivery
          ..clear()
          ..addAll(listing.deliveryOptions);
        _negotiable = listing.negotiable;
        _mode = listing.isAuction ? 'AUCTION' : 'FIXED_PRICE';
        _variety.text = listing.variety;
        _attrs
          ..clear()
          ..addAll(listing.attributes);
        _serverMediaKeys = media.map((m) => m.storageKey).toList();
        final price = listing.priceMinor;
        if (price != null && !listing.isAuction) {
          _price.text = _trimMoney(price);
        }
        if (price != null && listing.isAuction) {
          _reserve.text = _trimMoney(price);
        }
        _auctionEnd = DateTime.tryParse(listing.auctionEndAt ?? '');
        _expectedHarvest = DateTime.tryParse(listing.expectedHarvestDate ?? '');
        _step = match == null ? 0 : 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  // ------------------------------------------------------------- computed

  bool get _isResume => _listingId != null;

  CategoryProfile get _profile =>
      profileFor(_product?.categorySlug ?? _selectedCategorySlug);

  bool get _hasProduct => _product != null;

  double? get _qtyValue => double.tryParse(_qty.text.trim());

  bool get _qtyValid => (_qtyValue ?? 0) > 0 && _unitCode.isNotEmpty;

  int? get _priceMinor {
    final v = num.tryParse(_price.text.trim());
    if (v == null) return null;
    return (v * 100).round();
  }

  bool get _priceValid {
    if (_mode == 'AUCTION') return true;
    return (_priceMinor ?? 0) > 0;
  }

  bool get _auctionValid =>
      _mode != 'AUCTION' || (_auctionEnd != null && _auctionEnd!.isAfter(DateTime.now()));

  bool get _canSaveDraft => _hasProduct && _qtyValid && !_busy;

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _hasProduct;
      case 1:
        return true;
      case 2:
        return _qtyValid;
      case 3:
        return _priceValid && _auctionValid;
      case 4:
        return _delivery.isNotEmpty;
      default:
        return _qtyValid && _priceValid && _auctionValid;
    }
  }

  bool get _isProduce => _profile.showQuality;

  // --------------------------------------------------------------- actions

  Future<void> _saveDraft({bool publish = false}) async {
    if (!_canSaveDraft) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final payload = _buildPayload(state: 'DRAFT');
      if (_listingId == null) {
        // Fresh draft — created with any media picked so far. Those keys are
        // now attached server-side, so they must not be re-sent later.
        final created = await repo.createListing(payload);
        _listingId = created.id;
        final sentKeys = (payload['media'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((m) => m['storage_key'] as String)
            .toList();
        setState(() {
          _serverMediaKeys = [..._serverMediaKeys, ...sentKeys];
        });
      } else {
        await repo.updateListing(_listingId!, _buildPatchPayload());
      }
      await _attachPendingMedia(repo);
      if (publish) {
        if (mounted) setState(() => _busy = true);
        final live = await repo.publishListing(_listingId!);
        if (!mounted) return;
        setState(() => _published = live);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🎉 Your listing is live!'),
          backgroundColor: IjwiColors.green,
        ));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Draft saved — you can finish it anytime.'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Uploaded-but-unattached photos go to the server once a draft exists.
  Future<void> _attachPendingMedia(MarketplaceRepository repo) async {
    final keys = _pendingMedia
        .where((m) => m.storageKey != null && !_serverMediaKeys.contains(m.storageKey))
        .map((m) => {'storage_key': m.storageKey})
        .toList();
    if (keys.isEmpty || _listingId == null) return;
    await repo.attachListingMedia(_listingId!, keys);
    setState(() {
      _serverMediaKeys = [
        ..._serverMediaKeys,
        ...keys.map((k) => k['storage_key'] as String),
      ];
    });
  }

  Map<String, dynamic> _buildPayload({required String state}) {
    final payload = <String, dynamic>{
      'state': state,
      'product_id': _product!.id,
      'title': _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : _defaultTitle(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      'quantity_value': _qtyValue,
      'available_quantity': _qtyValue,
      'unit_code': _unitCode,
      'location_region': _region.text.trim().isEmpty ? null : _region.text.trim(),
      if (_district.text.trim().isNotEmpty) 'location_district': _district.text.trim(),
      'delivery_options': _delivery.join(','),
      'negotiable': _negotiable,
      'listing_type': _mode,
      'currency_code': 'RWF',
      'price_type': 'PER_UNIT',
      if (_isProduce && _quality != 'UNGRADED') 'quality_grade': _quality,
      if (_productionMethod != null) 'production_method': _productionMethod,
      if (_certification != null) 'certification': _certification,
      if (_variety.text.trim().isNotEmpty) 'variety': _variety.text.trim(),
      if (_expectedHarvest != null)
        'expected_harvest_date': _dateOnly(_expectedHarvest!),
      if (_availableFrom != null) 'available_from': _dateOnly(_availableFrom!),
      if (_minOrder.text.trim().isNotEmpty)
        'minimum_order_value': double.tryParse(_minOrder.text.trim()) ?? 0,
      if (_mode == 'AUCTION') ..._auctionPayload(),
    };
    if (_mode != 'AUCTION') {
      if (_priceValid) payload['price_minor'] = _priceMinor;
    } else {
      final start = _priceMinor;
      if (start != null && start > 0) payload['price_minor'] = start;
    }
    final attrs = _buildAttributes();
    if (attrs.isNotEmpty) payload['attributes'] = attrs;
    final keys = _pendingMedia
        .where((m) => m.storageKey != null)
        .map((m) => {'storage_key': m.storageKey});
    if (state == 'DRAFT' && _listingId == null) {
      payload['media'] = keys.toList();
    }
    payload.removeWhere((k, v) => v == null);
    return payload;
  }

  Map<String, dynamic> _buildPatchPayload() {
    final draft = _buildPayload(state: 'DRAFT');
    draft.remove('media');
    return draft;
  }

  Map<String, dynamic> _auctionPayload() => {
        if (_auctionEnd != null)
          'auction_end_at': _auctionEnd!.toUtc().toIso8601String(),
        if (_reserve.text.trim().isNotEmpty)
          'reserve_price_minor': (num.tryParse(_reserve.text.trim()) ?? 0) * 100,
        'min_bid_increment_minor':
            ((num.tryParse(_increment.text.trim()) ?? 1) * 100).round(),
      };

  Map<String, dynamic> _buildAttributes() {
    final out = <String, dynamic>{};
    for (final f in _profile.fields) {
      final v = _attrs[f.key];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      // Money-ish attributes are typed in whole RWF and stored in minor units.
      if (f.key == 'deposit_rwf' && v is num) {
        out[f.key] = (v * 100).round();
      } else {
        out[f.key] = v;
      }
    }
    return out;
  }

  String _defaultTitle() {
    final p = _product!;
    final q = _qtyValue ?? 0;
    return '${p.name}${q > 0 ? ' — ${_trimNum(q)} $_unitCode' : ''}';
  }

  // -------------------------------------------------------------- rendering

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isResume ? 'Edit draft' : 'Create listing'),
        actions: [
          if (_canSaveDraft)
            TextButton(
              onPressed: _busy ? null : _saveDraft,
              child: const Text('Save draft'),
            ),
        ],
      ),
      body: _published != null
          ? _successBody()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && !_hasProduct
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: () {
                                setState(() {
                                  _error = null;
                                  _loading = true;
                                });
                                _bootstrap();
                              },
                              child: const Text('Retry')),
                        ]),
                      ),
                    )
                  : _wizardBody(),
    );
  }

  Widget _wizardBody() {
    return Column(children: [
      _progressBar(),
      Expanded(child: _buildStep()),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
          child: Text(_error!,
              style: const TextStyle(color: IjwiColors.red, fontSize: 13)),
        ),
      _bottomBar(),
    ]);
  }

  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Container(
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i <= _step
                      ? IjwiColors.green
                      : const Color(0xFFD7E2DA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${_isResume ? 'Editing draft' : 'New listing'} · '
            '${_steps[_step]} (${_step + 1}/${_steps.length})',
            style: const TextStyle(color: IjwiColors.muted, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Row(children: [
          if (_step > 0)
            OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _step--),
              child: const Text('Back'),
            ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(150, 48)),
            onPressed: _busy || !_canContinue ? null : _nextOrFinish,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_step == _steps.length - 1 ? 'Publish listing' : 'Next'),
          ),
        ]),
      ),
    );
  }

  void _nextOrFinish() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      if (_step == 3) _fetchPriceAdvice();
    } else {
      _saveDraft(publish: true);
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _offerStep();
      case 1:
        return _detailsStep();
      case 2:
        return _quantityStep();
      case 3:
        return _pricingStep();
      case 4:
        return _locationStep();
      case 5:
        return _photosStep();
      default:
        return _reviewStep();
    }
  }

  // -------------------------------------------------------------- step: 0

  Widget _offerStep() {
    final cats = _categories ?? const <Category>[];
    final cat = cats
        .where((c) => c.slug == _selectedCategorySlug)
        .firstOrNull;
    final visible = _selectedCategorySlug == null
        ? _products
        : _products.where((p) => p.categorySlug == _selectedCategorySlug).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Text('What are you offering?',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('All'),
                selected: _selectedCategorySlug == null,
                onSelected: (_) => setState(() => _selectedCategorySlug = null),
              ),
            ),
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Text(c.icon),
                  label: Text(c.name),
                  selected: _selectedCategorySlug == c.slug,
                  onSelected: (_) =>
                      setState(() => _selectedCategorySlug = c.slug),
                ),
              ),
          ],
        ),
      ),
      if (cat != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Text(
            _profile.guidance.isEmpty
                ? 'Choose the exact item you are offering.'
                : _profile.guidance,
            style: const TextStyle(color: IjwiColors.muted, fontSize: 12.5),
          ),
        ),
      const SizedBox(height: 6),
      Expanded(
        child: visible.isEmpty
            ? const Center(child: Text('No items in this category yet.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final p = visible[i];
                  final selected = _product?.id == p.id;
                  return Card(
                    color: selected ? IjwiColors.greenLight : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(IjwiRadius.sm),
                      side: selected
                          ? const BorderSide(color: IjwiColors.green, width: 1.6)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      leading: Text(p.emoji, style: const TextStyle(fontSize: 26)),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${p.categoryName ?? ''} · per ${p.defaultUnit}'),
                      trailing: selected
                          ? const Icon(Icons.check_circle,
                              color: IjwiColors.green)
                          : null,
                      onTap: () => setState(() {
                        _product = p;
                        _unitCode = p.defaultUnit;
                        if (_title.text.isEmpty) {
                          _title.text = p.name;
                        }
                        if (_category == null) _category = cat;
                      }),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ------------------------------------------------------------ step: 1

  Widget _detailsStep() {
    final f = _profile.fields;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        if (_profile.guidance.isNotEmpty)
          _infoCard(_profile.guidance),
        TextField(
          controller: _title,
          maxLength: 90,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Listing title',
            hintText: 'e.g. Grade A Kinigi potatoes, fresh harvest',
            counterText: '',
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Tell buyers what makes this worth their time…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        if (f.isNotEmpty) ...[
          Text('Category details',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 8),
          for (final field in f) _attrField(field),
          const SizedBox(height: 8),
        ],
        if (_isProduce) ...[
          _sectionTitle('Quality'),
          if (_profile.graded) ...[
            DropdownButtonFormField<String>(
              initialValue: _quality,
              decoration: const InputDecoration(labelText: 'Quality grade'),
              items: [
                for (final g in qualityGrades)
                  DropdownMenuItem(value: g, child: Text(gradeLabel(g))),
              ],
              onChanged: (v) => setState(() => _quality = v ?? 'UNGRADED'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _productionMethod ?? '',
              decoration:
                  const InputDecoration(labelText: 'Production method (optional)'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Not stated')),
                for (final m in productionMethods)
                  DropdownMenuItem(
                      value: m,
                      child: Text(m.replaceAll('_', ' ').toLowerCase().capFirst())),
              ],
              onChanged: (v) => setState(
                  () => _productionMethod = v == '' ? null : v),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _variety,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Variety (optional)',
              hintText: 'e.g. Kinigi, Longe 5, Hass',
            ),
          ),
          if (_profile.certifications) ...[
            const SizedBox(height: 10),
            const Text('Certification',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 6,
              children: [
                for (final c in certifications)
                  ChoiceChip(
                    label: Text(c),
                    selected: _certification == c,
                    onSelected: (on) =>
                        setState(() => _certification = on ? c : null),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _attrField(WizardField field) {
    switch (field.type) {
      case WizardFieldType.select:
        final value = _attrs[field.key] as String?;
        final options = field.options;
        final selected = options.contains(value)
            ? value
            : (field.required ? options.firstOrNull : null);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: field.required ? null : 'Select…',
            ),
            items: [
              for (final o in field.options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => setState(() {
              if (v != null) _attrs[field.key] = v;
            }),
          ),
        );
      case WizardFieldType.number:
        final value = _attrs[field.key] as num?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: TextEditingController(
                text: value == null ? '' : _trimNum(value.toDouble())),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: field.label,
              suffixText: field.suffix,
              helperText: field.hint,
            ),
            onChanged: (t) {
              final n = num.tryParse(t.trim());
              setState(() {
                if (n == null) {
                  _attrs.remove(field.key);
                } else {
                  _attrs[field.key] = n;
                }
              });
            },
          ),
        );
      default:
        final value = _attrs[field.key] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: TextEditingController(text: value ?? ''),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: field.label + (field.required ? ' *' : ''),
              hintText: field.hint,
            ),
            onChanged: (t) => setState(() {
              if (t.trim().isEmpty) {
                _attrs.remove(field.key);
              } else {
                _attrs[field.key] = t.trim();
              }
            }),
          ),
        );
    }
  }

  // ----------------------------------------------------------- step: 2

  Widget _quantityStep() {
    final units = _units;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Text('How much are you offering?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                  labelText: 'Quantity', counterText: ''),
              maxLength: 9,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: units.any((u) => u.code == _unitCode)
                  ? _unitCode
                  : (units.firstOrNull?.code ?? 'kg'),
              decoration: const InputDecoration(labelText: 'Unit'),
              items: [
                for (final u in units)
                  DropdownMenuItem(
                      value: u.code,
                      child: Text('${u.code} — ${u.label}')),
              ],
              onChanged: (v) => setState(() {
                if (v != null) _unitCode = v;
                _fetchPriceAdvice();
              }),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Text('Pricing basis: RWF per $_unitCode',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Buyers pay the price you set per unit of this measure.',
            style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
        if (_profile.harvestAware) ...[
          const SizedBox(height: 18),
          _dateTile(
            label: 'Available from',
            value: _availableFrom,
            onPick: (d) => setState(() => _availableFrom = d),
            clear: () => setState(() => _availableFrom = null),
          ),
          _dateTile(
            label: 'Expected harvest date',
            value: _expectedHarvest,
            onPick: (d) => setState(() => _expectedHarvest = d),
            clear: () => setState(() => _expectedHarvest = null),
            hint: 'Use this when selling a future harvest (pre-order).',
          ),
        ],
        if (_profile.graded) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _minOrder,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Minimum order (optional)',
              suffixText: _unitCode,
              helperText: 'Leave empty for any amount',
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPick,
    required VoidCallback clear,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(value == null ? label : '$label: ${_fmtDate(value)}',
              style: TextStyle(
                  fontWeight:
                      value == null ? FontWeight.w500 : FontWeight.w700)),
          subtitle: hint == null ? null : Text(hint),
          trailing: value == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: clear,
                ),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (picked != null) onPick(picked);
          },
        ),
        const Divider(height: 1),
      ]),
    );
  }

  // ----------------------------------------------------------- step: 3

  Widget _pricingStep() {
    final unit = _unitCode.isEmpty ? 'unit' : _unitCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'FIXED_PRICE', label: Text('Fixed price')),
            ButtonSegment(value: 'AUCTION', label: Text('Auction')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 18),
        if (_mode == 'AUCTION') ...[
          const Text('Auction',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Buyers bid against each other until the end time.',
              style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
          const SizedBox(height: 14),
          _priceField(
            label: 'Starting price (optional)',
            suffix: 'RWF per $unit',
            controller: _price,
          ),
          const SizedBox(height: 10),
          _priceField(
            label: 'Reserve price (optional)',
            suffix: 'RWF',
            controller: _reserve,
            hint: 'Lowest price you will accept — never revealed to bidders',
          ),
          const SizedBox(height: 10),
          _priceField(
            label: 'Minimum bid increment',
            suffix: 'RWF',
            controller: _increment,
            hint: 'Default 1 RWF',
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(_auctionEnd == null
                ? 'End time *'
                : 'Ends: ${_fmtDate(_auctionEnd!)} '
                    '${_fmtTime(_auctionEnd!)}'),
            subtitle: const Text('Auction end is enforced by server time'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickAuctionEnd(),
          ),
          const SizedBox(height: 12),
        ] else ...[
          _priceField(
            label: 'Your price',
            suffix: 'RWF per $unit',
            controller: _price,
            hint: 'e.g. 450 means RWF 450 per $unit',
          ),
          if (_priceAdvice != null) ...[
            const SizedBox(height: 10),
            _infoCard(_priceAdvice!, tinted: true),
          ],
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accept offers / negotiate',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Buyers can send you offers below the price'),
            value: _negotiable,
            activeColor: IjwiColors.green,
            onChanged: (v) => setState(() => _negotiable = v),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _priceField({
    required String label,
    required String suffix,
    required TextEditingController controller,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: hint,
        prefixText: 'RWF ',
      ),
      onChanged: (_) {
        setState(() {});
        if (_mode != 'AUCTION') _schedulePriceAdvice();
      },
    );
  }

  void _schedulePriceAdvice() {
    _adviceDebounce?.cancel();
    _adviceDebounce = Timer(const Duration(milliseconds: 700), _fetchPriceAdvice);
  }

  Future<void> _fetchPriceAdvice() async {
    final minor = _priceMinor;
    if (_product == null || minor == null || minor <= 0) return;
    if (_unitCode != 'kg') return; // advisory data is quoted per kg
    try {
      final res = await ref.read(marketplaceRepositoryProvider).priceAdvice(
            productId: _product!.id,
            region: _region.text.trim().isEmpty ? null : _region.text.trim(),
            priceMinor: minor,
          );
      final a = res['advisor'] as Map<String, dynamic>?;
      final range = a?['observed_range_minor'];
      if (!mounted || range is! List || range.length != 2) return;
      final low = (range[0] as num).toInt();
      final high = (range[1] as num).toInt();
      final suggestion = a?['suggestion'] as String?;
      setState(() {
        _priceAdvice = 'Observed market range: '
            '${formatRwf(low)}–${formatRwf(high)} per kg'
            '${suggestion != null ? ' · $suggestion' : ''}';
      });
    } catch (_) {
      // advisory is best-effort
    }
  }

  Future<void> _pickAuctionEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _auctionEnd ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _auctionEnd ?? DateTime.now().add(const Duration(days: 3))),
    );
    if (time == null || !mounted) return;
    setState(() => _auctionEnd =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  // ---------------------------------------------------------- step: 4

  Widget _locationStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Text('Where is it?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Buyers search by region — an approximate location keeps you safe.',
            style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
        const SizedBox(height: 16),
        TextField(
          controller: _region,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Region / province',
              hintText: 'e.g. Northern'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _district,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'District (optional)',
              hintText: 'e.g. Musanze'),
        ),
        const SizedBox(height: 18),
        Text('How will buyers receive it?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (code, label) in deliveryOptions)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(label),
            value: _delivery.contains(code),
            onChanged: (on) => setState(() {
              if (on == true) {
                _delivery.add(code);
              } else {
                _delivery.remove(code);
              }
            }),
          ),
        const SizedBox(height: 16),
        const Text('Delivery prices are quoted by the seller or logistics partner — never entered here.',
            style: TextStyle(color: IjwiColors.muted, fontSize: 12)),
      ],
    );
  }

  // ---------------------------------------------------------- step: 5

  Widget _photosStep() {
    final hasExisting = _serverMediaKeys.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Text('Photos',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Photos make listings sell faster. The first photo is the cover.',
            style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
            onPressed: _busy ? null : _pickFromGallery,
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Camera'),
            onPressed: _busy ? null : _takePhoto,
          ),
        ]),
        if (hasExisting) ...[
          const SizedBox(height: 8),
          Text('${_serverMediaKeys.length} photo(s) already attached',
              style: const TextStyle(
                  color: IjwiColors.muted, fontSize: 12.5)),
        ],
        if (_pendingMedia.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < _pendingMedia.length; i++)
            _mediaTile(_pendingMedia[i], i),
        ],
        if (_pendingMedia.isEmpty && !hasExisting)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F2),
                borderRadius: BorderRadius.circular(IjwiRadius.sm),
                border: Border.all(color: const Color(0xFFD7E2DA)),
              ),
              child: const Center(
                  child: Text('No photos yet — you can publish without them')),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _pickFromGallery() async {
    final files = await ImagePicker().pickMultiImage(
        limit: 6 - _pendingMedia.length - _serverMediaKeys.length);
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        _pendingMedia.add(_MediaItem(f.path));
      }
    });
    for (final item in _pendingMedia) {
      if (!item.uploading && item.storageKey == null && !item.failed) {
        _upload(item);
      }
    }
  }

  Future<void> _takePhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) return;
    setState(() => _pendingMedia.add(_MediaItem(f.path)));
    _upload(_pendingMedia.last);
  }

  Future<void> _upload(_MediaItem item) async {
    setState(() {
      item.uploading = true;
      item.failed = false;
      item.progress = 0;
    });
    try {
      final key = await ref
          .read(marketplaceRepositoryProvider)
          .uploadListingImage(item.path, onProgress: (f) {
        if (mounted) setState(() => item.progress = f);
      });
      if (!mounted) return;
      setState(() {
        item.storageKey = key;
        item.uploading = false;
        item.progress = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        item.uploading = false;
        item.failed = true;
      });
    }
  }

  Widget _mediaTile(_MediaItem item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(item.path),
                width: 64, height: 64, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 64,
                    color: const Color(0xFFE4ECE7),
                    child: const Icon(Icons.image_outlined))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(index == 0 ? 'Cover photo' : 'Photo ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (item.uploading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: item.progress, minHeight: 6),
                    ),
                    const SizedBox(height: 2),
                    Text('Uploading ${(item.progress * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 11, color: IjwiColors.muted)),
                  ] else if (item.failed)
                    Text('Upload failed — tap retry',
                        style: const TextStyle(
                            fontSize: 12, color: IjwiColors.red))
                  else
                    Text('Ready',
                        style: const TextStyle(
                            fontSize: 12, color: IjwiColors.greenDark)),
                ]),
          ),
          IconButton(
            tooltip: 'Move earlier',
            icon: const Icon(Icons.arrow_back),
            onPressed: index == 0 || item.uploading
                ? null
                : () => setState(() => _pendingMedia
                    .insert(index - 1, _pendingMedia.removeAt(index))),
          ),
          if (item.failed)
            IconButton(
              tooltip: 'Retry upload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _upload(item),
            ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _pendingMedia.removeAt(index)),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------- step: 6

  Widget _reviewStep() {
    final attrs = _buildAttributes();
    final photoCount = _pendingMedia.length + _serverMediaKeys.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('${_product?.emoji ?? ''} ',
                        style: const TextStyle(fontSize: 24)),
                    Expanded(
                      child: Text(
                          _title.text.trim().isNotEmpty
                              ? _title.text.trim()
                              : _defaultTitle(),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                  if (_description.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_description.text.trim(),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: IjwiColors.muted)),
                    ),
                  const Divider(height: 22),
                  _row('Offering', kindLabel(_profile.kind)),
                  _row('Item', _product?.name ?? ''),
                  _row('Quantity',
                      '${_trimNum(_qtyValue ?? 0)} $_unitCode'),
                  if (_isProduce && _quality != 'UNGRADED')
                    _row('Quality', gradeLabel(_quality)),
                  if (_variety.text.trim().isNotEmpty)
                    _row('Variety', _variety.text.trim()),
                  for (final f in _profile.fields)
                    if (attrs.containsKey(f.key))
                      _row(f.displayLabel,
                          formatAttributeValue(f.key, attrs[f.key])),
                  if (_mode == 'AUCTION')
                    _row('Type', 'Auction · ends ${_auctionEnd == null ? '?' : _fmtDate(_auctionEnd!)} ${_auctionEnd == null ? '' : _fmtTime(_auctionEnd!)}')
                  else ...[
                    _row('Price',
                        '${_priceMinor == null ? 'Not set' : '${formatRwf(_priceMinor!)} per $_unitCode'}'),
                    if (_negotiable)
                      _row('Negotiable', 'Open to offers'),
                  ],
                  if (_expectedHarvest != null)
                    _row('Expected harvest', _fmtDate(_expectedHarvest!)),
                  if (_availableFrom != null)
                    _row('Available from', _fmtDate(_availableFrom!)),
                  if (_delivery.isNotEmpty)
                    _row('Delivery',
                        _delivery.map((c) {
                          for (final (code, label) in deliveryOptions) {
                            if (code == c) return label;
                          }
                          return c;
                        }).join(', ')),
                  if (_region.text.trim().isNotEmpty)
                    _row('Location',
                        [_district.text.trim(), _region.text.trim()]
                            .where((s) => s.isNotEmpty)
                            .join(', ')),
                  _row('Photos', photoCount == 0 ? 'None' : '$photoCount'),
                ]),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy || !_canSaveDraft
                  ? null
                  : () => _saveDraft(publish: false),
              child: const Text('Save draft'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _busy || !_canContinue ? null : _publishFromReview,
              child: Text(_busy ? 'Publishing…' : 'Publish listing'),
            ),
          ),
        ]),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Center(
                child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _publishFromReview() async {
    // Make sure the photo step errors surface instead of silently publishing.
    final failed = _pendingMedia.where((m) => m.failed).toList();
    if (failed.isNotEmpty) {
      setState(() => _error =
          '${failed.length} photo upload(s) failed — retry or remove them first.');
      setState(() => _step = 5);
      return;
    }
    await _saveDraft(publish: true);
  }

  Widget _successBody() {
    final l = _published!;
    final pm = l.priceMinor;
    final priceNote = pm == null
        ? ''
        : ' · ${formatRwf(pm)} per ${l.unitCode}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
          const Text('🎉', style: TextStyle(fontSize: 54)),
          const SizedBox(height: 12),
          const Text('Your listing is live!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${l.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${_trimNum(l.quantityValue)} ${l.unitCode}$priceNote',
              style: const TextStyle(color: IjwiColors.muted)),
          const SizedBox(height: 10),
          const Text('Buyers can now find your offer in the marketplace.',
              textAlign: TextAlign.center,
              style: TextStyle(color: IjwiColors.muted)),
          const SizedBox(height: 26),
          FilledButton.icon(
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('View listing'),
            onPressed: () {
              context.push('/listing/${l.id}');
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Done'),
            onPressed: () => context.pop(),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Create another listing'),
            onPressed: () {
              setState(() {
                _published = null;
                _listingId = null;
                _pendingMedia.clear();
                _serverMediaKeys = const [];
                _price.clear();
                _reserve.clear();
                _qty.text = '';
                _title.clear();
                _product = null;
                _step = 0;
              });
            },
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------- helpers

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _infoCard(String message, {bool tinted = false}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tinted ? const Color(0xFFE8EEFB) : const Color(0xFFEFF5F0),
          borderRadius: BorderRadius.circular(IjwiRadius.sm),
        ),
        child: Text(message,
            style: TextStyle(
                fontSize: 12.5,
                color: tinted ? IjwiColors.blue : IjwiColors.muted)),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 130,
                  child: Text(k,
                      style: const TextStyle(color: IjwiColors.muted))),
              Expanded(
                  child: Text(v,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
      );

  String _trimNum(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _trimMoney(int minor) {
    final major = minor / 100;
    return major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${h}:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

extension _CapFirst on String {
  String capFirst() =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);
}
