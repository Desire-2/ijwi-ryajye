import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/ui.dart';
import '../market/marketplace_repository.dart';

class MyListingRow {
  MyListingRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        state = j['state'] as String? ?? 'ACTIVE',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        available = (j['available_quantity'] as num?)?.toDouble() ?? 0,
        unit = j['unit_code'] as String? ?? 'kg',
        listingType = j['listing_type'] as String? ?? 'FIXED_PRICE',
        emoji =
            (j['product'] as Map<String, dynamic>?)?['emoji'] as String? ?? '🌱';

  final String id;
  final String title;
  final String state;
  final int priceMinor;
  final double available;
  final String unit;
  final String listingType;
  final String emoji;
}

/// Seller hub: the user's own listings (drafts included), drafts that are
/// stored on this device (offline starts), + entry to publish.
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  List<MyListingRow>? _items;
  List<Map<String, dynamic>> _localDrafts = const [];
  String? _error;

  Future<void> _load() async {
    // Device-local drafts load even when the server is unreachable (offline),
    // so sellers never lose the ability to see and continue an offline start.
    List<Map<String, dynamic>> local = const [];
    try {
      local =
          await ref.read(marketplaceRepositoryProvider).localListingDrafts();
    } catch (_) {
      // best-effort
    }
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/listings/mine', query: {'per_page': '50'});
      if (!mounted) return;
      setState(() {
        _items = (res['items'] as List? ?? const [])
            .map((j) => MyListingRow.fromJson(j as Map<String, dynamic>))
            .toList();
        _localDrafts = local;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localDrafts = local;
        _error = ApiClient.errorMessage(e);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setState(MyListingRow l, String state) async {
    try {
      await ref
          .read(apiClientProvider)
          .patchJson('/listings/${l.id}', {'state': state});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Future<void> _closeListing(MyListingRow l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close listing?'),
        content: Text('"${l.title}" will no longer appear in the market.'),
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
    if (confirmed != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .postJson('/listings/${l.id}/close', {});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Future<void> _continueLocalDraft(String id) async {
    await context.push('/sell/new?id=$id');
    await _load();
  }

  Future<void> _deleteLocalDraft(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
            'It is only stored on this device and cannot be recovered.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(marketplaceRepositoryProvider).deleteLocalListingDraft(id);
    } catch (_) {
      // best-effort
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('my_listings')),
        actions: [
          IconButton(
            tooltip: 'Seller dashboard',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.push('/sell/dashboard'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: IjwiColors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Create listing'),
        onPressed: () async {
          await context.push('/sell/new');
          await _load();
        },
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final loading = _items == null && _localDrafts.isEmpty;
    if (loading) {
      return _error != null
          ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
          : ListView(children: const [
              Skeleton(height: 84),
              SizedBox(height: 8),
              Skeleton(height: 84),
            ]);
    }
    final serverRows = _items ?? const <MyListingRow>[];
    if (serverRows.isEmpty && _localDrafts.isEmpty) {
      if (_error != null) {
        return ListView(children: [ErrorBox(_error!, onRetry: _load)]);
      }
      return ListView(children: [
        EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No listings yet',
          message:
              'Offer anything you grow, raise or provide — produce, '
              'livestock, equipment, services, transport and more.',
          actionLabel: 'Create listing',
          onAction: () async {
            await context.push('/sell/new');
            await _load();
          },
        ),
      ]);
    }
    final children = <Widget>[];
    if (_localDrafts.isNotEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('Drafts on this device',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF9A6B00))),
      ));
      for (final d in _localDrafts) {
        children.add(_localDraftTile(d));
      }
      if (_error != null) {
        children.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            "You're offline — server listings could not load. "
            'These drafts stay on this device until you publish online.',
            style: TextStyle(fontSize: 12, color: IjwiColors.muted),
          ),
        ));
      }
      if (serverRows.isNotEmpty) {
        children.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text('My listings',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ));
      }
    }
    children.addAll(serverRows.map(_serverTile));
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: children,
    );
  }

  Widget _localDraftTile(Map<String, dynamic> d) {
    final id = d['local_id'] as String? ?? '';
    final rawTitle = d['title'] as String? ?? '';
    final title = rawTitle.trim().isNotEmpty
        ? rawTitle
        : d['product_name'] as String? ?? 'Untitled draft';
    final emoji = d['emoji'] as String? ?? '🌱';
    return Card(
      child: ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 28)),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text(
            'Saved on this device — publish when you\'re back online'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'continue') await _continueLocalDraft(id);
            if (v == 'delete') await _deleteLocalDraft(id);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'continue', child: Text('Continue draft')),
            PopupMenuItem(value: 'delete', child: Text('Delete draft')),
          ],
        ),
        onTap: () => _continueLocalDraft(id),
      ),
    );
  }

  Widget _serverTile(MyListingRow l) {
    return Card(
      child: ListTile(
        leading: Text(l.emoji, style: const TextStyle(fontSize: 28)),
        title: Text(l.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            l.state == 'DRAFT'
                ? 'Draft — use ⋮ to continue it'
                : '${formatRwf(l.priceMinor)}/${l.unit} · '
                    '${l.available.toStringAsFixed(0)} ${l.unit} left'
                    ' · ${l.listingType == "AUCTION" ? "Auction" : "Fixed"}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await context.push('/sell/new?id=${l.id}');
              await _load();
              return;
            }
            if (v == 'edit-live') {
              await context.push('/sell/edit?id=${l.id}');
              await _load();
              return;
            }
            if (v == 'close') _closeListing(l);
            if (v == 'pause') _setState(l, 'PAUSED');
            if (v == 'activate') _setState(l, 'ACTIVE');
          },
          itemBuilder: (context) => [
            if (l.state == 'DRAFT')
              const PopupMenuItem(value: 'edit', child: Text('Continue draft')),
            if (l.state == 'ACTIVE' ||
                l.state == 'PAUSED' ||
                l.state == 'SOLD_OUT')
              const PopupMenuItem(value: 'edit-live', child: Text('Edit listing')),
            if (l.state == 'ACTIVE')
              const PopupMenuItem(value: 'pause', child: Text('Pause listing')),
            if (l.state == 'PAUSED')
              const PopupMenuItem(
                  value: 'activate', child: Text('Activate listing')),
            if (l.state != 'DRAFT')
              const PopupMenuItem(value: 'close', child: Text('Close listing')),
          ],
          child: Chip(
            visualDensity: VisualDensity.compact,
            backgroundColor: l.state == 'ACTIVE'
                ? IjwiColors.greenLight
                : (l.state == 'DRAFT'
                    ? const Color(0xFFFBEED2)
                    : const Color(0xFFEEE7DA)),
            label: Text(
              l.state == 'DRAFT' ? 'Draft' : l.state,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: l.state == 'ACTIVE'
                    ? IjwiColors.greenDark
                    : (l.state == 'DRAFT'
                        ? const Color(0xFF9A6B00)
                        : IjwiColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
