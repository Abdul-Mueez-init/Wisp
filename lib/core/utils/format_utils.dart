/// Shared formatting helpers per architecture.md `core/utils/`.
String formatFileSize(int? bytes) {
  if (bytes == null) return '';
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// WhatsApp-style relative day formatting for the chat list preview
/// (Batch 6b) — today: "3:41 PM", within the last 6 days: "Mon", older:
/// "14/03/25".
String formatChatTimestamp(DateTime dateTime) {
  final now = DateTime.now();
  final local = dateTime.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(date).inDays;

  if (daysAgo == 0) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
  if (daysAgo < 7) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[local.weekday - 1];
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = (local.year % 100).toString().padLeft(2, '0');
  return '$day/$month/$year';
}

/// Short relative-time label for content that's always < 24h old
/// (stories) — "Just now" / "5m ago" / "3h ago". Falls back to
/// [formatChatTimestamp] past 24h as a defensive case only — a story
/// should never actually reach that age given client-side expiry.
String formatRelativeShort(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime.toLocal());
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return formatChatTimestamp(dateTime);
}
