// lib/widgets/safe_network_image.dart
//
// Drop-in replacement for Image.network and NetworkImage.
// Handles null URLs, load errors, slow networks — no broken icons ever.
// Built-in shimmer loading. Zero extra packages needed.

import 'package:flutter/material.dart';

class SafeNetworkImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;
  final BorderRadius? borderRadius;

  const SafeNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _fallback(width, height);

    Widget img = Image.network(
      url!,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : ShimmerBox(width: width ?? 80, height: height ?? 80),
      errorBuilder: (_, __, ___) => _fallback(width, height),
    );

    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }

  Widget _fallback(double? w, double? h) => fallback ??
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_outlined, color: Color(0xFF6366F1), size: 24),
      );
}

class SafeAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final String? name;
  final IconData fallbackIcon;
  final Color? backgroundColor;

  const SafeAvatar({
    super.key,
    required this.url,
    required this.radius,
    this.name,
    this.fallbackIcon = Icons.person_rounded,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0xFFEEF2FF);
    final initial = (name?.isNotEmpty == true) ? name![0].toUpperCase() : null;

    Widget child;
    if (url == null || url!.isEmpty) {
      child = initial != null
          ? Text(initial,
              style: TextStyle(
                  color: const Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.75))
          : Icon(fallbackIcon, color: const Color(0xFF6366F1), size: radius);
    } else {
      child = ClipOval(
        child: Image.network(
          url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          loadingBuilder: (_, c, p) =>
              p == null ? c : ShimmerBox(width: radius * 2, height: radius * 2),
          errorBuilder: (_, __, ___) => initial != null
              ? Text(initial,
                  style: TextStyle(
                      color: const Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.75))
              : Icon(fallbackIcon, color: const Color(0xFF6366F1), size: radius),
        ),
      );
    }

    return CircleAvatar(radius: radius, backgroundColor: bg, child: child);
  }
}

// ── Shimmer (no package needed) ───────────────────────────────────────────────
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = Tween<double>(begin: -2, end: 2)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: const [Color(0xFFEEF0F5), Color(0xFFFAFBFC), Color(0xFFEEF0F5)],
          ),
        ),
      ),
    );
  }
}

// ── DoctorCardSkeleton ────────────────────────────────────────────────────────
class DoctorCardSkeleton extends StatelessWidget {
  const DoctorCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: double.infinity, height: 100),
          const SizedBox(height: 10),
          const ShimmerBox(width: 120, height: 14),
          const SizedBox(height: 6),
          const ShimmerBox(width: 80, height: 11),
          const SizedBox(height: 8),
          Row(children: const [
            ShimmerBox(width: 50, height: 10),
            SizedBox(width: 8),
            ShimmerBox(width: 60, height: 10),
          ]),
        ],
      ),
    );
  }
}

// ── ListItemSkeleton ──────────────────────────────────────────────────────────
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const ShimmerBox(width: 48, height: 48, borderRadius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: double.infinity, height: 14),
                SizedBox(height: 6),
                ShimmerBox(width: 160, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
