import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../market/marketplace_models.dart';
import '../market/marketplace_repository.dart';

/// Platform-admin catalogue management: add and edit the categories,
/// products and units the marketplace runs on — no app release needed.
/// The backend enforces the ADMIN role on every request.
class AdminCatalogScreen extends ConsumerStatefulWidget {
  const AdminCatalogScreen({super.key});

  @override
  ConsumerState<AdminCatalogScreen> createState() => _AdminCatalogScreenState();
}

class _AdminCatalogScreenState extends ConsumerState<AdminCatalogScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catalogue management'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.category_outlined), text: 'Categories'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Products'),
              Tab(icon: Icon(Icons.straighten), text: 'Units'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _CategoriesTab(),
          _ProductsTab(),
          _UnitsTab(),
        ]),
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox({this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
}

// ------------------------------------------------------------- categories

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab();

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  List<Category>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final items = await ref.read(marketplaceRepositoryProvider).categories();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _add() => _editDialog();

  Future<void> _edit(Category c) =>
      _editDialog(id: c.id, name: c.name, icon: c.icon);

  Future<void> _editDialog(
      {String? id, String name = '', String icon = ''}) async {
    final nameCtrl = TextEditingController(text: name);
    final iconCtrl = TextEditingController(text: icon);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? 'New category' : 'Edit category'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words),
          TextField(controller: iconCtrl,
              decoration: const InputDecoration(
                  labelText: 'Icon', hintText: 'e.g. 🌾 or 🐄 or 🚜',
                  counterText: ''),
              maxLength: 4),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      setState(() => _error = null);
      if (id == null) {
        await repo.adminCreateCategory(
            name: nameCtrl.text.trim(), icon: iconCtrl.text.trim());
      } else {
        await repo.adminUpdateCategory(id, {
          if (nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
          if (iconCtrl.text.trim().isNotEmpty) 'icon': iconCtrl.text.trim(),
        });
      }
      await _load();
    } catch (e) {
      _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? _LoadingBox(error: _error, onRetry: _load)
          : ListView(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.add)),
                  title: const Text('Add category',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                      'A new kind of offering — e.g. Storage, Equipment Rental'),
                  onTap: _add,
                ),
                const Divider(height: 1),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No categories yet')),
                  ),
                for (final c in items)
                  ListTile(
                    leading: Text(c.icon.isEmpty ? '🏷' : c.icon,
                        style: const TextStyle(fontSize: 22)),
                    title: Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.slug),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => _edit(c)),
                  ),
              ],
            ),
    );
  }
}

// --------------------------------------------------------------- products

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab();

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  List<ProductSummary>? _products;
  List<Category> _categories = const [];
  List<UnitOption> _units = const [];
  String? _error;

  Future<void> _load() async {
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.products(),
        repo.categories(),
        repo.units(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<ProductSummary>;
        _categories = results[1] as List<Category>;
        _units = results[2] as List<UnitOption>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _add() => _editDialog();

  Future<void> _edit(ProductSummary p) => _editDialog(
        id: p.id,
        name: p.name,
        categorySlug: p.categorySlug,
        unitCode: p.defaultUnit,
        emoji: p.emoji,
      );

  Future<void> _editDialog(
      {String? id,
      String name = '',
      String? categorySlug,
      String unitCode = 'kg',
      String emoji = ''}) async {
    if (_categories.isEmpty || _units.isEmpty) return;
    final nameCtrl = TextEditingController(text: name);
    final emojiCtrl = TextEditingController(text: emoji);
    String? catSlug = categorySlug ?? _categories.first.slug;
    String unit = _units.any((u) => u.code == unitCode)
        ? unitCode
        : _units.first.code;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(id == null ? 'New product' : 'Edit product'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words),
            TextField(controller: emojiCtrl,
                decoration: const InputDecoration(
                    labelText: 'Emoji', hintText: 'e.g. 🌾', counterText: ''),
                maxLength: 4),
            DropdownButtonFormField<String>(
              initialValue: catSlug,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in _categories)
                  DropdownMenuItem(value: c.slug, child: Text(c.name)),
              ],
              onChanged: (v) => setDialog(() => catSlug = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: 'Default unit'),
              items: [
                for (final u in _units)
                  DropdownMenuItem(
                      value: u.code, child: Text('${u.code} — ${u.label}')),
              ],
              onChanged: (v) => setDialog(() => unit = v ?? unit),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted || catSlug == null) return;
    final category = _categories.where((c) => c.slug == catSlug).firstOrNull;
    if (category == null) return;
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      if (id == null) {
        await repo.adminCreateProduct(
            name: nameCtrl.text.trim(),
            categoryId: category.id,
            defaultUnit: unit,
            emoji: emojiCtrl.text.trim());
      } else {
        await repo.adminUpdateProduct(id, {
          if (nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
          'category_id': category.id,
          'default_unit': unit,
          if (emojiCtrl.text.trim().isNotEmpty) 'emoji': emojiCtrl.text.trim(),
        });
      }
      await _load();
    } catch (e) {
      _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    if (products == null) {
      return _LoadingBox(error: _error, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.add)),
            title: const Text('Add product',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'An exact item sellers can list — choose its category first'),
            onTap: _add,
          ),
          const Divider(height: 1),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('No products yet')),
            ),
          for (final p in products)
            ListTile(
              leading: Text(p.emoji.isEmpty ? '🌱' : p.emoji,
                  style: const TextStyle(fontSize: 22)),
              title: Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${p.categoryName ?? ''} · per ${p.defaultUnit}'),
              trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => _edit(p)),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ units

class _UnitsTab extends ConsumerStatefulWidget {
  const _UnitsTab();

  @override
  ConsumerState<_UnitsTab> createState() => _UnitsTabState();
}

class _UnitsTabState extends ConsumerState<_UnitsTab> {
  List<UnitOption>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final items = await ref.read(marketplaceRepositoryProvider).units();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _add() => _editDialog();

  Future<void> _edit(UnitOption u) => _editDialog(code: u.code, label: u.label);

  Future<void> _editDialog({String? code, String label = ''}) async {
    final codeCtrl = TextEditingController(text: code ?? '');
    final labelCtrl = TextEditingController(text: label);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(code == null ? 'New unit' : 'Edit unit'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: codeCtrl,
              enabled: code == null,
              decoration: const InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. kg, t, bag, crate, day, ha, trip'),
              textCapitalization: TextCapitalization.none),
          TextField(controller: labelCtrl,
              decoration: const InputDecoration(
                  labelText: 'Label', hintText: 'e.g. Kilogram, Bag (50kg)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      if (code == null) {
        await repo.adminCreateUnit(
            code: codeCtrl.text.trim(), label: labelCtrl.text.trim());
      } else {
        await repo.adminUpdateUnit(
            code, {'label': labelCtrl.text.trim()});
      }
      await _load();
    } catch (e) {
      _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? _LoadingBox(error: _error, onRetry: _load)
          : ListView(
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.add)),
                  title: const Text('Add unit',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle:
                      const Text('A measure sellers price and quote in'),
                  onTap: _add,
                ),
                const Divider(height: 1),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No units yet')),
                  ),
                for (final u in items)
                  ListTile(
                    leading: const Icon(Icons.straighten,
                        color: IjwiColors.greenDark),
                    title: Text(u.code,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(u.label),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => _edit(u)),
                  ),
              ],
            ),
    );
  }
}
