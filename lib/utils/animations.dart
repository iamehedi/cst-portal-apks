import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'a11y.dart';

/// Fade in + slide up from [offset] pixels.
List<Effect> fadeInSlide({
  Duration? delay,
  Duration? duration,
  double offset = 20,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 400.ms,
              curve: Curves.easeOut,
            ),
            MoveEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 400.ms,
              curve: Curves.easeOut,
              begin: Offset(0, offset),
              end: Offset.zero,
            ),
          ];

/// Scale from [begin] + fade in.
List<Effect> scaleIn({
  Duration? delay,
  Duration? duration,
  double begin = 0.9,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOut,
            ),
            ScaleEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOutBack,
              begin: Offset(begin, begin),
              end: const Offset(1, 1),
            ),
          ];

/// Staggered delay for list items based on [index].
Duration staggerDelay(int index, {int maxItems = 10, Duration total = const Duration(milliseconds: 600)}) {
  final clamped = index.clamp(0, maxItems);
  return Duration(milliseconds: (total.inMilliseconds * clamped / maxItems).round());
}

/// Fade in from left for list items (e.g. notifications, timeline)
List<Effect> fadeInFromLeft({
  Duration? delay,
  Duration? duration,
  double offset = 16,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOut,
            ),
            MoveEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOut,
              begin: Offset(-offset, 0),
              end: Offset.zero,
            ),
          ];

/// Fade in from right (e.g. action buttons appearing)
List<Effect> fadeInFromRight({
  Duration? delay,
  Duration? duration,
  double offset = 16,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOut,
            ),
            MoveEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 350.ms,
              curve: Curves.easeOut,
              begin: Offset(offset, 0),
              end: Offset.zero,
            ),
          ];

/// Blur in effect for premium feel
List<Effect> blurIn({
  Duration? delay,
  Duration? duration,
  double begin = 8,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            BlurEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 500.ms,
              curve: Curves.easeOut,
              begin: Offset(begin, begin),
              end: Offset.zero,
            ),
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 500.ms,
              curve: Curves.easeOut,
            ),
          ];

/// Shimmer + fade for loading states
List<Effect> shimmerAppear({
  Duration? delay,
  Duration? duration,
  bool skip = false,
}) =>
    skip
        ? []
        : [
            ShimmerEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 800.ms,
              color: const Color(0x15FFFFFF),
            ),
            FadeEffect(
              delay: delay ?? Duration.zero,
              duration: duration ?? 500.ms,
              curve: Curves.easeOut,
            ),
          ];

/// Staggered container that applies a slide-up + fade animation to its children
class StaggeredColumn extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final Duration totalDuration;
  final double slideOffset;

  const StaggeredColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.totalDuration = const Duration(milliseconds: 600),
    this.slideOffset = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) {
      return Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisAlignment: mainAxisAlignment,
        mainAxisSize: mainAxisSize,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: children.asMap().entries.map((entry) {
        final i = entry.key;
        final child = entry.value;
        final delayMs = (totalDuration.inMilliseconds * i / children.length).round();
        final delay = Duration(milliseconds: delayMs);
        return child
            .animate()
            .fadeIn(
              duration: 350.ms,
              delay: delay,
              curve: Curves.easeOut,
            )
            .slideY(
              begin: slideOffset,
              end: 0,
              duration: 350.ms,
              delay: delay,
              curve: Curves.easeOut,
            );
      }).toList(),
    );
  }
}

/// Page route with slide-up + fade transition.
/// Falls back to a plain fade when the user has enabled reduced motion.
class SlideUpPageRoute<T> extends PageRouteBuilder<T> {
  SlideUpPageRoute({required Widget page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (ctx, animation, __, child) {
            if (reducedMotion(ctx)) {
              return FadeTransition(opacity: animation, child: child);
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 200),
        );
}
