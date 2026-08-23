import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class OfferRow {
  OfferRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        state = j['state'] as String? ?? 'PENDING',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        quantity = (j['quantity_value'] as num?)?.toDouble() ?? 0;

  final String id;
  final String state;
  final int priceMinor;
  final double quantity;
}

class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  List<OfferRow>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/offers', query: {'per_page': '50'});
      setState(() {
        _items = (res['items'] as List)
            .map((j) => OfferRow.fromJson(j as Map<String, dynamic>))
            .toList();
        _error = null;
      });
    } catch (e) {
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _act(OfferRow o, String action) async {
    try {
      await ref.read(apiClientProvider).postJson('/offers/${o.id}/$action', {});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'ACCEPTED':
        return IjwiColors.green;
      case 'REJECTED':
      case 'EXPIRED':
      case 'WITHDRAWN':
        return IjwiColors.red;
      case 'COUNTERED':
        return IjwiColors.amber;
      default:
        return IjwiColors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.red))
                    : const CircularProgressIndicator())
            : ListView.builder(
                itemCount: _items!.length,
                itemBuilder: (context, i) {
                  final o = _items![i];
                  return Card(
                    child: ListTile(
                      title: Text(
                          '${o.quantity} units · ${formatRwf(o.priceMinor)}/unit',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(tr('order_status')),
                      leading: CircleAvatar(
                        backgroundColor:
                            _stateColor(o.state).withOpacity(0.15),
                        child: Icon(Icons.receipt_long,
                            color: _stateColor(o.state)),
                      ),
                      trailing: o.state == 'PENDING'
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: tr('accept_offer'),
                                  onPressed: () => _act(o, 'accept'),
                                  icon: const Icon(Icons.check,
                                      color: IjwiColors.green)),
                              IconButton(
                                  tooltip: tr('reject'),
                                  onPressed: () => _act(o, 'reject'),
                                  icon: const Icon(Icons.close,
                                      color: IjwiColors.red)),
                            ])
                          : Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(o.state),
                              backgroundColor:
                                  _stateColor(o.state).withOpacity(0.12)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
