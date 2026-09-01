// lib/features/chat/data/message_event.dart
import '../../../models/message.dart';

/// Phase D (WISP_PERFORMANCE_HANDOFF.md §11) — the three things a
/// conversation-scoped `messages` Realtime channel can tell
/// `ChatMessagesController` about a single row, as opposed to the old
/// full-conversation `.stream()` approach's "here is the entire
/// conversation again, from scratch" full-snapshot re-emission on every
/// insert/update. One event = one row that actually changed.
enum MessageEventType { insert, update, delete }

class MessageEvent {
  const MessageEvent._(this.type, this.id, this.message);

  final MessageEventType type;
  final String id;

  /// Populated for [MessageEventType.insert]/[MessageEventType.update];
  /// null for [MessageEventType.delete] — Realtime's `DELETE` payload
  /// only reliably carries the primary key (`oldRecord`) unless the
  /// table has `REPLICA IDENTITY FULL` set, which `messages` doesn't
  /// (per seed.sql/ERD.md — not something this feature should require
  /// a schema change for just to get a full deleted row nothing in the
  /// app currently needs).
  final Message? message;

  factory MessageEvent.insert(Message message) =>
      MessageEvent._(MessageEventType.insert, message.id, message);

  factory MessageEvent.update(Message message) =>
      MessageEvent._(MessageEventType.update, message.id, message);

  factory MessageEvent.delete(String id) =>
      MessageEvent._(MessageEventType.delete, id, null);
}
