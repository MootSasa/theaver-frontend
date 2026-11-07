import 'package:flutter/material.dart';

/// Custom fade transition builder for page transitions.
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
}

/// Custom slide transition builder (right to left) for page transitions.
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const Offset begin = Offset(1.0, 0.0);
    const Offset end = Offset.zero;
    const Curve curve = Curves.easeOutCubic;
    final Animation<Offset> position = Tween<Offset>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: animation, curve: curve));

    return SlideTransition(
      position: position,
      child: child,
    );
  }
}

/// Custom scale transition builder with fade for page transitions.
class ScalePageTransitionsBuilder extends PageTransitionsBuilder {
  const ScalePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> scale = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    final Animation<double> fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: scale,
        child: child,
      ),
    );
  }
}

/// Custom rotation transition builder for special effects.
class RotationPageTransitionsBuilder extends PageTransitionsBuilder {
  const RotationPageTransitionsBuilder();

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
      child: child,
    );
  }
}

/// Custom screen transition animations for Theaver.
class ScreenTransitionAnimations {
  /// Fade transition builder.
  static PageTransitionsBuilder get fadeTransition => const FadePageTransitionsBuilder();

  /// Slide transition from right to left.
  static PageTransitionsBuilder get slideTransition => const SlidePageTransitionsBuilder();

  /// Scale transition with fade.
  static PageTransitionsBuilder get scaleTransition => const ScalePageTransitionsBuilder();

  /// Rotation transition (for special effects).
  static PageTransitionsBuilder get rotationTransition => const RotationPageTransitionsBuilder();
}

/// Custom page transitions theme for easy application.
class CustomPageTransitionsTheme {
  static PageTransitionsTheme get customTheme => PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ScreenTransitionAnimations.slideTransition,
      TargetPlatform.iOS: ScreenTransitionAnimations.fadeTransition,
      TargetPlatform.linux: ScreenTransitionAnimations.scaleTransition,
      TargetPlatform.macOS: ScreenTransitionAnimations.scaleTransition,
      TargetPlatform.windows: ScreenTransitionAnimations.scaleTransition,
    },
  );
}
