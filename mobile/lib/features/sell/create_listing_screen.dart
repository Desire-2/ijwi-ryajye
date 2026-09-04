import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';

class _ProductOption {
  _ProductOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        emoji = j['emoji'] as String? ?? '🌱',
        slug = j['slug'] as String? ?? '';

  final String id;
  final String name;
  final String emoji;
  final String slug;
}

class _FarmOption {
  _FarmOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? 'My Farm',
        region = j['region'] as String?;

  final String id;
  final String name;
  final String? region;
}

/// Farmer-first "Sell Your Harvest" wizard.
/// Steps: product → quantity → price → details → review → publish.
/// Creates a farm automatically on first use (POST /farms).
class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _title = TextEditingController();
  final _qty = TextEditingController(text: '100');
  final _price = TextEditingController();
  final _region = TextEditingController();

  List<_ProductOption>? _products;
  List<_FarmOption>? _farms;
  _ProductOption? _product;
  _FarmOption? _farm;
  String _listingType = 'FIXED_PRICE';
  bool _negotiable = true;
  String _quality = 'UNGRADED';
  String _delivery = 'PICKUP,NEGOTIABLE';
  String? _priceAdvice;
  int _step = 0;
  bool _publishing = false;
  String? _error;

  static const _steps = ['Crop', 'Quantity', 'Price', 'Details', 'Review'];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _title.dispose();
    _qty.dispose();
    _price.dispose();
    _region.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final api = ref.read(apiClientProvider);
    try {
      final pRes = await api.getJson('/products', query: {'per_page': '200'});
      setState(() => _products = (pRes['items'] as List? ?? const [])
          .map((j) => _ProductOption.fromJson(j as Map<String, dynamic>))
          .toList());
    } catch (_) {}
    _fetchPriceAdvice();
    try {
      final fRes = await api.getJson('/farms');
      setState(() => _farms = (fRes['farms'] as List? ?? const [])
          .map((j) => _FarmOption.fromJson(j as Map<String, dynamic>))
          .toList());
    } catch (_) {}
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _product != null;
      case 1:
        return (double.tryParse(_qty.text.trim()) ?? 0) > 0;
      case 2:
        return (int.tryParse(_price.text.trim()) ?? 0) >= 0 &&
            _price.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _fetchPriceAdvice() async {
    if (_product == null || _price.text.trim().isEmpty) return;
    try {
      final res = await ref.read(apiClientProvider).getJson(
          '/price-advice',
          query: {
            'product_id': _product!.id,
            'price_minor': _price.text.trim(),
            'unit_code': 'kg',
          });
      final advice = res['advisor'] as Map<String, dynamic>?;
      final range = advice?['observed_range_minor'];
      if (range is List && range.length == 2) {
        final low = (range[0] as num).toInt();
        final high = (range[1] as num).toInt();
        setState(() => _priceAdvice =
            'Recent market range: ${(low / 100).toStringAsFixed(0)}–${(high / 100).toStringAsFixed(0)} RWF/kg'
            '${advice?['suggestion'] != null ? ' · ${advice!['suggestion']}' : ''}');
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    setState(() {
      _publishing = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      // Ensure a farm exists (backend requires farm_id for farmer listings
      // in most flows; create one lazily from the user's region).
      var farmId = _farm?.id;
      if (farmId == null) {
        final farmName = '${_product!.name} Farm';
        final f = await api.postJson('/farms', {
          'name': farmName,
          'country_code': 'RW',
          if (_region.text.trim().isNotEmpty) 'region': _region.text.trim(),
        });
        farmId = (f['farm'] as Map<String, dynamic>)['id'] as String;
      }

      final payload = <String, dynamic>{
        'product_id': _product!.id,
        'title': _title.text.trim().isNotEmpty
            ? _title.text.trim()
            : '${_product!.name} — ${_qty.text.trim()}${_unitLabel()}',
        'quantity_value': double.tryParse(_qty.text.trim()) ?? 0,
        'available_quantity': double.tryParse(_qty.text.trim()) ?? 0,
        'unit_code': 'kg',
        'price_minor': int.tryParse(_price.text.trim()) ?? 0,
        'listing_type': _listingType,
        'negotiable': _negotiable,
        'quality_grade': _quality,
        'delivery_options': _delivery,
        'location_region':
            _region.text.trim().isNotEmpty ? _region.text.trim() : null,
        'farm_id': farmId,
        if (_listingType == 'AUCTION')
          'auction_end_at': DateTime.now()
              .add(const Duration(days: 7))
              .toIso8601String(),
      }..removeWhere((k, v) => v == null);

      await api.postJson('/listings', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Listing published! Buyers can see it now.'),
          backgroundColor: IjwiColors.green));
      context.pop();
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  String _unitLabel() => _product?.slug == 'irish-potatoes' ? ' kg' : ' kg';

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 4 ? 'Review' : 'Sell Your Harvest'),
      ),
      body: Column(children: [
        // ---- progress ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
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
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text('Step ${_step + 1} of ${_steps.length} · ${_steps[_step]}',
                style: const TextStyle(color: IjwiColors.muted, fontSize: 12)),
          ]),
        ),
        Expanded(child: _buildStep()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Text(_error!,
                style: const TextStyle(color: IjwiColors.red)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: Row(children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('Back'),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
                onPressed:
                    !_canContinue || _publishing ? null : _nextOrPublish,
                child: _publishing
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_step == 4 ? tr('send') == 'Send' ? 'Publish' : tr('send') : 'Next'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _nextOrPublish() {
    if (_step < 4) {
      setState(() => _step++);
    } else {
      _publish();
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _productPicker();
      case 1:
        return _quantityStep();
      case 2:
        return _priceStep();
      case 3:
        return _detailsStep();
      default:
        return _reviewStep();
    }
  }

  Widget _productPicker() {
    if (_products == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(padding: const EdgeInsets.all(14), children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Text('What are you selling?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _products!
              .map((p) => ChoiceChip(
                    label: Text('${p.emoji} ${p.name}'),
                    selected: _product?.id == p.id,
                    selectedColor: IjwiColors.greenLight,
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _product?.id == p.id
                            ? IjwiColors.greenDark
                            : Colors.black87),
                    onSelected: (_) => setState(() => _product = p),
                  ))
              .toList()),
    ]);
  }

  Widget _quantityStep() {
    return ListView(padding: const EdgeInsets.all(22), children: [
      const Text('How much do you have?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 18),
      TextField(
        controller: _qty,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
            suffixText: 'kg', counterText: ''),
        maxLength: 9,
      ),
    ]);
  }

  Widget _priceStep() {
    return ListView(padding: const EdgeInsets.all(22), children: [
      const Text('Your price per kg?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('in RWF minor units — e.g. 45000 for 450 RWF/kg',
          style: const TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
      const SizedBox(height: 18),
      TextField(
        controller: _price,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(suffixText: 'minor'),
      ),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'FIXED_PRICE', label: Text('Fixed')),
          ButtonSegment(value: 'AUCTION', label: Text('Auction')),
        ],
        selected: {_listingType},
        onSelectionChanged: (s) => setState(() => _listingType = s.first),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Open to negotiation',
            style: TextStyle(fontWeight: FontWeight.w600)),
        value: _negotiable,
        activeColor: IjwiColors.green,
        onChanged: (v) => setState(() => _negotiable = v),
      ),
      if (_priceAdvice != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFE8EEFB),
                borderRadius: BorderRadius.circular(IjwiRadius.sm)),
            child: Text(_priceAdvice!,
                style: const TextStyle(fontSize: 12.5, color: IjwiColors.blue)),
          ),
        ),
    ]);
  }

  Widget _detailsStep() {
    return ListView(padding: const EdgeInsets.all(22), children: [
      const Text('Where is it?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      TextField(
        controller: _region,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Region / District'),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 90,
        decoration: const InputDecoration(
            labelText: 'Listing title (optional)',
            hintText: 'e.g. Fresh harvest, Grade A',
            counterText: ''),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _quality,
        decoration: const InputDecoration(labelText: 'Quality grade'),
        items: const [
          DropdownMenuItem(value: 'UNGRADED', child: Text('Any / ungraded')),
          DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
          DropdownMenuItem(value: 'GRADE_B', child: Text('Grade B')),
          DropdownMenuItem(value: 'GRADE_A', child: Text('Grade A')),
          DropdownMenuItem(value: 'PREMIUM', child: Text('Premium')),
        ],
        onChanged: (v) => setState(() => _quality = v ?? 'UNGRADED'),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _delivery,
        decoration: const InputDecoration(labelText: 'Delivery options'),
        items: const [
          DropdownMenuItem(
              value: 'PICKUP,NEGOTIABLE', child: Text('Pickup or negotiable')),
          DropdownMenuItem(value: 'PICKUP', child: Text('Buyer pickup only')),
          DropdownMenuItem(
              value: 'SELLER_DELIVERY', child: Text('Seller can deliver')),
        ],
        onChanged: (v) => setState(() => _delivery = v ?? 'PICKUP,NEGOTIABLE'),
      ),
      if (_farms != null && _farms!.isNotEmpty) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _farm?.id,
          decoration: const InputDecoration(labelText: 'Farm'),
          items: _farms!
              .map((f) => DropdownMenuItem(
                  value: f.id,
                  child: Text(f.region == null
                      ? f.name
                      : '${f.name} · ${f.region}')))
              .toList(),
          onChanged: (v) =>
              setState(() => _farm = _farms!.firstWhere((f) => f.id == v)),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('A farm will be created for you automatically.',
              style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
        ),
    ]);
  }

  Widget _reviewStep() {
    final total =
        ((int.tryParse(_price.text.trim()) ?? 0) *
                (double.tryParse(_qty.text.trim()) ?? 0)) ~/
            1;
    return ListView(padding: const EdgeInsets.all(22), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${_product?.emoji ?? ''} ${_title.text.trim().isNotEmpty ? _title.text.trim() : _product?.name ?? ''}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900)),
            const Divider(height: 22),
            _row('Quantity', '${_qty.text.trim()} kg'),
            _row('Price',
                '${_price.text.trim()} minor/kg (${((int.tryParse(_price.text.trim()) ?? 0) / 100).toStringAsFixed(0)} RWF)'),
            _row('Type', _listingType == 'AUCTION' ? 'Auction' : 'Fixed price'),
            _row('Quality', _quality.replaceAll('_', ' ')),
            _row('Delivery', _delivery.replaceAll('_', ' ')),
            _row('Negotiable', _negotiable ? 'Yes' : 'No'),
            if (_region.text.trim().isNotEmpty)
              _row('Location', _region.text.trim()),
            const Divider(height: 22),
            _row('Estimated total value', '$total minor'),
          ]),
        ),
      ),
    ]);
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: IjwiColors.muted))),
          Text(v,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
