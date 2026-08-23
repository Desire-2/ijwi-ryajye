import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class OrderRow {
  OrderRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        state = j['state'] as String? ?? 'PENDING_PAYMENT',
        totalMinor = (j['total_minor'] as num?)?.toInt() ?? 0;

  final String id;
  final String state;
  final int totalMinor;

  bool get needsPayment => state == 'PAID' || state == 'PENDING_PAYMENT';
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<OrderRow>? _items;
  String? _error;
  String? _payingId;

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/orders', query: {'per_page': '50'});
      setState(() {
        _items = (res['items'] as List)
            .map((j) => OrderRow.fromJson(j as Map<String, dynamic>))
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

  Future<void> _pay(OrderRow o) async {
    setState(() => _payingId = o.id);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.postJson('/orders/${o.id}/payments', {
        'provider': 'mock',
        'method': 'mobile_money',
      });
      final payment = res['payment'] as Map<String, dynamic>;
      // Mock provider completes instantly via webhook in dev; poll wallet.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Payment ${payment['provider_reference'] ?? ''} initiated')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _payingId = null);
    }
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'COMPLETED':
      case 'DELIVERED':
        return IjwiColors.green;
      case 'CANCELLED':
      case 'DISPUTED':
        return IjwiColors.red;
      case 'IN_TRANSIT':
      case 'READY_FOR_PICKUP':
        return IjwiColors.blue;
      default:
        return IjwiColors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
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
                  final color = _stateColor(o.state);
                  return Card(
                    child: ListTile(
                      title:
                          Text(compactRwf(o.totalMinor),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 17)),
                      subtitle: Row(children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(o.state),
                      ]),
                      trailing: o.needsPayment
                          ? FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(90, 36)),
                              onPressed: _payingId == o.id
                                  ? null
                                  : () => _pay(o),
                              child: _payingId == o.id
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(tr('pay_order')),
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
