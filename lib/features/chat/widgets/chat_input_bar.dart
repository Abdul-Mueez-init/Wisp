import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Floating chat input per design.md "Inputs" component: Surface-Raised
/// background, hairline border, pill shape, 8px margin from safe area.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.sending,
    this.onTextChanged,
  });

  final void Function(String text) onSend;
  final bool sending;

  /// Fired on every keystroke (and once with '' right after a send) so
  /// the typing indicator can debounce off of it. Optional — omitting
  /// it just means no typing signal is sent.
  final void Function(String text)? onTextChanged;

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
    // controller.clear() doesn't fire TextField.onChanged on its own —
    // signal "stopped typing" explicitly.
    widget.onTextChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          8,
          AppSpacing.pageMargin,
          8,
        ),
        child: Row(
          children: [
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
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
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
                  backgroundColor: AppColors.primaryContainer,
                ),
                onPressed: widget.sending ? null : _submit,
                icon: widget.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cream,
                        ),
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
