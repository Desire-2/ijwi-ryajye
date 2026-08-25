import 'package:flutter/material.dart';

import '../../core/theme/design_system.dart';

/// Shared component library. Every screen composes these instead of
/// re-implementing loading/empty/error patterns.

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.actionLabel, this.onAction, super.key});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: const TextStyle(
                    color: IjwiColors.green, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title,
      required this.message, this.actionLabel, this.onAction, super.key});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
                color: IjwiColors.greenLight, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: IjwiColors.green),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: IjwiColors.muted, height: 1.4)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(
                onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {this.onRetry, super.key});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 36, color: IjwiColors.red),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: IjwiColors.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onRetry!(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ]),
      ),
    );
  }
}

class Skeleton extends StatefulWidget {
  const Skeleton({this.height = 72, this.width, super.key});

  final double height;
  final double? width;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.9).animate(_c),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: const Color(0xFFE4EDE7),
          borderRadius: BorderRadius.circular(IjwiRadius.md),
        ),
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  const StatChip({required this.icon, required this.label,
      required this.value, this.onTap, super.key});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(IjwiRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(IjwiRadius.md),
          border: Border.all(color: const Color(0xFFD7E2DA)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: IjwiColors.green),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            Text(label,
                style: const TextStyle(color: IjwiColors.muted, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: BoxDecoration(
          color: IjwiColors.green, borderRadius: BorderRadius.circular(12)),
      child: Text(count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class IjwiAvatar extends StatelessWidget {
  const IjwiAvatar(this.name,
      {this.size = 44, this.isGroup = false, super.key});

  final String name;
  final double size;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final letter =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor:
          isGroup ? IjwiColors.blue.withOpacity(0.15) : IjwiColors.greenLight,
      child: isGroup
          ? const Icon(Icons.groups_2, color: IjwiColors.blue)
          : Text(letter,
              style: const TextStyle(
                  color: IjwiColors.greenDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 17)),
    );
  }
}
