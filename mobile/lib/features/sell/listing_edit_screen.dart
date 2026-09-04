import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../market/marketplace_models.dart';
import '../market/marketplace_repository.dart';
import 'listing_wizard_engine.dart';

/// Edit screen for live (published) listings. Drafts continue through the
/// Create Listing wizard instead. Field set mirrors what the backend permits
/// for live listings — quantity changes restock/trim real inventory.
class ListingEditScreen extends ConsumerStatefulWidget {
  const ListingEditScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<ListingEditScreen> createState() => _ListingEditScreenState();
}

class _ListingEditScreenState extends ConsumerState<ListingEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  final _variety = TextEditingController();

  final Set<String> _delivery = {};
  bool _negotiable = false;
  String _quality = 'UNGRADED';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  Listing? _listing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _quantity.dispose();
    _variety.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (listing, _) =
          await ref.read(marketplaceRepositoryProvider).listing(widget.listingId);
      if (!mounted) return;
      final price = listing.priceMinor;
      setState(() {
        _listing = listing;
        _loading = false;
        _title.text = listing.title;
        _description.text = listing.description;
        _quantity.text =
            listing.availableQuantity.toStringAsFixed(_isInt(listing.availableQuantity) ? 0 : 2);
        _quality = listing.qualityGrade;
        _variety.text = listing.variety;
        _negotiable = listing.negotiable;
        _delivery
          ..clear()
          ..addAll(listing.deliveryOptions);
        if (price != null && !listing.isAuction) {
          _price.text = _majorOf(price);
        }
        _notice = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiClient.errorMessage(e);
      });
    }
  }

  bool _isInt(double v) => v == v.roundToDouble();

  String _majorOf(int minor) {
    final major = minor / 100;
    return major == major.roundToDouble()
        ? major.toInt().toString()
        : major.toStringAsFixed(2);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final l = _listing!;
      final patch = <String, dynamic>{
        'title': _title.text.trim().isEmpty ? l.title : _title.text.trim(),
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
        if (_variety.text.trim().isNotEmpty) 'variety': _variety.text.trim(),
        'delivery_options': _delivery.toList(),
        'negotiable': _negotiable,
        'quality_grade': _quality,
        if (!l.isAuction && _price.text.trim().isNotEmpty)
          'price_minor': ((num.tryParse(_price.text.trim()) ?? 0) * 100).round(),
        if (_quantity.text.trim().isNotEmpty)
          'available_quantity': double.tryParse(_quantity.text.trim()) ?? 0,
      };
      await ref
          .read(marketplaceRepositoryProvider)
          .updateListing(widget.listingId, patch);
      if (!mounted) return;
      setState(() => _notice = 'Changes saved.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _state(String state) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .updateListing(widget.listingId, {'state': state});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _listing;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit listing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : l == null
              ? (_error != null
                  ? Center(child: Text(_error!))
                  : const SizedBox.shrink())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Row(children: [
                        Text('${l.productEmoji} ', style: const TextStyle(fontSize: 26)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.productName,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(
                                    '${_stateLabel(l.state)} · '
                                    '${l.availableQuantity.toStringAsFixed(_isInt(l.availableQuantity) ? 0 : 2)} ${l.unitCode} available',
                                    style: const TextStyle(
                                        fontSize: 12.5, color: IjwiColors.muted)),
                              ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _title,
                        maxLength: 90,
                        decoration: const InputDecoration(
                            labelText: 'Listing title', counterText: ''),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: 'Description', alignLabelWithHint: true),
                      ),
                      const SizedBox(height: 14),
                      if (!l.isAuction) ...[
                        TextField(
                          controller: _price,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Price',
                            prefixText: 'RWF ',
                            suffixText: 'per ${l.unitCode}',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 6),
                        if (_price.text.trim().isNotEmpty)
                          Text(
                            '${formatRwf(((num.tryParse(_price.text.trim()) ?? 0) * 100).round())} per ${l.unitCode}',
                            style: const TextStyle(
                                color: IjwiColors.muted, fontSize: 12),
                          ),
                        const SizedBox(height: 14),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Auctions keep their price; manage the reserve from the listing.',
                            style: TextStyle(color: IjwiColors.muted, fontSize: 12.5),
                          ),
                        ),
                      TextField(
                        controller: _quantity,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Available quantity',
                          suffixText: l.unitCode,
                          helperText:
                              'Top up stock or reduce it (never below committed offers/bids)',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _quality,
                        decoration: const InputDecoration(labelText: 'Quality grade'),
                        items: [
                          for (final g in qualityGrades)
                            DropdownMenuItem(value: g, child: Text(gradeLabel(g))),
                        ],
                        onChanged: (v) =>
                            setState(() => _quality = v ?? 'UNGRADED'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _variety,
                        decoration: const InputDecoration(
                            labelText: 'Variety (optional)',
                            hintText: 'e.g. Kinigi, Longe 5'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Accept offers / negotiable'),
                        value: _negotiable,
                        activeThumbColor: IjwiColors.green,
                        onChanged: (v) => setState(() => _negotiable = v),
                      ),
                      const SizedBox(height: 6),
                      const Text('How will buyers receive it?',
                          style: TextStyle(fontWeight: FontWeight.w800)),
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
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(_notice!,
                              style: const TextStyle(color: IjwiColors.greenDark)),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(_error!,
                              style: const TextStyle(color: IjwiColors.red)),
                        ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save changes'),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        if (l.state == 'ACTIVE')
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.pause_outlined),
                              label: const Text('Pause'),
                              onPressed: _saving ? null : () => _state('PAUSED'),
                            ),
                          ),
                        if (l.state == 'PAUSED') ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: const Text('Activate'),
                              onPressed: _saving ? null : () => _state('ACTIVE'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (l.state != 'CLOSED') ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: IjwiColors.red),
                              icon: const Icon(Icons.close),
                              label: const Text('Close'),
                              onPressed: _saving ? null : _close,
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
    );
  }

  String _stateLabel(String s) => switch (s) {
        'ACTIVE' => 'Active',
        'PAUSED' => 'Paused',
        'CLOSED' => 'Closed',
        'SOLD_OUT' => 'Sold out',
        'EXPIRED' => 'Expired',
        _ => s,
      };

  Future<void> _close() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close listing?'),
        content: const Text('It will no longer appear in the market.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .closeListing(widget.listingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Listing closed.')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}
