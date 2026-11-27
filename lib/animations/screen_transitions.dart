import 'package:flutter/material.dart';
import '../utils/swipe_back_route.dart';

export '../utils/swipe_back_route.dart'
    show TelegramSwipeBackPageTransitionsBuilder;

/// Custom fade transition builder for page transitions.
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwipeBackPageRoute.delegatedTransitionBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.popGestureInProgress) {
      return SwipeBackPageRoute.buildSharedTransitions<T>(
        route: route,
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }

    final wrappedChild = SwipeBackPageRoute.wrapWithSwipeBackDetector<T>(
      route: route,
      animation: animation,
      child: SwipeBackPageRoute.buildSecondaryParallax(
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        if (animation.value >= 0.999) {
          return inner!;
        }
        return FadeTransition(
          opacity: animation,
          child: inner,
        );
      },
      child: wrappedChild,
    );
  }
}

/// Custom slide transition builder (right to left) for page transitions.
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwipeBackPageRoute.delegatedTransitionBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SwipeBackPageRoute.buildSharedTransitions<T>(
      route: route,
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Custom scale transition builder with fade for desktop page transitions,
/// enhanced with Telegram secondary parallax, scrim dimming, and interactive
/// swipe-back support.
class ScalePageTransitionsBuilder extends PageTransitionsBuilder {
  const ScalePageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwipeBackPageRoute.delegatedTransitionBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final userGesture =
        Navigator.maybeOf(context)?.userGestureInProgress ?? false;
    if (route.popGestureInProgress || userGesture) {
      return SwipeBackPageRoute.buildSharedTransitions<T>(
        route: route,
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }

    final wrappedChild = SwipeBackPageRoute.wrapWithSwipeBackDetector<T>(
      route: route,
      animation: animation,
      child: SwipeBackPageRoute.buildSecondaryParallax(
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        if (animation.value >= 0.999) {
          return inner!;
        }
        final double curved = Curves.easeOutCubic.transform(
          animation.value.clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: curved.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.8 + 0.2 * curved,
            child: inner,
          ),
        );
      },
      child: wrappedChild,
    );
  }
}

/// Custom rotation transition builder for special effects.
class RotationPageTransitionsBuilder extends PageTransitionsBuilder {
  const RotationPageTransitionsBuilder();

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwipeBackPageRoute.delegatedTransitionBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> rotation = Tween<double>(
      begin: -0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.elasticOut));

    return RotationTransition(
      turns: rotation,
      child: SwipeBackPageRoute.buildSecondaryParallax(
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    );
  }
}

/// Custom screen transition animations for Theaver.
class ScreenTransitionAnimations {
  /// Telegram-grade interactive full-screen swipe-back + parallax transition.
  static PageTransitionsBuilder get telegramSwipeBack =>
      const TelegramSwipeBackPageTransitionsBuilder();

  /// Fade transition builder.
  static PageTransitionsBuilder get fadeTransition =>
      const FadePageTransitionsBuilder();

  /// Slide transition from right to left.
  static PageTransitionsBuilder get slideTransition =>
      const SlidePageTransitionsBuilder();

  /// Scale transition with fade.
  static PageTransitionsBuilder get scaleTransition =>
      const ScalePageTransitionsBuilder();

  /// Rotation transition (for special effects).
  static PageTransitionsBuilder get rotationTransition =>
      const RotationPageTransitionsBuilder();
}

/// Custom page transitions theme for easy application.
class CustomPageTransitionsTheme {
  static PageTransitionsTheme get customTheme => PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ScreenTransitionAnimations.telegramSwipeBack,
          TargetPlatform.iOS: ScreenTransitionAnimations.telegramSwipeBack,
          TargetPlatform.fuchsia: ScreenTransitionAnimations.telegramSwipeBack,
          TargetPlatform.linux: ScreenTransitionAnimations.scaleTransition,
          TargetPlatform.macOS: ScreenTransitionAnimations.scaleTransition,
          TargetPlatform.windows: ScreenTransitionAnimations.scaleTransition,
        },
      );
}
