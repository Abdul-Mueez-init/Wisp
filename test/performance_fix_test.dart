// test/performance_fix_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/features/chat/providers/message_provider.dart';

void main() {
  group('ChatMessagesState tests', () {
    test('default state initialized properly', () {
      const state = ChatMessagesState();
      expect(state.messages, isEmpty);
      expect(state.isLoadingInitial, isTrue);
      expect(state.isLoadingMore, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.error, isNull);
    });

    test('copyWith updates fields correctly', () {
      const state = ChatMessagesState();
      final updated = state.copyWith(
        isLoadingInitial: false,
        hasMore: false,
      );
      expect(updated.isLoadingInitial, isFalse);
      expect(updated.hasMore, isFalse);
      expect(updated.messages, isEmpty);
    });
  });
}
