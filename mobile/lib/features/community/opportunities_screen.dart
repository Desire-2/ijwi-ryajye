import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';

/// Opportunities: buyer requests surfaced to farmers in the community.
/// Each connects into the real marketplace backend.
class OpportunitiesScreen extends ConsumerStatefulWidget {
  const OpportunitiesScreen({super.key});

  @override
  ConsumerState<OpportunitiesScreen> createState() =>
      _OpportunitiesScreenState();
}

class _OpportunitiesScreenState extends ConsumerState<OpportunitiesScreen> {
  List<Opportunity>? _opportunities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final opps = await svc.listBuyerRequests();
      if (!mounted) return;
      setState(() {
        _opportunities = opps;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Opportunities')),
      body: _error != null && _opportunities == null
          ? ErrorBox(_error!, onRetry: _load)
          : _opportunities == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _opportunities!.isEmpty
                      ? ListView(children: const [
                          EmptyState(
                              icon: Icons.local_fire_department_outlined,
                              title: 'No buyer requests right now',
                              message:
                                  'New opportunities from buyers will appear here.'),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _opportunities!.length,
                          itemBuilder: (context, i) {
                            final o = _opportunities![i];
                            return _opportunityCard(o);
                          },
                        ),
                ),
    );
  }

  Widget _opportunityCard(Opportunity o) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.local_fire_department, size: 16, color: IjwiColors.red),
            SizedBox(width: 4),
            Text('BUYER REQUEST',
                style: TextStyle(
                    color: IjwiColors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Text(o.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (o.description != null && o.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(o.description!,
                style: const TextStyle(
                    color: IjwiColors.muted, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 6, children: [
            if (o.product != null)
              _infoChip('🌾', o.product!),
            if (o.quantityValue != null)
              _infoChip('📦', '${_num(o.quantityValue!)} ${o.unitCode}'),
            if (o.destinationRegion != null)
              _infoChip('📍', o.destinationRegion!),
            if (o.requiredByDate != null)
              _infoChip('📅', 'By ${o.requiredByDate}'),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(150, 40)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Open a chat with this buyer to respond')));
              },
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Respond'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoChip(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: IjwiColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$emoji $text',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
