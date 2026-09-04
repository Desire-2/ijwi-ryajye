import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/design_system.dart';
import 'community_models.dart';

/// Visual treatment for each agricultural post type.
/// Uses recognizable markers + contextual colors (never color alone).
class PostTypeStyle {
  static const List<String> reactionEmojis = [
    '❤️', '👍', '👏', '🙏', '🌱', '🌾', '🚜', '💡', '🔥',
  ];

  static IconData icon(String type) {
    switch (type) {
      case 'question':
        return Icons.help_outline;
      case 'poll':
        return Icons.bar_chart;
      case 'event':
        return Icons.event;
      case 'opportunity':
        return Icons.local_fire_department_outlined;
      case 'harvest':
        return Icons.eco_outlined;
      case 'product':
        return Icons.storefront_outlined;
      case 'farm_update':
        return Icons.spa_outlined;
      case 'announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.notes;
    }
  }

  static Color color(String type) {
    switch (type) {
      case 'question':
        return IjwiColors.blue;
      case 'poll':
        return const Color(0xFF7C3AED);
      case 'event':
        return IjwiColors.amber;
      case 'opportunity':
        return IjwiColors.red;
      case 'harvest':
        return IjwiColors.amber;
      case 'product':
        return const Color(0xFF0E7490);
      case 'farm_update':
        return IjwiColors.green;
      case 'announcement':
        return IjwiColors.red;
      default:
        return IjwiColors.green;
    }
  }

  static String label(String type) {
    switch (type) {
      case 'question':
        return 'Question';
      case 'poll':
        return 'Poll';
      case 'event':
        return 'Event';
      case 'opportunity':
        return 'Opportunity';
      case 'harvest':
        return 'Harvest';
      case 'product':
        return 'Product';
      case 'farm_update':
        return 'Farm update';
      case 'announcement':
        return 'Announcement';
      default:
        return 'Post';
    }
  }
}

/// Serves as a semantic label wrapper for screen readers.
void announceToAccessibility(BuildContext context, String message) {
  SemanticsService.announce(message, Directionality.of(context));
}
