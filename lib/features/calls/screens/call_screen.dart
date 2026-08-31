// lib/features/calls/screens/call_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/call_controller.dart';
import '../providers/call_session_state.dart';

/// Single screen covering the whole call lifecycle on this device —
/// outgoing ringing, incoming ringing, connecting, and active. Per
/// design.md's "Status Note", both the In-Call Video and Incoming
/// Video Call Stitch exports are explicitly flagged unusable (overlap
/// bugs / cropped export), so this is built directly from the token
/// system as instructed there: dark full-bleed background, cream
/// contact name, muted call-status text, circular outline-icon
/// controls, red for decline/end, `AppColors.primary` for accept.
class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callControllerProvider);

    // The controller drives itself back to idle once a call ends —
    // that's this screen's cue to pop, from wherever it was pushed.
    ref.listen<CallSessionState>(callControllerProvider, (previous, next) {
      if (previous != null && !previous.isIdle && next.isIdle) {
        if (context.canPop()) context.pop();
      }
    });

    final otherUserId = callState.otherUserId;
    final otherProfile = otherUserId != null
        ? ref.watch(profileByIdProvider(otherUserId)).value
        : null;
    final otherName =
        otherProfile?.displayName ?? otherProfile?.username ?? 'Wisp user';
    final rawAvatarPath = otherProfile?.avatarUrl;
    final otherAvatarUrl = rawAvatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(rawAvatarPath)
        : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.backgroundBase,
        body: SafeArea(
          child: switch (callState.phase) {
            CallPhase.active => _ActiveCallView(
                callState: callState,
                otherName: otherName,
                otherAvatarUrl: otherAvatarUrl,
              ),
            _ => _RingingOrConnectingView(
                callState: callState,
                otherName: otherName,
                otherAvatarUrl: otherAvatarUrl,
              ),
          },
        ),
      ),
    );
  }
}

/// Covers outgoingRinging / incomingRinging / connecting — the peer's
/// name/avatar centered, a status line, and the relevant action row.
class _RingingOrConnectingView extends ConsumerWidget {
  const _RingingOrConnectingView({
    required this.callState,
    required this.otherName,
    required this.otherAvatarUrl,
  });

  final CallSessionState callState;
  final String otherName;
  final String? otherAvatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusText = switch (callState.phase) {
      CallPhase.outgoingRinging =>
        callState.isVideo ? 'Video calling…' : 'Calling…',
      CallPhase.incomingRinging =>
        callState.isVideo ? 'Incoming video call' : 'Incoming call',
      CallPhase.connecting => 'Connecting…',
      _ => '',
    };

    // The caller's mic is already live at this point — startCall() calls
    // session.init() (which grabs the mic) before the offer is even
    // sent, so muting while it's still ringing is functionally real,
    // not cosmetic. The callee side has no session yet until they tap
    // Accept, so there's nothing to mute during incomingRinging.
    final hasLiveSession =
        ref.read(callControllerProvider.notifier).session != null;

    return Column(
      children: [
        const Spacer(flex: 2),
        CircleAvatar(
          radius: 56,
          backgroundColor: AppColors.surfaceContainerHigh,
          backgroundImage:
              otherAvatarUrl != null ? NetworkImage(otherAvatarUrl!) : null,
          child: otherAvatarUrl == null
              ? Text(
                  otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                  style:
                      const TextStyle(fontSize: 40, color: AppColors.primary),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.stackDefault),
        Text(
          otherName,
          style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: AppColors.cream) ??
              const TextStyle(fontSize: 20, color: AppColors.cream),
        ),
        const SizedBox(height: AppSpacing.stackCompact),
        Text(
          statusText,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const Spacer(flex: 3),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.stackDefault * 2),
          child: switch (callState.phase) {
            CallPhase.incomingRinging => _IncomingActionRow(
                ref: ref,
              ),
            _ => _CancelActionRow(
                ref: ref,
                showMute: hasLiveSession,
                isMuted: callState.isMuted,
              ),
          },
        ),
      ],
    );
  }
}

class _IncomingActionRow extends StatelessWidget {
  const _IncomingActionRow({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallActionButton(
          icon: Icons.call_end,
          backgroundColor: AppColors.error,
          onTap: () => ref.read(callControllerProvider.notifier).declineCall(),
          label: 'Decline',
        ),
        _CallActionButton(
          icon: Icons.call,
          backgroundColor: AppColors.primary,
          iconColor: AppColors.onPrimary,
          onTap: () => ref.read(callControllerProvider.notifier).answerCall(),
          label: 'Accept',
        ),
      ],
    );
  }
}

class _CancelActionRow extends StatelessWidget {
  const _CancelActionRow({
    required this.ref,
    required this.showMute,
    required this.isMuted,
  });
  final WidgetRef ref;
  final bool showMute;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    if (!showMute) {
      return _CallActionButton(
        icon: Icons.call_end,
        backgroundColor: AppColors.error,
        onTap: () => ref.read(callControllerProvider.notifier).endCall(),
        label: 'Cancel',
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CallActionButton(
          icon: isMuted ? Icons.mic_off : Icons.mic,
          backgroundColor: AppColors.surfaceContainerHigh,
          onTap: () => ref.read(callControllerProvider.notifier).toggleMute(),
          label: isMuted ? 'Unmute' : 'Mute',
        ),
        _CallActionButton(
          icon: Icons.call_end,
          backgroundColor: AppColors.error,
          onTap: () => ref.read(callControllerProvider.notifier).endCall(),
          label: 'Cancel',
        ),
      ],
    );
  }
}

/// Active-call view: video renderers side by side (picture-in-picture
/// self-view) for video calls, a plain avatar for audio calls, plus
/// mute/camera/end controls per design.md's Buttons/Status tokens.
class _ActiveCallView extends ConsumerWidget {
  const _ActiveCallView({
    required this.callState,
    required this.otherName,
    required this.otherAvatarUrl,
  });

  final CallSessionState callState;
  final String otherName;
  final String? otherAvatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(callControllerProvider.notifier).session;

    return Stack(
      children: [
        Positioned.fill(
          child: callState.isVideo && session != null
              ? RTCVideoView(
                  session.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Container(
                  color: AppColors.backgroundBase,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        backgroundImage: otherAvatarUrl != null
                            ? NetworkImage(otherAvatarUrl!)
                            : null,
                        child: otherAvatarUrl == null
                            ? Text(
                                otherName.isNotEmpty
                                    ? otherName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 40, color: AppColors.primary),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.stackDefault),
                      Text(
                        otherName,
                        style: const TextStyle(
                            fontSize: 20, color: AppColors.cream),
                      ),
                    ],
                  ),
                ),
        ),
        if (callState.isVideo && session != null && !callState.isCameraOff)
          Positioned(
            top: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 100,
                height: 140,
                child: RTCVideoView(
                  session.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpacing.stackDefault * 2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallActionButton(
                icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                backgroundColor: AppColors.surfaceContainerHigh,
                onTap: () =>
                    ref.read(callControllerProvider.notifier).toggleMute(),
                label: callState.isMuted ? 'Unmute' : 'Mute',
              ),
              if (callState.isVideo)
                _CallActionButton(
                  icon: callState.isCameraOff
                      ? Icons.videocam_off
                      : Icons.videocam,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  onTap: () =>
                      ref.read(callControllerProvider.notifier).toggleCamera(),
                  label: callState.isCameraOff ? 'Camera on' : 'Camera off',
                ),
              _CallActionButton(
                icon: Icons.call_end,
                backgroundColor: AppColors.error,
                onTap: () =>
                    ref.read(callControllerProvider.notifier).endCall(),
                label: 'End',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color? iconColor;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: backgroundColor,
            child: Icon(icon, color: iconColor ?? AppColors.cream, size: 26),
          ),
        ),
        const SizedBox(height: AppSpacing.stackCompact),
        Text(
          label,
          style:
              const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}
