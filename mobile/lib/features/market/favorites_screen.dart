import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';
import 'marketplace_widgets.dart';

/// Saved listings (favorites). Removing updates the backend immediately.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  List<Listing>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final favs = await ref.read(marketplaceRepositoryProvider).favorites();
      if (mounted) {
        setState(() {
          _items = favs;
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

  Future<void> _remove(Listing l) async {
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .removeFavorite(l.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Removed from favorites')));
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
    return Scaffold(
      appBar: AppBar(
          title: const Text('Favorites',
              style: TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? (_error != null
                ? ListView(children: [ErrorBox(_error!, onRetry: _load)])
                : ListView(padding: const EdgeInsets.all(14), children: const [
                    Skeleton(height: 84), SizedBox(height: 8),
                    Skeleton(height: 84),
                  ]))
            : _items!.isEmpty
                ? const MarketplaceEmpty(
                    icon: Icons.favorite_border,
                    title: 'No saved products yet',
                    message:
                        'Save produce you want to revisit later — it will appear here.')
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) {
                      final l = _items![i];
                      return Stack(children: [
                        ListingRow(listing: l),
                        Positioned(
                          right: 38,
                          top: 14,
                          child: GestureDetector(
                            onTap: () => _remove(l),
                            child: const Icon(Icons.favorite,
                                size: 20, color: IjwiColors.red),
                          ),
                        ),
                      ]);
                    },
                  ),
      ),
    );
  }
}