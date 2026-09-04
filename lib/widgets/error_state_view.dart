import 'package:flutter/material.dart';

import '../core/errors/friendly_message.dart';
import '../core/theme/app_theme.dart';

/// Global/shared widget per architecture.md ("`widgets/` — truly
/// global/shared widgets only"). Phase 11 polish pass: centralizes the
/// error-state UI that was previously duplicated ad hoc (and showing
/// raw `'$e'` text) across `calls_tab_screen.dart`,
/// `status_list_screen.dart`, `group_members_screen.dart`,
/// `profile_settings_screen.dart`, and `chat_detail_screen.dart`.
///
/// Deliberately simple: an icon, one friendly line (via
/// [friendlyErrorMessage] — never the raw exception), and an optional
/// "Try again" button. [onRetry] is optional because a couple of call
/// sites (e.g. the Calls tab, which already self-heals via
/// `resilient_realtime_stream.dart`'s backoff) don't need a manual
/// retry action — but most do, and previously had none at all.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  /// The raw error (a [Failure], a Supabase exception, or anything
  /// else) — mapped to friendly copy internally, never shown raw.
  final Object error;

  /// Called when the user taps "Try again". Omit to hide the button
  /// (e.g. when the surrounding screen already retries automatically).
  final VoidCallback? onRetry;

  /// Tighter padding/icon size for use inside a sheet or a smaller
  /// panel rather than a full screen body.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final message = friendlyErrorMessage(error);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(
          compact ? AppSpacing.stackDefault : AppSpacing.pageMargin,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: compact ? 28 : 36,
            ),
            const SizedBox(height: AppSpacing.stackDefault),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.stackDefault),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
