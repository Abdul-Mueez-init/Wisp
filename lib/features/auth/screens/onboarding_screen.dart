import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/providers/profile_provider.dart';
import '../widgets/onboarding_details_step.dart';
import '../widgets/onboarding_username_step.dart';

/// Two-step onboarding wizard: username (Phase 1, matches Stitch export)
/// → display name/avatar/language (built from design tokens, no export
/// exists for this step — see flagged note in project chat).
/// Per PRD.md §4, this runs once after signup, before the app is usable.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  String? _username;

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);

    ref.listen(onboardingControllerProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.pageMargin),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _step == 0
                    ? OnboardingUsernameStep(
                        key: const ValueKey('username-step'),
                        onContinue: (username) {
                          setState(() {
                            _username = username;
                            _step = 1;
                          });
                        },
                      )
                    : OnboardingDetailsStep(
                        key: const ValueKey('details-step'),
                        isSubmitting: onboardingState.isLoading,
                        onFinish: ({
                          required displayName,
                          required avatarBytes,
                          required avatarExt,
                          required preferredLanguage,
                        }) {
                          ref
                              .read(onboardingControllerProvider.notifier)
                              .completeOnboarding(
                                username: _username!,
                                displayName: displayName,
                                avatarBytes: avatarBytes,
                                avatarExt: avatarExt,
                                preferredLanguage: preferredLanguage,
                              );
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
