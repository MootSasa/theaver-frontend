import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'unread_separator.dart' show isChatRenderBoxActivelyLaidOut;

/// Telegram-style scroll navigator for variable-height reverse/forward chat lists.
///
/// Instead of multiplying `targetIndex * estimatedHeight` from offset 0 (which
/// misses by thousands of pixels when message heights vary), this navigator uses
/// currently mounted items in the viewport as ground-truth coordinate anchors
/// via [RenderAbstractViewport.getOffsetToReveal], converging onto [targetIndex]
/// in 1–3 frames before performing a crisp final `ensureVisible` settle.
class ChatScrollNavigator {
  ChatScrollNavigator._();

  /// Scrolls [scrollController] so that the widget identified by [resolveTargetKey]
  /// (located at [targetIndex] out of [itemCount] items) is positioned at [alignment]
  /// in the viewport.
  ///
  /// Returns `true` if the target widget was mounted and aligned.
  static Future<bool> scrollToTarget({
    required ScrollController scrollController,
    required int targetIndex,
    required int itemCount,
    required GlobalKey? Function() resolveTargetKey,
    required GlobalKey? Function(int index) keyForIndex,
    required bool Function() isMounted,
    double alignment = 0.5,
    VoidCallback? onTargetMounted,
  }) async {
    if (!isMounted() || targetIndex < 0 || targetIndex >= itemCount) {
      return false;
    }

    if (!scrollController.hasClients ||
        !scrollController.position.hasContentDimensions) {
      await WidgetsBinding.instance.endOfFrame;
      if (!isMounted() ||
          !scrollController.hasClients ||
          !scrollController.position.hasContentDimensions) {
        return false;
      }
    }

    // Fast path: Target widget is already actively laid out in the viewport or cacheExtent.
    final initialCtx = resolveTargetKey()?.currentContext;
    if (initialCtx != null && initialCtx.mounted) {
      final ro = initialCtx.findRenderObject();
      final box = ro is RenderBox ? ro : null;
      final viewport =
          isChatRenderBoxActivelyLaidOut(box) ? RenderAbstractViewport.maybeOf(box!) : null;
      if (box != null && viewport != null) {
        final desiredOffset = viewport
            .getOffsetToReveal(box, alignment)
            .offset
            .clamp(
              scrollController.position.minScrollExtent,
              scrollController.position.maxScrollExtent,
            );
        final distance = ( desiredOffset - scrollController.offset ).abs();
        final viewportDim = scrollController.position.viewportDimension;

        onTargetMounted?.call();

        // If further than ~1.5 screens within cacheExtent, jump close first
        if (distance > viewportDim * 1.4) {
          final sign = desiredOffset > scrollController.offset ? -1.0 : 1.0;
          final preOffset = (desiredOffset + sign * math.min(140.0, viewportDim * 0.25))
              .clamp(
                scrollController.position.minScrollExtent,
                scrollController.position.maxScrollExtent,
              );
          scrollController.jumpTo(preOffset);
          await WidgetsBinding.instance.endOfFrame;
          if (!isMounted()) return false;
        }

        final settledCtx = resolveTargetKey()?.currentContext;
        if (settledCtx != null && settledCtx.mounted) {
          await Scrollable.ensureVisible(
            settledCtx,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: alignment,
          );
          await _verifyExactAlignment(
            scrollController: scrollController,
            resolveTargetKey: resolveTargetKey,
            alignment: alignment,
            isMounted: isMounted,
          );
          return true;
        }
      }
    }

    // Guided multi-frame anchor seek for unmounted target indices
    double runningPitch = 88.0;
    const int maxSeekFrames = 12;

    for (int frame = 0; frame < maxSeekFrames; frame++) {
      if (!isMounted() ||
          !scrollController.hasClients ||
          !scrollController.position.hasContentDimensions) {
        return false;
      }

      final targetCtx = resolveTargetKey()?.currentContext;
      if (targetCtx != null && targetCtx.mounted) {
        final targetRo = targetCtx.findRenderObject();
        if (targetRo is RenderBox && isChatRenderBoxActivelyLaidOut(targetRo)) {
          break;
        }
      }

      // Collect all currently mounted item anchors in the viewport/cacheExtent
      final mountedAnchors = <({int index, RenderBox box, double revealOffset})>[];
      RenderAbstractViewport? viewport;

      for (int i = 0; i < itemCount; i++) {
        final key = keyForIndex(i);
        final ctx = key?.currentContext;
        if (ctx == null || !ctx.mounted) continue;
        final ro = ctx.findRenderObject();
        if (ro is! RenderBox || !isChatRenderBoxActivelyLaidOut(ro)) continue;
        viewport ??= RenderAbstractViewport.maybeOf(ro);
        if (viewport == null) continue;

        final reveal = viewport.getOffsetToReveal(ro, alignment).offset;
        if (reveal.isFinite) {
          mountedAnchors.add((index: i, box: ro, revealOffset: reveal));
        }
      }

      final pos = scrollController.position;
      final minScroll = pos.minScrollExtent;
      final maxScroll = pos.maxScrollExtent;

      if (mountedAnchors.isEmpty) {
        // Fallback if no anchors are mounted yet on this frame
        final fallbackOffset =
            (targetIndex * runningPitch).clamp(minScroll, maxScroll);
        if ((scrollController.offset - fallbackOffset).abs() > 1.0) {
          scrollController.jumpTo(fallbackOffset);
        }
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }

      // Measure actual center-to-center pitch across currently mounted items
      if (mountedAnchors.length >= 2) {
        final first = mountedAnchors.first;
        final last = mountedAnchors.last;
        final indexSpan = (last.index - first.index).abs();
        final offsetSpan = (last.revealOffset - first.revealOffset).abs();
        if (indexSpan > 0 && offsetSpan > 10.0) {
          final measuredPitch = (offsetSpan / indexSpan).clamp(48.0, 280.0);
          runningPitch = (runningPitch * 0.35) + (measuredPitch * 0.65);
        }
      } else {
        final singleHeight = mountedAnchors.first.box.size.height;
        if (singleHeight > 24.0) {
          runningPitch = singleHeight.clamp(48.0, 280.0);
        }
      }

      // Find the mounted anchor closest in index to targetIndex
      var nearest = mountedAnchors.first;
      int minIndexDelta = (targetIndex - nearest.index).abs();
      for (final candidate in mountedAnchors) {
        final delta = (targetIndex - candidate.index).abs();
        if (delta < minIndexDelta) {
          minIndexDelta = delta;
          nearest = candidate;
        }
      }

      final int remainingItems = targetIndex - nearest.index;
      if (remainingItems == 0) {
        // The item at targetIndex is mounted via keyForIndex, align to it
        final clamped = nearest.revealOffset.clamp(minScroll, maxScroll);
        if ((scrollController.offset - clamped).abs() > 1.0) {
          scrollController.jumpTo(clamped);
        }
        await WidgetsBinding.instance.endOfFrame;
        break;
      }

      // Determine scroll direction per index step (+1 if higher index => higher scroll offset)
      double directionSign = 1.0;
      if (mountedAnchors.length >= 2) {
        final first = mountedAnchors.first;
        final last = mountedAnchors.last;
        if (last.index != first.index) {
          directionSign =
              (last.revealOffset >= first.revealOffset) == (last.index > first.index)
                  ? 1.0
                  : -1.0;
        }
      }

      // If only 1-2 items away, step by at least the anchor's own height + padding
      final double stepPitch = remainingItems.abs() <= 2
          ? math.max(runningPitch, nearest.box.size.height * 0.85 + 36.0)
          : runningPitch;

      final double rawTargetOffset =
          nearest.revealOffset + (remainingItems * stepPitch * directionSign);
      final double clampedOffset = rawTargetOffset.clamp(minScroll, maxScroll);

      if ((scrollController.offset - clampedOffset).abs() < 1.0 &&
          clampedOffset < maxScroll &&
          clampedOffset > minScroll) {
        // Nudge by half a screen in the required direction so SliverList mounts next items
        final nudge =
            (scrollController.offset + remainingItems.sign * directionSign * 240.0)
                .clamp(minScroll, maxScroll);
        scrollController.jumpTo(nudge);
      } else {
        scrollController.jumpTo(clampedOffset);
      }

      await WidgetsBinding.instance.endOfFrame;
    }

    if (!isMounted() || !scrollController.hasClients) return false;

    final finalCtx = resolveTargetKey()?.currentContext ??
        keyForIndex(targetIndex)?.currentContext;
    if (finalCtx == null || !finalCtx.mounted) {
      return false;
    }

    onTargetMounted?.call();

    // Teleport pre-positioning: place viewport within ~110px of exact target
    // so the final settle animation is fast and smooth (Telegram-style).
    final ro = finalCtx.findRenderObject();
    final viewport = ro != null ? RenderAbstractViewport.maybeOf(ro) : null;
    if (ro != null && viewport != null && scrollController.position.hasContentDimensions) {
      final exactOffset = viewport
          .getOffsetToReveal(ro, alignment)
          .offset
          .clamp(
            scrollController.position.minScrollExtent,
            scrollController.position.maxScrollExtent,
          );
      final diff = exactOffset - scrollController.offset;
      if (diff.abs() > 140.0) {
        final preSettleOffset = (exactOffset - diff.sign * 100.0).clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        );
        scrollController.jumpTo(preSettleOffset);
        await WidgetsBinding.instance.endOfFrame;
        if (!isMounted()) return false;
      }
    }

    final postJumpCtx = resolveTargetKey()?.currentContext ??
        keyForIndex(targetIndex)?.currentContext;
    if (postJumpCtx != null && postJumpCtx.mounted) {
      await Scrollable.ensureVisible(
        postJumpCtx,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
      await _verifyExactAlignment(
        scrollController: scrollController,
        resolveTargetKey: () =>
            resolveTargetKey() ?? keyForIndex(targetIndex),
        alignment: alignment,
        isMounted: isMounted,
      );
      return true;
    }

    return false;
  }

  /// Performs a zero-duration micro-correction after the settle animation in case
  /// surrounding slivers or images adjusted their layout extent during the scroll.
  static Future<void> _verifyExactAlignment({
    required ScrollController scrollController,
    required GlobalKey? Function() resolveTargetKey,
    required double alignment,
    required bool Function() isMounted,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!isMounted() ||
        !scrollController.hasClients ||
        !scrollController.position.hasContentDimensions) {
      return;
    }
    final ctx = resolveTargetKey()?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final ro = ctx.findRenderObject();
    final viewport = ro != null ? RenderAbstractViewport.maybeOf(ro) : null;
    if (ro == null || viewport == null) return;

    final exactOffset = viewport
        .getOffsetToReveal(ro, alignment)
        .offset
        .clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        );
    if ((exactOffset - scrollController.offset).abs() > 3.0) {
      await Scrollable.ensureVisible(
        ctx,
        duration: Duration.zero,
        alignment: alignment,
      );
    }
  }
}
