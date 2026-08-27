// lib/features/chat/widgets/chat_input_bar.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart' show Amplitude;

import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../contacts/screens/contact_picker_screen.dart';
import '../../voice_notes/providers/voice_note_provider.dart';
import '../../voice_notes/widgets/voice_record_button.dart';
import '../../location/providers/live_location_provider.dart';

enum _AttachmentChoice {
  photoCamera,
  photoGallery,
  videoCamera,
  videoGallery,
  document,
  contact,
  location,
}

/// Floating chat input per design.md "Inputs" component. Batch 5c added
/// the mic/send swap; Batch 5d adds "Contact" to the attachment sheet.
class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.sending,
    required this.onSendImage,
    required this.onSendVideo,
    required this.onSendDocument,
    required this.onSendVoice,
    required this.onShareContact,
    required this.onSendCurrentLocation,
    required this.onStartLiveLocation,
    required this.uploadingMedia,
    this.onTextChanged,
  });

  final void Function(String text) onSend;
  final bool sending;
  final void Function(String text)? onTextChanged;
  final Future<void> Function(Uint8List bytes, String fileExt) onSendImage;
  final Future<void> Function(Uint8List bytes, String fileExt) onSendVideo;
  final Future<void> Function(Uint8List bytes, String fileName) onSendDocument;
  final Future<void> Function(Uint8List bytes) onSendVoice;
  final Future<void> Function(Profile profile) onShareContact;
  final Future<void> Function() onSendCurrentLocation;
  final Future<void> Function(LiveLocationDuration duration)
      onStartLiveLocation;

  /// True while an attachment is uploading — disables "+" and voice
  /// recording so a second upload can't be queued mid-flight (no
  /// upload queue exists yet).
  final bool uploadingMedia;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty || widget.sending) return;
    widget.onSend(text);
    _controller.clear();
    widget.onTextChanged?.call('');
  }

  Future<void> _openAttachmentSheet() async {
    if (widget.uploadingMedia) return;
    final choice = await showModalBottomSheet<_AttachmentChoice>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Camera'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.photoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Photo gallery'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.photoGallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_outlined, color: AppColors.primary),
              title: const Text('Record video'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.videoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined,
                  color: AppColors.primary),
              title: const Text('Video from gallery'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.videoGallery),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.primary),
              title: const Text('Document'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.document),
            ),
            ListTile(
              leading:
                  const Icon(Icons.person_outline, color: AppColors.primary),
              title: const Text('Contact'),
              onTap: () => Navigator.of(context).pop(_AttachmentChoice.contact),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: AppColors.primary),
              title: const Text('Location'),
              onTap: () =>
                  Navigator.of(context).pop(_AttachmentChoice.location),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    switch (choice) {
      case _AttachmentChoice.photoCamera:
        await _pickAndSendImage(ImageSource.camera);
      case _AttachmentChoice.photoGallery:
        await _pickAndSendImage(ImageSource.gallery);
      case _AttachmentChoice.videoCamera:
        await _pickAndSendVideo(ImageSource.camera);
      case _AttachmentChoice.videoGallery:
        await _pickAndSendVideo(ImageSource.gallery);
      case _AttachmentChoice.document:
        await _pickAndSendDocument();
      case _AttachmentChoice.contact:
        await _pickAndShareContact();
      case _AttachmentChoice.location:
        await _openLocationSheet();
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
    await widget.onSendImage(bytes, ext);
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.path.contains('.') ? picked.path.split('.').last : 'mp4';
    await widget.onSendVideo(bytes, ext);
  }

  Future<void> _pickAndSendDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return; // shouldn't happen with withData: true
    await widget.onSendDocument(bytes, file.name);
  }

  Future<void> _pickAndShareContact() async {
    final profile = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (profile == null) return;
    await widget.onShareContact(profile);
  }

  Future<void> _openLocationSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: AppColors.primary),
              title: const Text('Current location'),
              subtitle: const Text('Send your location once'),
              onTap: () => Navigator.of(context).pop('current'),
            ),
            ListTile(
              leading: const Icon(Icons.location_history_outlined,
                  color: AppColors.primary),
              title: const Text('Live location'),
              subtitle: const Text('Share your location as you move'),
              onTap: () => Navigator.of(context).pop('live'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'current') {
      await widget.onSendCurrentLocation();
    } else if (choice == 'live') {
      await _openDurationSheet();
    }
  }

  Future<void> _openDurationSheet() async {
    final duration = await showModalBottomSheet<LiveLocationDuration>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Share live location for',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            for (final option in LiveLocationDuration.values)
              ListTile(
                leading:
                    const Icon(Icons.timer_outlined, color: AppColors.primary),
                title: Text(option.label),
                onTap: () => Navigator.of(context).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (duration != null) {
      await widget.onStartLiveLocation(duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(voiceRecordingControllerProvider);
    final isRecording = recordingState.phase != VoiceRecordingPhase.idle;
    final isCancelling = recordingState.phase == VoiceRecordingPhase.cancelling;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin, 8, AppSpacing.pageMargin, 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: widget.uploadingMedia
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: isRecording ? null : _openAttachmentSheet,
                      icon: Icon(
                        Icons.add_circle_outline,
                        color:
                            isRecording ? AppColors.outline : AppColors.primary,
                      ),
                    ),
            ),
            Expanded(
              child: isRecording
                  ? _RecordingRow(
                      elapsed: recordingState.elapsed,
                      cancelling: isCancelling,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color:
                              AppColors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: Theme.of(context).textTheme.bodyLarge,
                        onChanged: widget.onTextChanged,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                              color: AppColors.onSurfaceVariant
                                  .withValues(alpha: 0.6)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: _hasText
                  ? IconButton.filled(
                      style: IconButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer),
                      onPressed: widget.sending ? null : _submit,
                      icon: widget.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.cream),
                            )
                          : const Icon(Icons.send_rounded,
                              color: AppColors.cream),
                    )
                  : VoiceRecordButton(
                      enabled: !widget.uploadingMedia && !widget.sending,
                      onRecorded: widget.onSendVoice,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the text field while recording: elapsed timer, a
/// live mic-level dot (via the repository's amplitude stream), and the
/// "slide to cancel" hint — reddens once the drag has crossed
/// [VoiceRecordButton]'s cancel threshold.
class _RecordingRow extends ConsumerWidget {
  const _RecordingRow({required this.elapsed, required this.cancelling});

  final Duration elapsed;
  final bool cancelling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amplitudeStream =
        ref.read(voiceRecordingControllerProvider.notifier).amplitudeStream;
    final color = cancelling ? AppColors.error : AppColors.primary;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          StreamBuilder<Amplitude>(
            stream: amplitudeStream,
            builder: (context, snapshot) {
              final level = snapshot.hasData
                  ? ((snapshot.data!.current + 45) / 45).clamp(0.15, 1.0)
                  : 0.4;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 10 + (level * 6),
                height: 10 + (level * 6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(_formatElapsed(elapsed),
              style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Icon(Icons.chevron_left_rounded, size: 18, color: color),
          Text(
            'Slide to cancel',
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
