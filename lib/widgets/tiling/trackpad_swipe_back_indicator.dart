import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/haptic_utils.dart';
import 'tile_viewport_scope.dart';

/// Обёртка для обработки свайпа двумя пальцами по тачпаду слева направо на ПК:
/// - Нативные жесты тачпада (`PointerPanZoomStartEvent` / `PointerPanZoomUpdateEvent` / `PointerPanZoomEndEvent`)
/// - В среде WSLg (где RDP-клиент транслирует тачпад в обычные колёсные события без фазы отпускания пальцев) —
///   прямой мост к Windows Precision Touchpad (`_WslTouchpadBridge`), который отслеживает физическое касание
///   двух пальцев (`TipSwitch`) и вызывает возврат строго в момент отрыва пальцев от тачпада (`END`).
class TrackpadBackGestureWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTriggerBack;
  final bool Function()? canTriggerBack;

  const TrackpadBackGestureWrapper({
    super.key,
    required this.child,
    required this.onTriggerBack,
    this.canTriggerBack,
  });

  @override
  State<TrackpadBackGestureWrapper> createState() =>
      _TrackpadBackGestureWrapperState();
}

class _TrackpadBackGestureWrapperState extends State<TrackpadBackGestureWrapper>
    with SingleTickerProviderStateMixin {
  static const double _kTriggerThreshold = 76.0;
  static const double _kMaxPullDistance = 128.0;

  late final AnimationController _reboundController;
  Animation<double>? _reboundAnimation;

  double _panDx = 0.0;
  double _panDy = 0.0;
  bool _isTrackingHorizontalBack = false;
  bool _isRejected = false;
  bool _thresholdReached = false;
  String? _tileId;

  @override
  void initState() {
    super.initState();
    _reboundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (mounted && _reboundAnimation != null) {
          setState(() {
            _panDx = _reboundAnimation!.value;
          });
        }
      });
    _WslTouchpadBridge.instance.registerWrapper(this);
  }

  @override
  void reassemble() {
    super.reassemble();
    _WslTouchpadBridge.instance.registerWrapper(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tileId = TileViewportScope.maybeTileIdOf(context);
    _WslTouchpadBridge.instance.registerWrapper(this);
  }

  @override
  void dispose() {
    _WslTouchpadBridge.instance.unregisterWrapper(this);
    _reboundController.dispose();
    super.dispose();
  }

  void _startGesture() {
    if (widget.canTriggerBack != null && !widget.canTriggerBack!()) {
      _isRejected = true;
      return;
    }
    _reboundController.stop();
    _panDx = 0.0;
    _panDy = 0.0;
    _isTrackingHorizontalBack = false;
    _isRejected = false;
    _thresholdReached = false;
  }

  void _applyHorizontalDelta(double dx, double dy) {
    if (_isRejected) return;

    if (!_isTrackingHorizontalBack) {
      _panDx += dx;
      _panDy += dy;

      // Если жест начался вертикально или влево — отклоняем его, чтобы не мешать обычному скроллу
      if (_panDy.abs() > 10.0 && _panDy.abs() > _panDx.abs()) {
        _isRejected = true;
        _panDx = 0.0;
        return;
      }
      if (_panDx < -8.0) {
        _isRejected = true;
        _panDx = 0.0;
        return;
      }
      if (_panDx > 10.0 && _panDx > _panDy.abs() * 1.25) {
        _isTrackingHorizontalBack = true;
      } else {
        return;
      }
    } else {
      // Накапливаем смещение с мягким резиновым сопротивлением после порога.
      // При движении обратно влево (dx < 0) уменьшаем _panDx 1:1, позволяя отменить взведение.
      final effectiveDx =
          (_panDx >= _kTriggerThreshold && dx > 0) ? dx * 0.38 : dx;
      _panDx = (_panDx + effectiveDx).clamp(0.0, _kMaxPullDistance);
    }

    final reachedNow = _panDx >= _kTriggerThreshold;
    if (reachedNow && !_thresholdReached) {
      _thresholdReached = true;
      HapticUtils.selection();
    } else if (!reachedNow && _thresholdReached) {
      _thresholdReached = false;
      HapticUtils.selection();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _finishGesture() {
    if (!_isTrackingHorizontalBack || _isRejected) {
      _panDx = 0.0;
      _panDy = 0.0;
      _isTrackingHorizontalBack = false;
      _isRejected = false;
      return;
    }

    final shouldPop = _panDx >= _kTriggerThreshold;
    final startVal = _panDx;
    _isTrackingHorizontalBack = false;
    _thresholdReached = false;

    _reboundAnimation = Tween<double>(begin: startVal, end: 0.0).animate(
      CurvedAnimation(parent: _reboundController, curve: Curves.easeOutCubic),
    );
    _reboundController.forward(from: 0.0);

    // Действие «Назад» выполняется строго после отпускания пальцев от тачпада
    if (shouldPop) {
      HapticUtils.impact();
      widget.onTriggerBack();
    }
  }

  void _cancelGesture() {
    final startVal = _panDx;
    _isTrackingHorizontalBack = false;
    _isRejected = false;
    _thresholdReached = false;
    if (startVal > 0.0) {
      _reboundAnimation = Tween<double>(begin: startVal, end: 0.0).animate(
        CurvedAnimation(parent: _reboundController, curve: Curves.easeOutCubic),
      );
      _reboundController.forward(from: 0.0);
    } else {
      _panDx = 0.0;
      _panDy = 0.0;
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _WslTouchpadBridge.instance.markHovered(this);
    _startGesture();
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _applyHorizontalDelta(event.panDelta.dx, event.panDelta.dy);
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _finishGesture();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _WslTouchpadBridge.instance.onPointerScrollInWrapper(this, event);
    }
  }

  @override
  Widget build(BuildContext context) {
    _WslTouchpadBridge.instance.registerWrapper(this);
    final progress = (_panDx / _kTriggerThreshold).clamp(0.0, 1.0);
    final showIndicator = _panDx > 2.0;

    return MouseRegion(
      opaque: false,
      onEnter: (_) => _WslTouchpadBridge.instance.markHovered(this),
      onHover: (_) => _WslTouchpadBridge.instance.markHovered(this),
      onExit: (_) => _WslTouchpadBridge.instance.unmarkHovered(this),
      child: Listener(
        onPointerHover: (_) => _WslTouchpadBridge.instance.markHovered(this),
        onPointerMove: (_) => _WslTouchpadBridge.instance.markHovered(this),
        onPointerDown: (_) => _WslTouchpadBridge.instance.markHovered(this),
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        onPointerPanZoomEnd: _onPanZoomEnd,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (showIndicator)
              Positioned(
                left: (-44.0 + _panDx * 0.72).clamp(-44.0, 22.0),
                top: 0,
                bottom: 0,
                child: Center(
                  child: IgnorePointer(
                    child: TrackpadSwipeBackIndicator(
                      progress: progress,
                      isArmed: _panDx >= _kTriggerThreshold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Мост к Windows Precision Touchpad (HID UsagePage=0x0D, Usage=0x05) для WSLg.
///
/// В WSLg RDP-клиент (`msrdc.exe`) переводит свайпы двумя пальцами по тачпаду в дискретные
/// события `WM_MOUSEHWHEEL` (`PointerScrollEvent`) и не передаёт событие отрыва пальцев от тачпада.
/// Этот мост запускает легковесный Win32 RawInput-слушатель, который передаёт `START` (касание двумя пальцами),
/// `UPDATE dx dy` (точное смещение пальцев 125 Гц) и `END` (момент физического отпускания тачпада).
class _WslTouchpadBridge {
  static final _WslTouchpadBridge instance = _WslTouchpadBridge._();
  _WslTouchpadBridge._();

  final List<_TrackpadBackGestureWrapperState> _wrappers = [];
  _TrackpadBackGestureWrapperState? _hoveredWrapper;
  _TrackpadBackGestureWrapperState? _activeGestureWrapper;

  Process? _helperProcess;
  StreamSubscription<String>? _stdoutSub;
  bool _isStarting = false;
  bool _isReady = false;
  bool _isTwoFingersDown = false;

  bool get _isWslEnvironment {
    if (kIsWeb || !Platform.isLinux) return false;
    final env = Platform.environment;
    if (env.containsKey('FLUTTER_TEST')) return false;
    return env.containsKey('WSL_DISTRO_NAME') || env.containsKey('WSL_INTEROP');
  }

  void registerWrapper(_TrackpadBackGestureWrapperState wrapper) {
    if (!_wrappers.contains(wrapper)) {
      _wrappers.add(wrapper);
    }
    if (_isWslEnvironment) {
      _ensureHelperStarted();
    }
  }

  void unregisterWrapper(_TrackpadBackGestureWrapperState wrapper) {
    _wrappers.remove(wrapper);
    if (_hoveredWrapper == wrapper) {
      _hoveredWrapper = null;
    }
    if (_activeGestureWrapper == wrapper) {
      _activeGestureWrapper = null;
    }
  }

  void markHovered(_TrackpadBackGestureWrapperState wrapper) {
    _hoveredWrapper = wrapper;
  }

  void unmarkHovered(_TrackpadBackGestureWrapperState wrapper) {
    if (_hoveredWrapper == wrapper) {
      _hoveredWrapper = null;
    }
  }

  void onPointerScrollInWrapper(
    _TrackpadBackGestureWrapperState wrapper,
    PointerScrollEvent event,
  ) {
    _hoveredWrapper = wrapper;
    // Если жест уже начался в WSL, но до первого скролла курсор не двигался (например, сразу после hot-reload),
    // привязываем активный жест к тайлу, получившему PointerScrollEvent.
    if (_isReady && _isTwoFingersDown && _activeGestureWrapper == null) {
      _activeGestureWrapper = wrapper;
      wrapper._startGesture();
    }
  }

  _TrackpadBackGestureWrapperState? _resolveTargetWrapper() {
    if (_hoveredWrapper != null && _hoveredWrapper!.mounted) {
      return _hoveredWrapper;
    }
    if (_wrappers.isEmpty) return null;

    final controller = TilingLayoutController.instance;
    // В однооконном режиме при открытом чате приоритет у тайла активного чата
    if (controller.windowSize.width <
            TilingLayoutController.kTwoColumnBreakpoint &&
        controller.chatTiles.isNotEmpty) {
      final activeChatTileId = controller.chatTiles.first.tileId;
      for (final w in _wrappers.reversed) {
        if (w.mounted && w._tileId == activeChatTileId) {
          return w;
        }
      }
    }

    final focusedId = controller.activeTileId;
    for (final w in _wrappers.reversed) {
      if (w.mounted && w._tileId == focusedId) {
        return w;
      }
    }

    for (final w in _wrappers.reversed) {
      if (w.mounted) return w;
    }
    return null;
  }

  Future<void> _ensureHelperStarted() async {
    if (_isStarting || _helperProcess != null) return;
    _isStarting = true;

    try {
      const cscPath =
          '/mnt/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe';
      if (!File(cscPath).existsSync()) {
        _isStarting = false;
        return;
      }

      final tempDir = _findWindowsTempDir();
      if (tempDir == null) {
        _isStarting = false;
        return;
      }

      const baseName = 'theaver_wsl_tp_v3';
      final csFile = File('${tempDir.path}/$baseName.cs');
      final exeFile = File('${tempDir.path}/$baseName.exe');

      if (!exeFile.existsSync()) {
        await csFile.writeAsString(_kWslTouchpadHelperCSharpSource, flush: true);
        final compileResult = await Process.run(
          cscPath,
          ['-nologo', '-optimize+', '-out:$baseName.exe', '$baseName.cs'],
          workingDirectory: tempDir.path,
        );
        if (compileResult.exitCode != 0 || !exeFile.existsSync()) {
          _isStarting = false;
          return;
        }
      }

      final proc = await Process.start(
        exeFile.path,
        const [],
        workingDirectory: tempDir.path,
      );
      _helperProcess = proc;

      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onHelperLine, onDone: _onHelperExit, onError: (_) => _onHelperExit());
    } catch (_) {
      _onHelperExit();
    } finally {
      _isStarting = false;
    }
  }

  void _onHelperLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    if (trimmed == 'READY') {
      _isReady = true;
      return;
    }

    if (trimmed == 'START') {
      _isTwoFingersDown = true;
      final target = _resolveTargetWrapper();
      _activeGestureWrapper = target;
      target?._startGesture();
      return;
    }

    if (trimmed.startsWith('UPDATE ')) {
      if (!_isTwoFingersDown) return;
      final parts = trimmed.split(' ');
      if (parts.length >= 3) {
        final dx = double.tryParse(parts[1]) ?? 0.0;
        final dy = double.tryParse(parts[2]) ?? 0.0;
        _activeGestureWrapper ??= _resolveTargetWrapper();
        _activeGestureWrapper?._applyHorizontalDelta(dx, dy);
      }
      return;
    }

    if (trimmed == 'END') {
      _isTwoFingersDown = false;
      final target = _activeGestureWrapper;
      _activeGestureWrapper = null;
      target?._finishGesture();
      return;
    }

    if (trimmed == 'CANCEL') {
      _isTwoFingersDown = false;
      final target = _activeGestureWrapper;
      _activeGestureWrapper = null;
      target?._cancelGesture();
      return;
    }
  }

  void _onHelperExit() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _helperProcess = null;
    _isReady = false;
    _isTwoFingersDown = false;
    _activeGestureWrapper = null;
  }

  Directory? _findWindowsTempDir() {
    try {
      final usersDir = Directory('/mnt/c/Users');
      if (usersDir.existsSync()) {
        for (final entry in usersDir.listSync()) {
          if (entry is Directory) {
            final name = entry.path.split('/').last;
            if (name == 'Public' ||
                name == 'Default' ||
                name == 'Default User' ||
                name == 'All Users') {
              continue;
            }
            final temp = Directory('${entry.path}/AppData/Local/Temp');
            if (temp.existsSync()) {
              return temp;
            }
          }
        }
      }
      final winTemp = Directory('/mnt/c/Windows/Temp');
      if (winTemp.existsSync()) return winTemp;
    } catch (_) {}
    return null;
  }

  static const String _kWslTouchpadHelperCSharpSource = r'''
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;

public class TheaverWslTouchpadHelper {
  public delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct WNDCLASSEX {
    public uint cbSize;
    public uint style;
    public WndProcDelegate lpfnWndProc;
    public int cbClsExtra;
    public int cbWndExtra;
    public IntPtr hInstance;
    public IntPtr hIcon;
    public IntPtr hCursor;
    public IntPtr hbrBackground;
    public string lpszMenuName;
    public string lpszClassName;
    public IntPtr hIconSm;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RAWINPUTDEVICE {
    public ushort usUsagePage;
    public ushort usUsage;
    public uint dwFlags;
    public IntPtr hwndTarget;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RAWINPUTHEADER {
    public uint dwType;
    public uint dwSize;
    public IntPtr hDevice;
    public IntPtr wParam;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
    public POINT(int x, int y) { X = x; Y = y; }
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct MSG {
    public IntPtr hwnd;
    public uint message;
    public IntPtr wParam;
    public IntPtr lParam;
    public uint time;
    public POINT pt;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct HIDP_CAPS {
    public ushort Usage;
    public ushort UsagePage;
    public ushort InputReportByteLength;
    public ushort OutputReportByteLength;
    public ushort FeatureReportByteLength;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
    public ushort[] Reserved;
    public ushort NumberLinkCollectionNodes;
    public ushort NumberInputButtonCaps;
    public ushort NumberInputValueCaps;
    public ushort NumberInputDataIndices;
    public ushort NumberOutputButtonCaps;
    public ushort NumberOutputValueCaps;
    public ushort NumberOutputDataIndices;
    public ushort NumberFeatureButtonCaps;
    public ushort NumberFeatureValueCaps;
    public ushort NumberFeatureDataIndices;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct HIDP_VALUE_CAPS {
    public ushort UsagePage;
    public byte ReportID;
    public byte IsAlias;
    public ushort BitField;
    public ushort LinkCollection;
    public ushort LinkUsage;
    public ushort LinkUsagePage;
    public byte IsRange;
    public byte IsStringRange;
    public byte IsDesignatorRange;
    public byte IsAbsolute;
    public byte HasNull;
    public byte Reserved;
    public ushort BitSize;
    public ushort ReportCount;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 5)]
    public ushort[] Reserved2;
    public uint UnitsExp;
    public uint Units;
    public int LogicalMin;
    public int LogicalMax;
    public int PhysicalMin;
    public int PhysicalMax;
    public ushort UsageMin;
    public ushort UsageMax;
    public ushort StringMin;
    public ushort StringMax;
    public ushort DesignatorMin;
    public ushort DesignatorMax;
    public ushort DataIndexMin;
    public ushort DataIndexMax;
  }

  [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
  public static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

  [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
  public static extern IntPtr CreateWindowEx(
      int exStyle, string className, string windowName, int style,
      int x, int y, int width, int height,
      IntPtr hwndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

  [DllImport("user32.dll")]
  public static extern IntPtr DefWindowProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool RegisterRawInputDevices(
      [In] RAWINPUTDEVICE[] pRawInputDevices, uint uiNumDevices, uint cbSize);

  [DllImport("user32.dll")]
  public static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

  [DllImport("user32.dll")]
  public static extern bool TranslateMessage(ref MSG lpMsg);

  [DllImport("user32.dll")]
  public static extern IntPtr DispatchMessage(ref MSG lpMsg);

  [DllImport("user32.dll")]
  public static extern uint GetRawInputData(
      IntPtr hRawInput, uint uiCommand, IntPtr pData, ref uint pcbSize, uint cbSizeHeader);

  [DllImport("user32.dll")]
  public static extern uint GetRawInputDeviceInfo(
      IntPtr hDevice, uint uiCommand, IntPtr pData, ref uint pcbSize);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool GetCursorPos(out POINT lpPoint);

  [DllImport("user32.dll")]
  public static extern IntPtr WindowFromPoint(POINT Point);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("hid.dll")]
  public static extern int HidP_GetCaps(IntPtr preparsedData, out HIDP_CAPS caps);

  [DllImport("hid.dll")]
  public static extern int HidP_GetValueCaps(
      int reportType, [Out] HIDP_VALUE_CAPS[] valueCaps, ref ushort valueCapsLength, IntPtr preparsedData);

  [DllImport("hid.dll")]
  public static extern int HidP_GetUsageValue(
      int reportType, ushort usagePage, ushort linkCollection, ushort usage,
      out uint usageValue, IntPtr preparsedData, IntPtr report, uint reportLength);

  [DllImport("hid.dll")]
  public static extern int HidP_GetUsages(
      int reportType, ushort usagePage, ushort linkCollection,
      [Out] ushort[] usageList, ref uint usageLength,
      IntPtr preparsedData, IntPtr report, uint reportLength);

  class DeviceInfo {
    public bool IsTouchpad;
    public IntPtr Preparsed;
    public int MaxSlots;
    public double ScaleX;
    public double ScaleY;
  }

  static Dictionary<IntPtr, DeviceInfo> _devices = new Dictionary<IntPtr, DeviceInfo>();
  static double _prevAvgX = 0;
  static double _prevAvgY = 0;
  static bool _inTwoFingerGesture = false;
  static bool _gestureAllowedForWindow = false;
  static IntPtr _rawBuf = IntPtr.Zero;
  static uint _rawBufCapacity = 0;
  static ushort[] _usageList = new ushort[16];
  static WndProcDelegate _wndProc = WndProc;

  static bool IsWslgWindowActiveOrHovered() {
    try {
      POINT pt;
      if (GetCursorPos(out pt)) {
        IntPtr winAtCursor = WindowFromPoint(pt);
        if (winAtCursor != IntPtr.Zero) {
          uint pid = 0;
          GetWindowThreadProcessId(winAtCursor, out pid);
          if (pid != 0) {
            string name = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();
            if (name.Contains("msrdc") || name.Contains("wslg")) return true;
            return false;
          }
        }
      }
      IntPtr fg = GetForegroundWindow();
      if (fg != IntPtr.Zero) {
        uint fgPid = 0;
        GetWindowThreadProcessId(fg, out fgPid);
        if (fgPid != 0) {
          string name = Process.GetProcessById((int)fgPid).ProcessName.ToLowerInvariant();
          if (name.Contains("msrdc") || name.Contains("wslg")) return true;
          return false;
        }
      }
    } catch {}
    return true;
  }

  static DeviceInfo GetDevice(IntPtr hDevice) {
    DeviceInfo info;
    if (_devices.TryGetValue(hDevice, out info)) return info;
    info = new DeviceInfo { IsTouchpad = false, Preparsed = IntPtr.Zero, MaxSlots = 5, ScaleX = 0.35, ScaleY = 0.35 };
    uint ppSize = 0;
    if (GetRawInputDeviceInfo(hDevice, 0x20000005, IntPtr.Zero, ref ppSize) == uint.MaxValue || ppSize == 0) {
      _devices[hDevice] = info;
      return info;
    }
    IntPtr pp = Marshal.AllocHGlobal((int)ppSize);
    if (GetRawInputDeviceInfo(hDevice, 0x20000005, pp, ref ppSize) == uint.MaxValue) {
      Marshal.FreeHGlobal(pp);
      _devices[hDevice] = info;
      return info;
    }
    HIDP_CAPS caps;
    if (HidP_GetCaps(pp, out caps) != 0x00110000 || caps.UsagePage != 0x0D || caps.Usage != 0x05) {
      Marshal.FreeHGlobal(pp);
      _devices[hDevice] = info;
      return info;
    }
    info.IsTouchpad = true;
    info.Preparsed = pp;
    info.MaxSlots = Math.Max(1, (int)caps.NumberLinkCollectionNodes - 1);
    ushort vLen = caps.NumberInputValueCaps;
    if (vLen > 0) {
      var vCaps = new HIDP_VALUE_CAPS[vLen];
      if (HidP_GetValueCaps(0, vCaps, ref vLen, pp) == 0x00110000) {
        foreach (var v in vCaps) {
          if (v.UsagePage == 0x01 && v.UsageMin == 0x30 && v.LogicalMax > v.LogicalMin) {
            info.ScaleX = 480.0 / Math.Max(400, v.LogicalMax - v.LogicalMin);
          }
          if (v.UsagePage == 0x01 && v.UsageMin == 0x31 && v.LogicalMax > v.LogicalMin) {
            info.ScaleY = 320.0 / Math.Max(300, v.LogicalMax - v.LogicalMin);
          }
        }
      }
    }
    _devices[hDevice] = info;
    return info;
  }

  static void ProcessRawInput(IntPtr hRawInput) {
    uint headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
    uint size = 0;
    if (GetRawInputData(hRawInput, 0x10000003, IntPtr.Zero, ref size, headerSize) == uint.MaxValue || size <= headerSize) {
      return;
    }
    if (size > _rawBufCapacity) {
      if (_rawBuf != IntPtr.Zero) Marshal.FreeHGlobal(_rawBuf);
      _rawBuf = Marshal.AllocHGlobal((int)size);
      _rawBufCapacity = size;
    }
    if (GetRawInputData(hRawInput, 0x10000003, _rawBuf, ref size, headerSize) == uint.MaxValue) {
      return;
    }
    int dwType = Marshal.ReadInt32(_rawBuf, 0);
    if (dwType != 2) return;

    IntPtr hDevice = Marshal.ReadIntPtr(_rawBuf, 8);
    DeviceInfo dev = GetDevice(hDevice);
    if (!dev.IsTouchpad) return;

    uint dwSizeHid = (uint)Marshal.ReadInt32(_rawBuf, (int)headerSize);
    uint dwCount = (uint)Marshal.ReadInt32(_rawBuf, (int)headerSize + 4);
    if (dwSizeHid == 0 || dwCount == 0) return;

    for (uint r = 0; r < dwCount; r++) {
      IntPtr reportPtr = IntPtr.Add(_rawBuf, (int)headerSize + 8 + (int)(r * dwSizeHid));
      int activeCount = 0;
      double sumX = 0;
      double sumY = 0;

      for (ushort lc = 1; lc <= dev.MaxSlots; lc++) {
        uint usageLen = (uint)_usageList.Length;
        int st = HidP_GetUsages(0, 0x0D, lc, _usageList, ref usageLen, dev.Preparsed, reportPtr, dwSizeHid);
        bool tip = false;
        if (st == 0x00110000) {
          for (uint u = 0; u < usageLen; u++) {
            if (_usageList[u] == 0x42) {
              tip = true;
              break;
            }
          }
        }
        if (tip) {
          uint x = 0, y = 0;
          HidP_GetUsageValue(0, 0x01, lc, 0x30, out x, dev.Preparsed, reportPtr, dwSizeHid);
          HidP_GetUsageValue(0, 0x01, lc, 0x31, out y, dev.Preparsed, reportPtr, dwSizeHid);
          sumX += x;
          sumY += y;
          activeCount++;
        }
      }

      double avgX = activeCount > 0 ? sumX / activeCount : 0;
      double avgY = activeCount > 0 ? sumY / activeCount : 0;
      OnFrameComplete(dev, activeCount, avgX, avgY);
    }
  }

  static void OnFrameComplete(DeviceInfo dev, int count, double avgX, double avgY) {
    if (count == 2) {
      if (!_inTwoFingerGesture) {
        _inTwoFingerGesture = true;
        _gestureAllowedForWindow = IsWslgWindowActiveOrHovered();
        _prevAvgX = avgX;
        _prevAvgY = avgY;
        if (_gestureAllowedForWindow) {
          Console.WriteLine("START");
          Console.Out.Flush();
        }
      } else if (_gestureAllowedForWindow) {
        double dx = (avgX - _prevAvgX) * dev.ScaleX;
        double dy = (avgY - _prevAvgY) * dev.ScaleY;
        _prevAvgX = avgX;
        _prevAvgY = avgY;
        if (Math.Abs(dx) > 0.05 || Math.Abs(dy) > 0.05) {
          Console.WriteLine(string.Format(CultureInfo.InvariantCulture, "UPDATE {0:F2} {1:F2}", dx, dy));
          Console.Out.Flush();
        }
      }
    } else if (count >= 3) {
      if (_inTwoFingerGesture) {
        bool wasAllowed = _gestureAllowedForWindow;
        _inTwoFingerGesture = false;
        _gestureAllowedForWindow = false;
        if (wasAllowed) {
          Console.WriteLine("CANCEL");
          Console.Out.Flush();
        }
      }
    } else {
      if (_inTwoFingerGesture) {
        bool wasAllowed = _gestureAllowedForWindow;
        _inTwoFingerGesture = false;
        _gestureAllowedForWindow = false;
        if (wasAllowed) {
          Console.WriteLine("END");
          Console.Out.Flush();
        }
      }
    }
  }

  static IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam) {
    if (msg == 0x00FF) {
      ProcessRawInput(lParam);
      return IntPtr.Zero;
    }
    return DefWindowProc(hWnd, msg, wParam, lParam);
  }

  public static void Main() {
    var stdinWatch = new Thread(() => {
      try {
        while (Console.In.Read() != -1) {}
      } catch {}
      Environment.Exit(0);
    });
    stdinWatch.IsBackground = true;
    stdinWatch.Start();

    var wcx = new WNDCLASSEX {
      cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX)),
      lpfnWndProc = _wndProc,
      lpszClassName = "TheaverTpSink_" + Guid.NewGuid().ToString("N")
    };
    RegisterClassEx(ref wcx);
    IntPtr hwnd = CreateWindowEx(0, wcx.lpszClassName, "TheaverTpSink", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
    if (hwnd == IntPtr.Zero) return;

    var rid = new RAWINPUTDEVICE[] {
      new RAWINPUTDEVICE {
        usUsagePage = 0x000D,
        usUsage = 0x0005,
        dwFlags = 0x00000100,
        hwndTarget = hwnd
      }
    };
    if (!RegisterRawInputDevices(rid, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)))) {
      return;
    }

    Console.WriteLine("READY");
    Console.Out.Flush();

    MSG msg;
    while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {
      if (msg.message == 0x00FF) {
        ProcessRawInput(msg.lParam);
      } else {
        TranslateMessage(ref msg);
        DispatchMessage(ref msg);
      }
    }
  }
}
''';
}


/// Визуальный индикатор со стрелкой «Назад», выезжающий слева при свайпе двумя пальцами по тачпаду.
class TrackpadSwipeBackIndicator extends StatelessWidget {
  final double progress;
  final bool isArmed;

  const TrackpadSwipeBackIndicator({
    super.key,
    required this.progress,
    required this.isArmed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary.withValues(alpha: 1.0);

    final baseBgColor =
        isDark ? const Color(0xFF252528) : const Color(0xFFFFFFFF);
    final baseIconColor = isDark ? Colors.white : const Color(0xDD000000);
    final armedIconColor =
        primary.computeLuminance() > 0.6 ? const Color(0xDD000000) : Colors.white;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isArmed ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, armedT, _) {
        final bgColor = Color.lerp(baseBgColor, primary, armedT)!;
        final iconColor = Color.lerp(baseIconColor, armedIconColor, armedT)!;
        final scale = (0.75 + 0.25 * progress) * (1.0 + 0.12 * armedT);

        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: iconColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
