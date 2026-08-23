import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/realtime/socket_service.dart';
import '../auth/auth_controller.dart';

class ChatMessage {
  ChatMessage.fromJson(Map<String, dynamic> j, {required String? myUserId})
      : id = j['id'] as String,
        senderId =
            (j['sender'] as Map<String, dynamic>?)?['id'] as String? ??
                j['sender_id'] as String?,
        body = j['body_text'] as String? ?? '',
        type = j['message_type'] as String? ?? 'text',
        replyTo = j['reply_to_message_id'] as String?,
        createdAt =
            DateTime.tryParse(j['created_at'] as String? ?? '') ??
                DateTime.now(),
        entity = j['entity'] is Map<String, dynamic>
            ? (j['entity'] as Map<String, dynamic>)
            : null,
        attachments = (j['attachments'] as List? ?? const [])
            .map((a) => a as Map<String, dynamic>)
            .toList(),
        mine = j['sender_id'] == myUserId ||
            ((j['sender'] as Map<String, dynamic>?)?['id']) == myUserId,
        serverSequence = (j['server_sequence'] as num?)?.toInt() ?? 0;

  final String id;
  final String? senderId;
  final String body;
  final String type;
  final String? replyTo;
  final DateTime createdAt;
  final Map<String, dynamic>? entity;
  final List<Map<String, dynamic>> attachments;
  bool mine;
  final int serverSequence;

  bool get isCard =>
      type.endsWith('_card') || (type == 'listing' || type == 'product');
}

/// A listing reference used by the attachment sheet ("share a product").
class ListingRef {
  ListingRef.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? 'Listing',
        priceMinor = (j['price_minor'] as num?)?.toInt() ?? 0,
        unit = j['unit_code'] as String? ?? 'kg',
        emoji = (j['product'] as Map<String, dynamic>?)?['emoji'] as String?;

  final String id;
  final String title;
  final int priceMinor;
  final String unit;
  final String? emoji;
}
