import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../../shared/widgets/ui.dart';

class _PriceRow {
  _PriceRow.fromJson(Map<String, dynamic> j)
      : product = (j['product'] as Map<String, dynamic>?)?['name'] as String? ?? '—',
        region = j['region'] as String?,
        midMinor = (j['price_mid_minor'] as num?)?.toInt() ?? 0,
        lowMinor = (j['price_low_minor'] as num?)?.toInt() ?? 0,
        highMinor = (j['price_high_minor'] as num?)?.toInt() ?? 0;

  final String product;
  final String? region;
  final int midMinor;
  final int lowMinor;
  final int highMinor;
}

class _Article {
  _Article.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? '',
        topic = j['topic'] as String? ?? 'general',
        body = j['body_text'] as String? ?? '';

  final String id;
  final String title;
  final String topic;
  final String body;
}

/// Market intelligence hub: Prices · Weather · Advisories · Ask Ijwi.
class IntelligenceHubScreen extends ConsumerStatefulWidget {
  const IntelligenceHubScreen({this.initialTab = 0, super.key});

  final int initialTab;

  @override
  ConsumerState<IntelligenceHubScreen> createState() =>
      _IntelligenceHubScreenState();
}

class _IntelligenceHubScreenState extends ConsumerState<IntelligenceHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  List<_PriceRow>? _prices;
  List<_Article>? _articles;
  Map<String, dynamic>? _weather;
  String? _weatherNote;
  String? _errorPrices;
  String? _errorArticles;

  // AI chat state
  final _aiInput = TextEditingController();
  final _aiScroll = ScrollController();
  final List<Map<String, String>> _aiMessages = [];
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPrices();
    _loadAdvisories();
    _loadWeather();
  }

  Future<void> _loadPrices() async {
    try {
      final res = await ref.read(apiClientProvider).getJson('/market-prices',
          query: {'days': '3', 'limit': '60'});
      final rows = (res['prices'] as List? ?? const [])
          .map((j) => _PriceRow.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _prices = rows;
        _errorPrices = null;
      });
    } catch (e) {
      setState(() => _errorPrices = ApiClient.errorMessage(e));
    }
  }

  Future<void> _loadAdvisories() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/advisory/articles', query: {'per_page': '50'});
      setState(() {
        _articles = (res['articles'] as List? ?? const [])
            .map((j) => _Article.fromJson(j as Map<String, dynamic>))
            .toList();
        _errorArticles = null;
      });
    } catch (e) {
      setState(() => _errorArticles = ApiClient.errorMessage(e));
    }
  }

  Future<void> _loadWeather() async {
    try {
      final res = await ref.read(apiClientProvider).getJson('/weather');
      setState(() => _weather = res);
    } catch (e) {
      setState(() => _weatherNote = ApiClient.errorMessage(e));
    }
  }

  Future<void> _sendAiMessage() async {
    final text = _aiInput.text.trim();
    if (text.isEmpty || _aiBusy) return;
    _aiInput.clear();
    setState(() {
      _aiMessages.add({'role': 'user', 'content': text});
      _aiBusy = true;
    });
    try {
      final res = await ref.read(apiClientProvider).postJson('/ai/chat', {
        'messages': [
          {'role': 'system', 'content': 'You are Ijwi, a helpful agriculture assistant for Rwandan farmers.'},
          ..._aiMessages,
        ],
      });
      final reply = res['reply'] as Map<String, dynamic>?;
      setState(() => _aiMessages.add({
            'role': 'assistant',
            'content': reply?['answer'] as String? ??
                (reply is String ? reply : 'Sorry, I could not answer that.'),
          }));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_aiScroll.hasClients) {
        await _aiScroll.animateTo(_aiScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } catch (e) {
      setState(() => _aiMessages.add({
            'role': 'assistant',
            'content': ApiClient.errorMessage(e),
          }));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _aiInput.dispose();
    _aiScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('advisory') == 'Advisories' ? 'Knowledge' : tr('advisory')),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Prices'),
            Tab(text: 'Weather'),
            Tab(text: 'Advice'),
            Tab(icon: Icon(Icons.smart_toy_outlined, size: 20), text: 'Ask Ijwi'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _pricesTab(),
        _weatherTab(),
        _advisoriesTab(),
        _aiTab(),
      ]),
    );
  }

  // ---- Prices ----

  Widget _pricesTab() {
    return RefreshIndicator(
      onRefresh: _loadPrices,
      child: _prices == null
          ? (_errorPrices != null
              ? ListView(children: [ErrorBox(_errorPrices!, onRetry: _loadPrices)])
              : ListView(children: const [Skeleton(height: 70), Skeleton(height: 70)]))
          : Builder(builder: (context) {
              // Latest price per product+region; show most recent first.
              final byKey = <String, _PriceRow>{};
              for (final p in _prices!) {
                byKey.putIfAbsent('${p.product}|${p.region}', () => p);
              }
              final rows = byKey.values.toList();
              if (rows.isEmpty) {
                return ListView(children: const [
                  EmptyState(
                      icon: Icons.query_stats,
                      title: 'No prices yet',
                      message:
                          'Market price observations will appear here as soon as data arrives.'),
                ]);
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final p = rows[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.query_stats,
                          color: IjwiColors.green),
                      title: Text(p.product,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(p.region ?? 'National average'),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(formatRwf(p.midMinor),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: IjwiColors.greenDark)),
                          Text(
                              '${formatRwf(p.lowMinor, withSymbol: false)} – '
                              '${formatRwf(p.highMinor, withSymbol: false)}',
                              style: const TextStyle(
                                  fontSize: 11, color: IjwiColors.muted)),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
    );
  }

  // ---- Weather ----

  Widget _weatherTab() {
    return RefreshIndicator(
      onRefresh: _loadWeather,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_weather != null)
          Card(
            color: IjwiColors.blue,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.wb_sunny_outlined, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('${_weather!['region'] ?? ''}',
                          style: const TextStyle(color: Colors.white)),
                    ]),
                    const SizedBox(height: 10),
                    ..._weather!.entries
                        .where((e) =>
                            e.key != 'region' &&
                            e.value != null &&
                            e.value.toString().isNotEmpty)
                        .take(6)
                        .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                Expanded(
                                    child: Text(e.key.replaceAll('_', ' '),
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(.8)))),
                                Flexible(
                                  child: Text('${e.value}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ]),
                            )),
                  ]),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                  _weatherNote ??
                      'Loading weather…\n\nIf no weather provider is configured on the server, this card stays empty.',
                  style: const TextStyle(color: IjwiColors.muted)),
            ),
          ),
      ]),
    );
  }

  // ---- Advisories ----

  Widget _advisoriesTab() {
    return RefreshIndicator(
      onRefresh: _loadAdvisories,
      child: _articles == null
          ? (_errorArticles != null
              ? ListView(
                  children: [ErrorBox(_errorArticles!, onRetry: _loadAdvisories)])
              : ListView(children: const [Skeleton(height: 90), Skeleton(height: 90)]))
          : (_articles!.isEmpty
              ? ListView(children: const [
                  EmptyState(
                      icon: Icons.tips_and_updates_outlined,
                      title: 'No advice yet',
                      message:
                          'Agronomy articles and expert answers will appear here.'),
                ])
              : ListView.builder(
                  itemCount: _articles!.length,
                  itemBuilder: (context, i) {
                    final a = _articles![i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: IjwiColors.greenLight,
                            child: Icon(Icons.tips_and_updates_outlined,
                                color: IjwiColors.green)),
                        title: Text(a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(a.body,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        trailing: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(a.topic,
                                style: const TextStyle(fontSize: 11))),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => DraggableScrollableSheet(
                            expand: false,
                            initialChildSize: 0.7,
                            builder: (_, scroll) => ListView(
                              controller: scroll,
                              padding: const EdgeInsets.all(22),
                              children: [
                                Chip(label: Text(a.topic)),
                                const SizedBox(height: 8),
                                Text(a.title,
                                    style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 14),
                                Text(a.body,
                                    style: const TextStyle(height: 1.55)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  })),
    );
  }

  // ---- AI assistant ----

  Widget _aiTab() {
    final tr = ref.watch(trProvider);
    return Column(children: [
      Expanded(
        child: _aiMessages.isEmpty
            ? EmptyState(
                icon: Icons.smart_toy_outlined,
                title: tr('ask_ai'),
                message:
                    'Ask anything about farming, prices or selling.\nTry: "When should I plant beans in Musanze?"')
            : ListView.builder(
                controller: _aiScroll,
                padding: const EdgeInsets.all(12),
                itemCount: _aiMessages.length,
                itemBuilder: (context, i) {
                  final m = _aiMessages[i];
                  final mine = m['role'] == 'user';
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 10),
                      constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.78),
                      decoration: BoxDecoration(
                        color: mine ? IjwiColors.green : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(m['content'] ?? '',
                          style: TextStyle(
                              height: 1.4,
                              color: mine ? Colors.white : Colors.black87)),
                    ),
                  );
                },
              ),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _aiInput,
                onSubmitted: (_) => _sendAiMessage(),
                decoration: InputDecoration(hintText: tr('ask_ai')),
              ),
            ),
            IconButton.filled(
              onPressed: _aiBusy ? null : _sendAiMessage,
              icon: _aiBusy
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }
}
