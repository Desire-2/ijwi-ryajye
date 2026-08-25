import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';

class ConversationRow {
  ConversationRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = (j['title'] as String?)?.isNotEmpty == true
            ? j['title'] as String
            : 'Conversation',
        type = j['conversation_type'] as String? ?? 'DIRECT',
        lastMessageAt = DateTime.tryParse(
                j['last_message_at'] as String? ?? '') ??
            null;

  final String id;
  final String title;
  final String type;
  final DateTime? lastMessageAt;
}

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  List<ConversationRow>? _items;
  String? _error;

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/conversations', query: {'per_page': '50'});
      setState(() {
        _items = (res['conversations'] as List? ?? res['items'] as List? ?? const [])
            .map((j) => ConversationRow.fromJson(j as Map<String, dynamic>))
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

  @override
  Widget build(BuildContext context) {
    final tr = ref.watch(trProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('tab_chat'))),
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
                  final c = _items![i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.type == 'GROUP'
                            ? IjwiColors.blue.withOpacity(0.15)
                            : IjwiColors.greenLight,
                        child: Icon(
                            c.type == 'GROUP'
                                ? Icons.groups_2
                                : Icons.person,
                            color: c.type == 'GROUP'
                                ? IjwiColors.blue
                                : IjwiColors.green),
                      ),
                      title: Text(c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(timeAgo(c.lastMessageAt ??
                          DateTime.now())),
                      onTap: () => context.go('/chat/${c.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
