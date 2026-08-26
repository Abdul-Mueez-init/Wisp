import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/providers/profile_provider.dart';

class OnboardingUsernameStep extends ConsumerStatefulWidget {
  const OnboardingUsernameStep({super.key, required this.onContinue});

  final void Function(String username) onContinue;

  @override
  ConsumerState<OnboardingUsernameStep> createState() =>
      _OnboardingUsernameStepState();
}

class _OnboardingUsernameStepState
    extends ConsumerState<OnboardingUsernameStep> {
  final _controller = TextEditingController();
  Timer? _debounce;

  bool _checking = false;
  bool? _isAvailable; // null = not checked yet
  String? _formatError;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Username shape isn't specified in ERD.md/PRD.md beyond "unique,
  // not null" — this is a reasonable, standard default (3-20 chars,
  // alphanumeric + underscore), flagged as an implementation choice.
  String? _formatValidation(String value) {
    if (value.length < 3) return 'At least 3 characters';
    if (value.length > 20) return 'Max 20 characters';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'Letters, numbers, underscore only';
    }
    return null;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _isAvailable = null;
      _checking = false;
      _formatError = value.isEmpty ? null : _formatValidation(value);
    });

    if (value.isEmpty || _formatError != null) return;

    setState(() => _checking = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final available = await ref
            .read(profileRepositoryProvider)
            .isUsernameAvailable(value);
        if (!mounted) return;
        setState(() {
          _checking = false;
          _isAvailable = available;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _isAvailable = null;
        });
      }
    });
  }

  bool get _canContinue =>
      _controller.text.isNotEmpty &&
      _formatError == null &&
      _isAvailable == true &&
      !_checking;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.air_rounded, color: AppColors.primary, size: 32),
        ),
        const SizedBox(height: 16),
        Text('Wisp', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Choose a unique username so friends can find you securely.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 48),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.buttonInput),
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: _controller,
            autocorrect: false,
            style: Theme.of(context).textTheme.bodyLarge,
            onChanged: _onChanged,
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Center(
                  widthFactor: 1,
                  child: Text('@', style: TextStyle(color: AppColors.outline)),
                ),
              ),
              suffixIcon: _checking
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_isAvailable == true
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : (_isAvailable == false
                          ? const Icon(Icons.cancel, color: AppColors.error)
                          : null)),
              hintText: 'username',
              hintStyle: const TextStyle(color: AppColors.outline),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _formatError ??
                    (_isAvailable == true
                        ? 'Username available'
                        : (_isAvailable == false ? 'Username taken' : '')),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _formatError != null || _isAvailable == false
                          ? AppColors.error
                          : AppColors.primary,
                    ),
              ),
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
            onPressed:
                _canContinue ? () => widget.onContinue(_controller.text) : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}
