import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>>? _entries;
  String? _error;

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final w = await api.getJson('/wallet');
      final l = await api.getJson('/wallet/ledger', query: {'per_page': '20'});
      setState(() {
        _wallet = w;
        _entries = (l['entries'] as List? ?? const [])
            .map((j) => j as Map<String, dynamic>)
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

  Future<void> _withdraw() async {
    final amountCtl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amountCtl,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Amount (RWF, whole)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Request withdrawal')),
        ]),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).postJson('/wallet/withdrawals', {
        'amount_minor':
            ((double.tryParse(amountCtl.text.trim()) ?? 0) * 100).round(),
        'destination': 'mobile_money',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Withdrawal requested')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(title: Text(tr('tab_wallet'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: IjwiColors.green,
        foregroundColor: Colors.white,
        onPressed: _withdraw,
        icon: const Icon(Icons.arrow_upward),
        label: Text(tr('withdraw')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            color: IjwiColors.green,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('wallet_balance'),
                        style: TextStyle(color: Colors.white.withOpacity(0.85))),
                    const SizedBox(height: 6),
                    Text(
                        formatRwf((w?['available_minor'] as num?)?.toInt() ?? 0),
                        style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                        '${tr('pending_balance')}: '
                        '${formatRwf((w?['pending_minor'] as num?)?.toInt() ?? 0)}',
                        style: TextStyle(color: Colors.white.withOpacity(0.8))),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ...?_entries?.map((e) {
                final credit =
                    ((e['amount_minor'] as num?)?.toInt() ?? 0) >= 0;
                return ListTile(
                leading: Icon(
                    credit ? Icons.south_west : Icons.north_east,
                    color: credit ? IjwiColors.green : IjwiColors.red),
                title: Text(formatRwf((e['amount_minor'] as num?)?.toInt() ?? 0)),
                subtitle: Text('${e['reason_code'] ?? e['entry_type'] ?? ''}'),
                trailing: Text(
                    formatRwf((e['balance_after_minor'] as num?)?.toInt() ?? 0,
                        withSymbol: false)),
              );})
        ]),
      ),
    );
  }
}
