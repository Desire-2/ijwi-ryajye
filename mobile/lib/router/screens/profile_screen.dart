import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/media/media_models.dart';
import '../../core/media/media_picker.dart';
import '../../core/media/media_repository.dart';
import '../../core/media/media_widgets.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/design_system.dart';
import '../../features/auth/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.watch(trProvider);
    final user = ref.watch(authProvider).valueOrNull;
    final isFarmer = user?.primaryRole != 'BUYER';

    return Scaffold(
      appBar: AppBar(title: Text(tr('tab_profile'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _ProfilePhoto(
                  photoUrl: user?.profilePhotoUrl,
                  onTap: () => _changePhoto(context, ref)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(user?.fullName ?? '—',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${user?.phone ?? ''}',
                        style: const TextStyle(color: IjwiColors.muted)),
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: IjwiColors.greenLight,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(user?.primaryRole ?? '',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: IjwiColors.greenDark)),
                    ),
                  ])),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _Section('Trading'),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(isFarmer ? 'My listings' : 'Saved searches'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/sell'),
        ),
        ListTile(
          leading: const Icon(Icons.local_offer_outlined),
          title: const Text('Offers'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/offers'),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Orders'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/orders'),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(tr('wallet')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/wallet'),
        ),
        _Section('Assistant & alerts'),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Ask Ijwi assistant'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/intelligence?tab=3'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/notifications'),
        ),
        if (user?.primaryRole == 'ADMIN') ...[
          _Section('Admin'),
          ListTile(
            leading: const Icon(Icons.storefront_outlined,
                color: IjwiColors.greenDark),
            title: const Text('Marketplace catalogue'),
            subtitle: const Text('Add or edit categories, products and units'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/catalog'),
          ),
        ],
        _Section('App'),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text('Language / Ururimi'),
          trailing: DropdownButton<String>(
            underline: const SizedBox.shrink(),
            value: ref.watch(i18nProvider).valueOrNull?.locale ?? 'rw',
            items: const [
              DropdownMenuItem(value: 'rw', child: Text('Kinyarwanda')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'sw', child: Text('Kiswahili')),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(i18nProvider.notifier).changeLocale(v);
              }
            },
          ),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.logout, color: IjwiColors.red),
          title: const Text('Log out', style: TextStyle(color: IjwiColors.red)),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Log out?'),
                content: const Text(
                    'Offline drafts stay on this phone until you log back in.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out')),
                ],
              ),
            );
            if (confirmed == true) {
              await ref.read(authProvider.notifier).logout();
            }
          },
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text('Ijwi Ryajye v1.0 · voice of the farmer',
              style: TextStyle(fontSize: 11.5, color: IjwiColors.muted)),
        ),
      ]),
    );
  }
}

/// Avatar with a camera overlay. Tapping lets the user take or pick a photo,
/// which uploads through the shared [MediaRepository] and PATCHes the
/// profile key.
class _ProfilePhoto extends ConsumerWidget {
  const _ProfilePhoto({required this.photoUrl, required this.onTap});

  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget avatar;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final url = ref.read(mediaRepositoryProvider).resolveUrl(photoUrl!);
      avatar = CircleAvatar(
        radius: 26,
        child: ClipOval(
          child: SizedBox(
            width: 52,
            height: 52,
            child: IjwiImage(url: url, fit: BoxFit.cover),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: 26,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(_initial(ref),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
      );
    }
    return Stack(clipBehavior: Clip.none, children: [
      GestureDetector(onTap: onTap, child: avatar),
      Positioned(
        right: -2,
        bottom: -2,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: IjwiColors.greenDark,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.photo_camera_outlined,
                size: 14, color: Colors.white),
          ),
        ),
      ),
    ]);
  }

  String _initial(WidgetRef ref) =>
      (ref.read(authProvider).valueOrNull?.fullName.isNotEmpty == true
              ? ref.read(authProvider).valueOrNull!.fullName[0]
              : '?')
          .toUpperCase();
}

Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
  final action = await showMediaPickerSheet(context,
      actions: const [MediaPickAction.camera, MediaPickAction.gallery]);
  if (action == null || !context.mounted) return;
  try {
    LocalMediaItem? picked;
    if (action == MediaPickAction.camera) {
      final perm = await ref.read(mediaPermissionsProvider).camera();
      if (perm != PermissionState.granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Camera permission is required to take a profile photo.')));
        }
        return;
      }
      picked = await ref.read(mediaPickerProvider).takePhoto();
    } else {
      final photos = await ref.read(mediaPickerProvider).pickImages(limit: 1);
      picked = photos.isEmpty ? null : photos.first;
    }
    if (picked == null) return;
    final media = await ref.read(mediaRepositoryProvider).upload(picked);
    if (!context.mounted) return;
    await ref.read(authProvider.notifier).updateProfilePhoto(media.storageKey);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Could not update photo: ${ApiClient.errorMessage(e)}')));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 4),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: IjwiColors.muted)),
    );
  }
}
