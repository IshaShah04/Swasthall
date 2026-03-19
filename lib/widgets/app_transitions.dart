// lib/widgets/app_transitions.dart
//
// Smooth page transitions and haptic feedback used app-wide.
// Import this once and use instead of MaterialPageRoute.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Navigation helpers ────────────────────────────────────────────────────────

/// Slide-up transition (modal-style). Use for booking, payment, detail screens.
Route<T> slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

/// Fade+scale transition. Use for overlays, success screens.
Route<T> fadeScaleRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
              child: child),
        );
      },
    );

/// Slide-right transition (standard push). Use for normal navigation.
Route<T> slideRightRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

// ── Haptic feedback shortcuts ─────────────────────────────────────────────────

/// Light tap — use on every button, chip, card tap
void hapticLight() => HapticFeedback.lightImpact();

/// Medium tap — use on primary action buttons (Book, Pay, Confirm)
void hapticMedium() => HapticFeedback.mediumImpact();

/// Success — use on booking confirmed, payment success
void hapticSuccess() => HapticFeedback.heavyImpact();

/// Error — use on form validation errors, failed actions
void hapticError() => HapticFeedback.vibrate();

// ── HapticButton — wrapper that adds haptic to any tap ────────────────────────
class HapticButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final HapticType haptic;
  final BorderRadius? borderRadius;

  const HapticButton({
    super.key,
    required this.child,
    required this.onTap,
    this.haptic = HapticType.light,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              switch (haptic) {
                case HapticType.light:
                  hapticLight();
                case HapticType.medium:
                  hapticMedium();
                case HapticType.success:
                  hapticSuccess();
                case HapticType.error:
                  hapticError();
              }
              onTap!();
            },
      child: child,
    );
  }
}

enum HapticType { light, medium, success, error }

// ── StaggeredList — entrance animation for lists ─────────────────────────────
class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDelay;

  const StaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 60),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.asMap().entries.map((entry) {
        return _StaggeredItem(
          delay: Duration(milliseconds: entry.key * itemDelay.inMilliseconds),
          child: entry.value,
        );
      }).toList(),
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _StaggeredItem({required this.child, required this.delay});

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _opacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ── AnimatedCheckmark — for success screens ───────────────────────────────────
class AnimatedCheckmark extends StatefulWidget {
  final double size;
  final Color color;

  const AnimatedCheckmark({
    super.key,
    this.size = 80,
    this.color = const Color(0xFF10B981),
  });

  @override
  State<AnimatedCheckmark> createState() => _AnimatedCheckmarkState();
}

class _AnimatedCheckmarkState extends State<AnimatedCheckmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _check;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scale = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5, curve: Curves.elasticOut)));
    _check = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ctrl.forward();
        hapticSuccess();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.12),
            border: Border.all(color: widget.color, width: 2.5),
          ),
          child: CustomPaint(
            painter: _CheckPainter(progress: _check.value, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.70)
      ..lineTo(size.width * 0.75, size.height * 0.33);

    final metrics = path.computeMetrics().first;
    final drawn = metrics.extractPath(0, metrics.length * progress);
    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// ── ConnectivityBanner — shows "No internet" strip automatically ──────────────
class ConnectivityBanner extends StatelessWidget {
  final bool isOnline;
  final Widget child;

  const ConnectivityBanner({
    super.key,
    required this.isOnline,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: isOnline ? 0 : 30,
          color: const Color(0xFFEF4444),
          child: isOnline
              ? const SizedBox.shrink()
              : const Center(
                  child: Text(
                    '⚠  No internet connection',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
