import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';
import 'marketplace_widgets.dart';

/// Buyer Requests (RFQ): browse open sourcing requests from buyers and post
/// your own request. Responding opens a structured offer against the request.
class BuyerRequestsScreen extends ConsumerStatefulWidget {
  const BuyerRequestsScreen({super.key});

  @override
  ConsumerState<BuyerRequestsScreen> createState() =>
      _BuyerRequestsScreenState();
}

class _BuyerRequestsScreenState extends ConsumerState<BuyerRequestsScreen> {
  List<BuyerRequest>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final page =
          await ref.read(marketplaceRepositoryProvider).buyerRequests();
      if (mounted) {
        setState(() {
          _items = page.items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buyer requests',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Post a request',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: IjwiColors.surface,
                builder: (_) => const _CreateRequestSheet(),
              );
              await _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? (_error != null
                ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
                : ListView(padding: const EdgeInsets.all(14), children: const [
                    Skeleton(height: 120), SizedBox(height: 8),
                    Skeleton(height: 120),
                  ]))
            : _items!.isEmpty
                ? MarketplaceEmpty(
                    icon: Icons.groups_outlined,
                    title: 'No open buyer requests',
                    message:
                        'Buyers post requests to source produce in bulk. You can post one too.',
                    actionLabel: 'Post a request',
                    onAction: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: IjwiColors.surface,
                        builder: (_) => const _CreateRequestSheet(),
                      );
                      await _load();
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) => _RequestCard(
                        request: _items![i],
                        repo: ref.read(marketplaceRepositoryProvider)),
                  ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request, required this.repo});

  final BuyerRequest request;
  final MarketplaceRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetLabel = request.budgetMinMinor != null ||
            request.budgetMaxMinor != null
        ? [
            if (request.budgetMinMinor != null)
              (request.budgetMinMinor! / 100).toStringAsFixed(0),
            if (request.budgetMaxMinor != null)
              (request.budgetMaxMinor! / 100).toStringAsFixed(0),
          ].join('–')
        : null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(request.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: request.isOpen
                    ? IjwiColors.greenLight
                    : const Color(0xFFEEE7DA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(request.state,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: request.isOpen
                          ? IjwiColors.greenDark
                          : IjwiColors.muted)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${request.quantityValue.toStringAsFixed(request.quantityValue == request.quantityValue.roundToDouble() ? 0 : 2)} ${request.unitCode}'
            '${request.qualityGrade != 'UNGRADED' ? ' · ${request.qualityGrade.replaceAll('_', ' ')}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (request.destinationLabel.isNotEmpty)
              _iconText(Icons.location_on_outlined, request.destinationLabel),
            if (request.requiredByDate != null)
              _iconText(Icons.event_outlined, 'By ${request.requiredByDate}'),
            if (budgetLabel != null)
              _iconText(Icons.paid_outlined, '$budgetLabel ${request.currencyCode}'),
          ]),
          const SizedBox(height: 10),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                minimumSize: const Size(120, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: () => _respond(context, ref),
            child: const Text('Respond with offer'),
          ),
        ]),
      ),
    );
  }

  Widget _iconText(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: IjwiColors.muted),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(fontSize: 12, color: IjwiColors.muted)),
        ],
      );

  Future<void> _respond(BuildContext context, WidgetRef ref) async {
    final qtyCtl = TextEditingController(
        text: request.quantityValue.toStringAsFixed(0));
    final priceCtl = TextEditingController();
    final budget = request.budgetMaxMinor ?? request.budgetMinMinor;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Respond to request',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(request.title,
              style: const TextStyle(color: IjwiColors.muted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: qtyCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Quantity (${request.unitCode})'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your price / ${request.unitCode} (${request.currencyCode} minor)',
              helperText: budget != null
                  ? 'Budget up to ${(budget / 100).toStringAsFixed(0)} ${request.currencyCode}'
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send offer'),
          ),
        ]),
      ),
    );
    if (sent != true) return;
    try {
      await repo.createOffer({
        'buyer_request_id': request.id,
        'quantity_value': double.tryParse(qtyCtl.text.trim()) ?? 0,
        'price_minor': int.tryParse(priceCtl.text.trim()) ?? 0,
        'unit_code': request.unitCode,
        'currency_code': request.currencyCode,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Offer sent'), backgroundColor: IjwiColors.green));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}

class _CreateRequestSheet extends ConsumerStatefulWidget {
  const _CreateRequestSheet();

  @override
  ConsumerState<_CreateRequestSheet> createState() =>
      _CreateRequestSheetState();
}

class _CreateRequestSheetState extends ConsumerState<_CreateRequestSheet> {
  List<ProductSummary>? _products;
  ProductSummary? _product;
  final _title = TextEditingController();
  final _qty = TextEditingController(text: '1000');
  final _region = TextEditingController();
  final _desc = TextEditingController();
  final _budgetMin = TextEditingController();
  final _budgetMax = TextEditingController();
  String _quality = 'UNGRADED';
  DateTime? _requiredBy;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _title.dispose();
    _qty.dispose();
    _region.dispose();
    _desc.dispose();
    _budgetMin.dispose();
    _budgetMax.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final ps = await ref.read(marketplaceRepositoryProvider).products();
      if (mounted) setState(() => _products = ps);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    if (_product == null || qty <= 0 || _title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose a product, enter a title and quantity')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(marketplaceRepositoryProvider).createBuyerRequest({
        'product_id': _product!.id,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'quantity_value': qty,
        'unit_code': 'kg',
        'quality_grade': _quality,
        if (_region.text.trim().isNotEmpty) 'destination_region': _region.text.trim(),
        if (_requiredBy != null) 'required_by_date': _requiredBy!.toIso8601String().split('T').first,
        if ((double.tryParse(_budgetMin.text.trim()) ?? 0) > 0)
          'budget_min_minor':
              ((double.tryParse(_budgetMin.text.trim()) ?? 0) * 100).round(),
        if ((double.tryParse(_budgetMax.text.trim()) ?? 0) > 0)
          'budget_max_minor':
              ((double.tryParse(_budgetMax.text.trim()) ?? 0) * 100).round(),
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Post a buyer request',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Tell farmers what you need to source',
              style: TextStyle(color: IjwiColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              // product picker
              DropdownButtonFormField<String>(
                value: null,
                decoration:
                    const InputDecoration(labelText: 'What do you need?'),
                hint: const Text('Select product'),
                items: (_products ?? const <ProductSummary>[])
                    .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.emoji} ${p.name}')))
                    .toList(),
                onChanged: (v) => setState(() =>
                    _product = (_products ?? []).firstWhere((p) => p.id == v)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Request title',
                    hintText: 'e.g. 10 tonnes beans for Kigali'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qty,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Quantity (kg)',
                    suffixText: 'kg'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _region,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Destination location'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _budgetMin,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Budget min (RWF)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _budgetMax,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Budget max (RWF)'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _quality,
                    decoration: const InputDecoration(labelText: 'Quality'),
                    items: const [
                      DropdownMenuItem(value: 'UNGRADED', child: Text('Any')),
                      DropdownMenuItem(value: 'STANDARD', child: Text('Standard')),
                      DropdownMenuItem(value: 'GRADE_A', child: Text('Grade A')),
                      DropdownMenuItem(value: 'GRADE_B', child: Text('Grade B')),
                      DropdownMenuItem(value: 'PREMIUM', child: Text('Premium')),
                    ],
                    onChanged: (v) => setState(() => _quality = v ?? 'UNGRADED'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _requiredBy = d);
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_requiredBy == null
                        ? 'Required by'
                        : _requiredBy!.toIso8601String().split('T').first,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                    hintText: 'Packaging, certification, delivery terms…'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post request'),
          ),
        ]),
      ),
    );
  }
}