import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zenbox/theme/theme.dart';

class TopNotification {
  static OverlayEntry? _activeEntry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline,
    Color? accentColor,
    Duration duration = const Duration(milliseconds: 2800),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.of(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: message,
        icon: icon,
        accentColor: accentColor ?? sage,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: dismiss,
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, () {
      dismiss();
    });
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_activeEntry != null) {
      try {
        _activeEntry?.remove();
      } catch (_) {}
      _activeEntry = null;
    }
  }
}

class _TopNotificationWidget extends StatefulWidget {
  const _TopNotificationWidget({
    required this.message,
    required this.icon,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  final String message;
  final IconData icon;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (mounted) {
      await _animController.reverse();
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 18,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Dismissible(
                key: const Key('top_notification_dismiss'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440, minWidth: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.6), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 16, color: widget.accentColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: cream,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null && widget.onAction != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 24),
                            foregroundColor: widget.accentColor,
                          ),
                          onPressed: () {
                            widget.onAction?.call();
                            _handleDismiss();
                          },
                          child: Text(
                            widget.actionLabel!,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _handleDismiss,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.close, size: 13, color: paleSage.withValues(alpha: 0.8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
