import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../core/utils/money.dart';
import '../market/marketplace_models.dart';
import '../market/marketplace_repository.dart';

/// Show the share sheet for a freshly published (or any live) listing.
Future<void> showListingShareSheet(BuildContext context, Listing listing) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ListingShareSheet(listing: listing),
  );
}

class _CommunityOption {
  _CommunityOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        icon = j['icon_emoji'] as String? ?? '🏘',
        joined = (j['joined'] as bool?) ?? false;

  final String id;
  final String name;
  final String icon;
  final bool joined;
}

class _ConversationOption {
  _ConversationOption.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = (j['title'] as String?)?.isNotEmpty == true
            ? j['title'] as String
            : 'Conversation',
        type = j['conversation_type'] as String? ?? 'DIRECT';

  final String id;
  final String title;
  final String type;
}

/// Share actions that reuse existing product surfaces: posting the listing to
/// Status, to a community (or the public feed) with `listing_id`, copying a
/// shareable text and the system share sheet. No duplicate content model.
class ListingShareSheet extends ConsumerStatefulWidget {
  const ListingShareSheet({super.key, required this.listing});

  final Listing listing;

  @override
  ConsumerState<ListingShareSheet> createState() => _ListingShareSheetState();
}

class _ListingShareSheetState extends ConsumerState<ListingShareSheet> {
  bool _busy = false;
  String? _feedback;

  Listing get _l => widget.listing;

  String get _shareText {
    final price = _l.priceMinor == null
        ? 'Price negotiable'
        : '${formatMoney(_l.priceMinor!, _l.currencyCode)} / ${_l.unitCode}';
    final qty = formatQuantity(_l.availableQuantity, _l.unitCode);
    return '${_l.productEmoji} ${_l.title} — $price, $qty available'
        '${_l.locationLabel.isNotEmpty ? ' in ${_l.locationLabel}' : ''}\n'
        'Find it on Ijwi Ryajye.';
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? IjwiColors.red : IjwiColors.green,
    ));
  }

  Future<void> _shareToStatus() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .statusFromListing(_l.id, caption: _l.title);
      if (!mounted) return;
      Navigator.pop(context);
      _say('Posted to your Status — followers can open the listing.');
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = ApiClient.errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOutside() async {
    await Share.share(_shareText, subject: _l.title);
  }

  Future<void> _copyText() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    Navigator.pop(context);
    _say('Listing text copied.');
  }

  Future<void> _pickCommunity() async {
    List<_CommunityOption> communities = const [];
    try {
      final res = await ref.read(apiClientProvider).getJson('/communities');
      communities = (res['communities'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_CommunityOption.fromJson)
          .toList();
    } catch (_) {
      // community list is best-effort; the feed option remains
    }
    if (!mounted) return;
    final joined = communities.where((c) => c.joined).toList();
    final selection = await showModalBottomSheet<_CommunityOption>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Share to community',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          ListTile(
            leading: const Text('🌍', style: TextStyle(fontSize: 22)),
            title: const Text('Public feed (all farmers)'),
            subtitle: const Text('Shown to everyone browsing the community feed'),
            onTap: () => Navigator.pop(context, _CommunityOption.fromJson({
                  'id': '', 'name': 'Public feed', 'joined': true,
                })),
          ),
          const Divider(height: 1),
          if (joined.isEmpty)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Join a community to post there'),
              subtitle: Text('Your public feed post works without joining'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in joined)
                    ListTile(
                      leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
        ]),
      ),
    );
    if (selection == null || !mounted) return;
    await _postToCommunity(selection.id);
  }

  Future<void> _postToCommunity(String communityId) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await ref.read(marketplaceRepositoryProvider).publishListingPost(
            listingId: _l.id,
            body: _shareText,
            communityId: communityId.isEmpty ? null : communityId,
          );
      if (!mounted) return;
      Navigator.pop(context);
      _say(communityId.isEmpty
          ? 'Posted to the public feed.'
          : 'Posted to your community.');
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = ApiClient.errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickConversation() async {
    List<_ConversationOption> conversations = const [];
    try {
      final res = await ref
          .read(apiClientProvider)
          .getJson('/conversations', query: {'per_page': '50'});
      conversations = (res['conversations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_ConversationOption.fromJson)
          .toList();
    } catch (_) {
      // listing conversations is best-effort
    }
    if (!mounted) return;
    if (conversations.isEmpty) {
      _say('No conversations yet — start a chat from a listing or profile.',
          error: true);
      return;
    }
    final selection = await showModalBottomSheet<_ConversationOption>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Send to a chat',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in conversations)
                  ListTile(
                    leading: Icon(
                        c.type == 'GROUP'
                            ? Icons.groups_outlined
                            : Icons.person_outline,
                        color: IjwiColors.green),
                    title: Text(c.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
    if (selection == null || !mounted) return;
    await _sendToConversation(selection);
  }

  /// Sends the same `listing_card` message ChatScreen uses when sharing a
  /// product inside a conversation — recipient sees a tappable listing card.
  Future<void> _sendToConversation(_ConversationOption conv) async {
    final l = _l;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await ref.read(apiClientProvider).postJson(
            '/conversations/${conv.id}/messages',
            {
              'client_message_id':
                  'm-share-${DateTime.now().microsecondsSinceEpoch}',
              'message_type': 'listing_card',
              'body_text': '',
              'entity_ref_type': 'listing',
              'entity_ref_id': l.id,
              'entity_snapshot': {
                'listing_id': l.id,
                'title': l.title,
                'price_minor': l.priceMinor,
                'unit_code': l.unitCode,
                'emoji': l.productEmoji,
              },
            },
          );
      if (!mounted) return;
      Navigator.pop(context);
      _say('Sent to ${conv.title}.');
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = ApiClient.errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('${l.productEmoji} ', style: const TextStyle(fontSize: 22)),
                  Expanded(
                    child: Text(l.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ]),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('Your listing is live — spread the word.',
                      style: TextStyle(
                          fontSize: 12.5, color: IjwiColors.muted)),
                ),
                const SizedBox(height: 6),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline, color: IjwiColors.green),
                  title: const Text('Post to Status', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Followers see it with a View Product link'),
                  onTap: _busy ? null : _shareToStatus,
                ),
                ListTile(
                  leading: const Icon(Icons.groups_outlined, color: IjwiColors.green),
                  title: const Text('Share to community', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Public feed or one of your communities'),
                  onTap: _busy ? null : _pickCommunity,
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, color: IjwiColors.green),
                  title: const Text('Send in chat', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Share a listing card in a conversation'),
                  onTap: _busy ? null : _pickConversation,
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy listing text', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: _busy ? null : _copyText,
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Share outside', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('WhatsApp, email and other apps'),
                  onTap: _busy ? null : _shareOutside,
                ),
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(_feedback!,
                        style: const TextStyle(color: IjwiColors.red, fontSize: 13)),
                  ),
              ]),
        ),
      ),
    );
  }
}
