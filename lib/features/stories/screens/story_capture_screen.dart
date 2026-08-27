// lib/features/stories/screens/story_capture_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../data/story_repository.dart';
import '../providers/story_provider.dart';

/// Story capture entry point (plan.md Phase 6, batch 6a). No Stitch
/// screen exists for this specific step — built directly from
/// design.md's tokens, same approach used for the two flagged-unusable
/// call screens. Flow: pick photo/video (camera or gallery, same
/// picker pattern as `ChatInputBar`) → preview + optional caption →
/// post. Deliberately no video scrubbing/trim UI — this is a capture
/// confirmation step, not an editor.
///
/// Launched from the Status tab's "+" action, wired in 6b.
class StoryCaptureScreen extends ConsumerStatefulWidget {
  const StoryCaptureScreen({super.key});

  @override
  ConsumerState<StoryCaptureScreen> createState() => _StoryCaptureScreenState();
}

class _StoryCaptureScreenState extends ConsumerState<StoryCaptureScreen> {
  Uint8List? _bytes;
  String? _ext;
  bool _isVideo = false;
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(
            source: source, maxDuration: const Duration(seconds: 60))
        : await picker.pickImage(
            source: source,
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final cap =
        video ? StoryRepository.maxVideoBytes : StoryRepository.maxImageBytes;
    if (bytes.lengthInBytes > cap) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(video
            ? 'Video is too large (max 50MB).'
            : 'Image is too large (max 8MB).'),
      ));
      return;
    }

    final ext = picked.path.contains('.')
        ? picked.path.split('.').last
        : (video ? 'mp4' : 'jpg');
    setState(() {
      _bytes = bytes;
      _ext = ext;
      _isVideo = video;
    });
  }

  Future<void> _openSourceSheet({required bool video}) async {
    final source = await showModalBottomSheet<ImageSource>(
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
              title: Text(video ? 'Record video' : 'Camera'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text(video ? 'Video from gallery' : 'Photo gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source, video: video);
  }

  Future<void> _post() async {
    final bytes = _bytes;
    final ext = _ext;
    if (bytes == null || ext == null) return;
    final success = await ref.read(postStoryControllerProvider.notifier).post(
          bytes: bytes,
          fileExt: ext,
          caption: _captionController.text,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final failure = ref.read(postStoryControllerProvider).error;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$failure')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _bytes != null;
    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(title: const Text('New status')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageMargin),
          child: hasMedia ? _buildPreview() : _buildPicker(),
        ),
      ),
    );
  }

  Widget _buildPicker() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Share a photo or video that disappears in 24 hours.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.stackDefault),
        ElevatedButton.icon(
          onPressed: () => _openSourceSheet(video: false),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Photo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openSourceSheet(video: true),
          icon: const Icon(Icons.videocam_outlined),
          label: const Text('Video'),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final posting = ref.watch(postStoryControllerProvider).isLoading;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: _isVideo
                ? Container(
                    color: AppColors.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_outline,
                            size: 56, color: AppColors.primary),
                        SizedBox(height: 8),
                        Text('Video ready to post'),
                      ],
                    ),
                  )
                : Image.memory(_bytes!,
                    fit: BoxFit.cover, width: double.infinity),
          ),
        ),
        const SizedBox(height: AppSpacing.stackDefault),
        TextField(
          controller: _captionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Add a caption',
            filled: true,
            fillColor: AppColors.surfaceRaised,
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppRadius.buttonInput)),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: posting
                    ? null
                    : () => setState(() {
                          _bytes = null;
                          _ext = null;
                        }),
                child: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: posting ? null : _post,
                child: posting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.cream),
                      )
                    : const Text('Post'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
