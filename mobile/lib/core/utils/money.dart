import 'package:intl/intl.dart';

/// All backend amounts are integer minor units (100 minor = 1 RWF).
String formatRwf(int minor, {bool withSymbol = true}) {
  final value = minor / 100;
  final formatted = NumberFormat.decimalPattern('en').format(value);
  return withSymbol ? '$formatted RWF' : formatted;
}

String compactRwf(int minor) {
  final value = minor / 100;
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M RWF';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K RWF';
  }
  return '${value.toStringAsFixed(0)} RWF';
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('dd MMM').format(time);
}
