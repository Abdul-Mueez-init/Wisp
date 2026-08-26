import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';

/// Language options aren't specified in PRD.md/ERD.md beyond
/// "preferred_language, default 'en', editable in settings" — this is
/// a reasonable starter list covering common cases for AI Feature 1
/// (translation), not a locked design decision. Easy to extend later.
const _languageOptions = <(String code, String label)>[
  ('en', 'English'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('pt', 'Portuguese'),
  ('ar', 'Arabic'),
  ('hi', 'Hindi'),
  ('ur', 'Urdu'),
  ('zh', 'Chinese'),
  ('ja', 'Japanese'),
];

class OnboardingDetailsStep extends StatefulWidget {
  const OnboardingDetailsStep({
    super.key,
    required this.onFinish,
    required this.isSubmitting,
  });

  final void Function({
    required String? displayName,
    required Uint8List? avatarBytes,
    required String? avatarExt,
    required String preferredLanguage,
  }) onFinish;
  final bool isSubmitting;

  @override
  State<OnboardingDetailsStep> createState() => _OnboardingDetailsStepState();
}

class _OnboardingDetailsStepState extends State<OnboardingDetailsStep> {
  final _displayNameController = TextEditingController();
  String _selectedLanguage = 'en';
  Uint8List? _avatarBytes;
  String? _avatarExt;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _avatarBytes = bytes;
      _avatarExt = picked.path.split('.').last;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Set up your profile',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Display name and photo are optional — you can add these later.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: _avatarBytes != null
                ? ClipOval(
                    child: Image.memory(_avatarBytes!, fit: BoxFit.cover))
                : const Icon(Icons.add_a_photo_outlined,
                    color: AppColors.outline, size: 28),
          ),
        ),
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Display name',
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _displayNameController,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceRaised,
            hintText: 'Your name',
            hintStyle: TextStyle(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.buttonInput),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Preferred language',
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.buttonInput),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedLanguage,
              dropdownColor: AppColors.surfaceContainerHigh,
              style: Theme.of(context).textTheme.bodyLarge,
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: AppColors.outline),
              items: _languageOptions
                  .map((lang) =>
                      DropdownMenuItem(value: lang.$1, child: Text(lang.$2)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedLanguage = value);
              },
            ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: widget.isSubmitting
                ? null
                : () => widget.onFinish(
                      displayName: _displayNameController.text,
                      avatarBytes: _avatarBytes,
                      avatarExt: _avatarExt,
                      preferredLanguage: _selectedLanguage,
                    ),
            child: widget.isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.cream),
                  )
                : const Text('Finish'),
          ),
        ),
      ],
    );
  }
}
