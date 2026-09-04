import 'package:intl/intl.dart';

/// All backend amounts are integer minor units (100 minor = 1 RWF, or the
/// currency's own minor unit). [currencyCode] is always rendered with the
/// amount so conversions are never silently assumed.
String formatMoney(int minor, String currencyCode, {bool withSymbol = true}) {
  final value = minor / 100;
  final formatted = NumberFormat.decimalPattern('en').format(value);
  return withSymbol ? '$formatted $currencyCode' : formatted;
}

String formatRwf(int minor, {bool withSymbol = true}) =>
    formatMoney(minor, 'RWF', withSymbol: withSymbol);

String compactMoney(int minor, String currencyCode) {
  final value = minor / 100;
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M $currencyCode';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K $currencyCode';
  }
  return '${value.toStringAsFixed(0)} $currencyCode';
}

String compactRwf(int minor) => compactMoney(minor, 'RWF');

/// Compact quantity: 1500 kg → "1.5 t", 250000 → "250 t", 12 → "12 kg".
String formatQuantity(double value, String unitCode) {
  if (unitCode == 'tonnes' || unitCode == 't') {
    return '${_trim(value)} t';
  }
  if (unitCode == 'kg' && value >= 1000) {
    return '${_trim(value / 1000)} t';
  }
  return '${_trim(value)} $unitCode';
}

String _trim(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('dd MMM').format(time);
}

String timeAgoIso(String? iso) {
  if (iso == null) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  return timeAgo(t.toLocal());
}