import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/tiling_layout_controller.dart';
import 'trackpad_swipe_back_indicator.dart';

class _TileViewportInherited extends InheritedWidget {
  final String tileId;
  final bool isChatTile;
  final Size tileSize;
  final EdgeInsets tileViewInsets;
  final bool hasTopNeighbor;
  final bool hasBottomNeighbor;

  const _TileViewportInherited({
    required this.tileId,
    required this.isChatTile,
    required this.tileSize,
    required this.tileViewInsets,
    required this.hasTopNeighbor,
    required this.hasBottomNeighbor,
    required super.child,
  });

  @override
  bool updateShouldNotify(_TileViewportInherited oldWidget) {
    return oldWidget.tileId != tileId ||
        oldWidget.isChatTile != isChatTile ||
        oldWidget.tileSize != tileSize ||
        oldWidget.tileViewInsets != tileViewInsets ||
        oldWidget.hasTopNeighbor != hasTopNeighbor ||
        oldWidget.hasBottomNeighbor != hasBottomNeighbor;
  }
}

/// Обёртка для каждого тайла в многооконном режиме.
///
/// Обеспечивает:
/// 1. Локальные габариты тайла через [TileViewportScope.sizeOf], [widthOf], [heightOf]
///    (при этом глобальный [MediaQuery.sizeOf] остаётся равным размеру корневого окна FlutterView,
///    чтобы шейдеры `liquid_glass_easy` корректно вычисляли экранные координаты без сдвига и обрезки).
/// 2. Отслеживание активного тайла по клику/тапу (`Listener.onPointerDown`).
/// 3. Обработку свайпа двумя пальцами по тачпаду слева направо с выезжающей стрелкой возврата.
/// 4. Строгую обрезку (`ClipRect`) и изоляцию слоя перерисовки (`RepaintBoundary`) внутри тайла.
class TileViewportScope extends StatelessWidget {
  final String tileId;
  final bool isChatTile;
  final bool hasTopNeighbor;
  final bool hasBottomNeighbor;
  final double? bottomDistanceFromWindow;
  final Widget child;

  const TileViewportScope({
    super.key,
    required this.tileId,
    required this.isChatTile,
    this.hasTopNeighbor = false,
    this.hasBottomNeighbor = false,
    this.bottomDistanceFromWindow,
    required this.child,
  });

  static String? maybeTileIdOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TileViewportInherited>()
        ?.tileId;
  }

  static bool isInsideChatTile(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_TileViewportInherited>()
            ?.isChatTile ??
        false;
  }

  static bool hasTopNeighborOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_TileViewportInherited>()
            ?.hasTopNeighbor ??
        false;
  }

  static bool hasBottomNeighborOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_TileViewportInherited>()
            ?.hasBottomNeighbor ??
        false;
  }

  static Size? maybeTileSizeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_TileViewportInherited>()
        ?.tileSize;
  }

  /// Возвращает размер текущего мини-окна (тайла), либо размер окна приложения,
  /// если виджет находится вне тайла (например, в полноэкранном диалоге).
  static Size sizeOf(BuildContext context) {
    return maybeTileSizeOf(context) ?? MediaQuery.sizeOf(context);
  }

  static double widthOf(BuildContext context) => sizeOf(context).width;

  static double heightOf(BuildContext context) => sizeOf(context).height;

  static EdgeInsets viewInsetsOf(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_TileViewportInherited>();
    if (inherited != null) {
      return inherited.tileViewInsets;
    }
    return MediaQuery.viewInsetsOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final parentMediaQuery = MediaQuery.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : parentMediaQuery.size.width;
        final effectiveHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : parentMediaQuery.size.height;
        final tileSize = Size(effectiveWidth, effectiveHeight);

        final double distanceFromBottomOfWindow = bottomDistanceFromWindow ??
            (hasBottomNeighbor
                ? math.max(0.0, parentMediaQuery.size.height - effectiveHeight)
                : 0.0);
        final globalViewInsets = parentMediaQuery.viewInsets;
        final effectiveBottomViewInset = math.max(
          0.0,
          globalViewInsets.bottom - distanceFromBottomOfWindow,
        );
        final effectiveViewInsets = globalViewInsets.copyWith(
          bottom: effectiveBottomViewInset,
        );

        Widget scopedChild = child;
        if (hasTopNeighbor || hasBottomNeighbor || distanceFromBottomOfWindow > 0) {
          final strippedMediaQuery = parentMediaQuery
              .removePadding(
                removeTop: hasTopNeighbor,
                removeBottom: hasBottomNeighbor,
              )
              .copyWith(
                viewPadding: parentMediaQuery.viewPadding.copyWith(
                  top: hasTopNeighbor ? 0.0 : null,
                  bottom: hasBottomNeighbor ? 0.0 : null,
                ),
                viewInsets: effectiveViewInsets,
              );
          scopedChild = MediaQuery(
            data: strippedMediaQuery,
            child: scopedChild,
          );
        }

        return _TileViewportInherited(
          tileId: tileId,
          isChatTile: isChatTile,
          tileSize: tileSize,
          tileViewInsets: effectiveViewInsets,
          hasTopNeighbor: hasTopNeighbor,
          hasBottomNeighbor: hasBottomNeighbor,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              TilingLayoutController.instance.setFocusedTile(tileId);
              if ((event.buttons & kBackMouseButton) != 0) {
                final rootNav = Navigator.maybeOf(context, rootNavigator: true);
                TilingLayoutController.instance.handleBackAction(
                  forTileId: tileId,
                  rootNavigator: rootNav,
                );
              }
            },
            child: ClipRect(
              child: RepaintBoundary(
                child: TrackpadBackGestureWrapper(
                  onTriggerBack: () {
                    final rootNav = Navigator.maybeOf(context, rootNavigator: true);
                    TilingLayoutController.instance.handleBackAction(
                      forTileId: tileId,
                      rootNavigator: rootNav,
                    );
                  },
                  child: scopedChild,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
