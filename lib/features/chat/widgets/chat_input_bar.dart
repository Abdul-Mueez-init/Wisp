import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';

enum _AttachmentChoice {
  photoCamera,
  photoGallery,
  videoCamera,
  videoGallery,
  document,
}

/// Floating chat input per design.md "Inputs" component. The "+"
/// attachment sheet grows across Batches 5a–5e per the handoff doc;
/// Voice/Contact/Location join the same sheet in 5c/5d/5e.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.sending,
    required this.onSendImage,
    required this.onSendVideo,
    required this.onSendDocument,
    required this.uploadingMedia,
    this.onTextChanged,
  });

  final void Function(String text) onSend;
  final bool sending;
  final void Function(String text)? onTextChanged;
  final Future<void> Function(Uint8List bytes, String fileExt) onSendImage;
  final Future<void> Function(Uint8List bytes, String fileExt) onSendVideo;
  final Future<void> Function(Uint8List bytes, String fileName) onSendDocument;

  /// True while an attachment is uploading — disables "+" so a second
  /// upload can't be queued mid-flight (no upload queue exists yet).
  final bool uploadingMedia;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();

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
            const SizedBox(height: 8),
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

  @override
  Widget build(BuildContext context) {
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
                      onPressed: _openAttachmentSheet,
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.primary),
                    ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
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
                        color:
                            AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
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
              child: IconButton.filled(
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
                    : const Icon(Icons.send_rounded, color: AppColors.cream),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
