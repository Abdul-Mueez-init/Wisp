ce transcription provider · DART
// lib/features/voice_notes/providers/voice_transcription_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../data/voice_transcription_repository.dart';
 
final voiceTranscriptionRepositoryProvider =
    Provider<VoiceTranscriptionRepository>((ref) {
  return const VoiceTranscriptionRepository();
});