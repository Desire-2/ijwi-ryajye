import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../shared/widgets/ui.dart';
import 'community_models.dart';
import 'community_service.dart';
import 'post_card.dart';

/// Channel broadcast view: listing of channel posts and their comments.
class ChannelDetailScreen extends ConsumerStatefulWidget {
  const ChannelDetailScreen({required this.channelId, super.key});

  final String channelId;

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen> {
  ChannelProfile? _channel;
  List<Post>? _posts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(communityServiceProvider);
    try {
      final channels = await svc.listChannels();
      final ch = channels.firstWhere(
          (c) => c.id == widget.channelId,
          orElse: () => channels.isNotEmpty
              ? channels.first
              : ChannelProfile(
                  id: widget.channelId, name: 'Channel'));
      final posts = await svc.channelPosts(widget.channelId);
      if (!mounted) return;
      setState(() {
        _channel = ch;
        _posts = posts;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiClient.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = _channel;
    return Scaffold(
      appBar: AppBar(title: Text(ch?.name ?? 'Channel')),
      body: _error != null && ch == null
          ? ErrorBox(_error!, onRetry: _load)
          : ch == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Container(
                        color: IjwiColors.greenLight,
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          const Icon(Icons.campaign_outlined,
                              size: 48, color: IjwiColors.blue),
                          const SizedBox(height: 8),
                          Text(ch.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          if (ch.description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(ch.description,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: IjwiColors.muted, height: 1.4)),
                            ),
                          const SizedBox(height: 8),
                          Text('${ch.subscriberCount} followers',
                              style: const TextStyle(
                                  color: IjwiColors.green,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(160, 40)),
                            onPressed: () async {
                              try {
                                if (ch.followed) {
                                  await ref
                                      .read(communityServiceProvider)
                                      .unfollowChannel(ch.id);
                                } else {
                                  await ref
                                      .read(communityServiceProvider)
                                      .followChannel(ch.id);
                                }
                                await _load();
                              } catch (_) {}
                            },
                            icon: Icon(ch.followed
                                ? Icons.notifications_active
                                : Icons.add_alert),
                            label: Text(
                                ch.followed ? 'Following' : 'Follow channel'),
                          ),
                        ]),
                      ),
                      SectionHeader('Posts'),
                      if (_posts == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Skeleton(height: 120),
                        )
                      else if (_posts!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No posts from this channel yet',
                                  style:
                                      TextStyle(color: IjwiColors.muted))),
                        )
                      else
                        for (final p in _posts!)
                          PostCard(post: p, onChanged: (_) {}),
                    ],
                  ),
                ),
    );
  }
}
