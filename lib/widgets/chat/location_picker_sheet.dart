import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:latlong2/latlong.dart';

import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

class LocationPickResult {
  final String messageType; // 'location' | 'live_location' | 'venue'
  final double latitude;
  final double longitude;
  final int? livePeriod;
  final int? heading;
  final double? horizontalAccuracy;
  final String? placeName;
  final String? address;

  const LocationPickResult({
    required this.messageType,
    required this.latitude,
    required this.longitude,
    this.livePeriod,
    this.heading,
    this.horizontalAccuracy,
    this.placeName,
    this.address,
  });
}

Future<LocationPickResult?> showLocationPickerSheet(BuildContext context) {
  return showTheavModalSheet<LocationPickResult>(
    context: context,
    title: 'Геопозиция',
    showCloseButton: true,
    builder: (ctx) => const _LocationPickerSheetBody(),
  );
}

class _LocationPickerSheetBody extends StatefulWidget {
  const _LocationPickerSheetBody();

  @override
  State<_LocationPickerSheetBody> createState() =>
      _LocationPickerSheetBodyState();
}

class _LocationPickerSheetBodyState extends State<_LocationPickerSheetBody> {
  static const LatLng _defaultCenter = LatLng(55.7558, 37.6173);

  final MapController _mapController = MapController();
  final TextEditingController _placeNameCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();

  LatLng _selectedPoint = _defaultCenter;
  double? _accuracyMeters;
  int? _heading;
  bool _locating = true;
  String? _locationNotice;
  int _selectedMode = 0; // 0 = static, 1 = live, 2 = venue
  int _livePeriodSeconds = 900; // 15 min default

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
  }

  @override
  void dispose() {
    _placeNameCtrl.dispose();
    _addressCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentLocation() async {
    if (mounted) {
      setState(() {
        _locating = true;
        _locationNotice = null;
      });
    }
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(() {
            _locating = false;
            _locationNotice = 'Служба геолокации отключена — выберите точку на карте';
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locating = false;
            _locationNotice = 'Нет доступа к GPS — выберите точку вручную';
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      final pt = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _selectedPoint = pt;
        _accuracyMeters = pos.accuracy > 0 ? pos.accuracy : null;
        _heading = pos.heading >= 0 && pos.heading <= 360
            ? pos.heading.round()
            : null;
        _locating = false;
        _locationNotice = null;
      });
      _mapController.move(pt, 15.5);
    } catch (_) {
      if (mounted) {
        setState(() {
          _locating = false;
          _locationNotice = 'Нажмите на карту или перетащите для выбора точки';
        });
      }
    }
  }

  void _submit() {
    HapticUtils.selection();
    if (_selectedMode == 2) {
      final place = _placeNameCtrl.text.trim();
      final addr = _addressCtrl.text.trim();
      if (place.isEmpty && addr.isEmpty) {
        GlassToastService().showError(
          context,
          'Укажите название места или адрес',
        );
        return;
      }
      Navigator.of(context).pop(
        LocationPickResult(
          messageType: 'venue',
          latitude: _selectedPoint.latitude,
          longitude: _selectedPoint.longitude,
          horizontalAccuracy: _accuracyMeters,
          placeName: place.isEmpty ? addr : place,
          address: addr.isEmpty ? null : addr,
        ),
      );
      return;
    }

    if (_selectedMode == 1) {
      Navigator.of(context).pop(
        LocationPickResult(
          messageType: 'live_location',
          latitude: _selectedPoint.latitude,
          longitude: _selectedPoint.longitude,
          livePeriod: _livePeriodSeconds,
          heading: _heading,
          horizontalAccuracy: _accuracyMeters,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      LocationPickResult(
        messageType: 'location',
        latitude: _selectedPoint.latitude,
        longitude: _selectedPoint.longitude,
        heading: _heading,
        horizontalAccuracy: _accuracyMeters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final maxH = MediaQuery.of(context).size.height * 0.78;
    const modeLabels = <String>['Точка', 'Трансляция', 'Место'];
    const liveDurations = <({int seconds, String label})>[
      (seconds: 900, label: '15 мин'),
      (seconds: 3600, label: '1 час'),
      (seconds: 28800, label: '8 часов'),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 220,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _selectedPoint,
                        initialZoom: 15.0,
                        minZoom: 2.0,
                        maxZoom: 18.0,
                        onTap: (_, point) {
                          HapticUtils.tap();
                          setState(() => _selectedPoint = point);
                        },
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            setState(() => _selectedPoint = camera.center);
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.theaver.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint,
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: Icon(
                                Icons.location_pin,
                                size: 42,
                                color: palette.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Material(
                        color: palette.surface.withValues(alpha: 0.9),
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          tooltip: 'Моё местоположение',
                          onPressed: _locating ? null : _detectCurrentLocation,
                          icon: _locating
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.primary,
                                  ),
                                )
                              : iconoir.Compass(
                                  width: 20,
                                  height: 20,
                                  color: palette.primary,
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selectedPoint.latitude.toStringAsFixed(5)}, ${_selectedPoint.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_locationNotice != null) ...[
              const SizedBox(height: 8),
              Text(
                _locationNotice!,
                style: TextStyle(color: palette.subtext, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (int i = 0; i < modeLabels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        setState(() => _selectedMode = i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _selectedMode == i
                              ? palette.primary.withValues(alpha: 0.16)
                              : palette.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedMode == i
                                ? palette.primary
                                : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          modeLabels[i],
                          style: TextStyle(
                            color: _selectedMode == i
                                ? palette.primary
                                : palette.onSurface,
                            fontSize: 13,
                            fontWeight: _selectedMode == i
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedMode == 1)
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                children: [
                  for (final opt in liveDurations)
                    TheavListRow(
                      leading: iconoir.Timer(
                        width: 20,
                        height: 20,
                        color: _livePeriodSeconds == opt.seconds
                            ? palette.primary
                            : palette.subtext,
                      ),
                      title: 'Делиться ${opt.label}',
                      trailing: _livePeriodSeconds == opt.seconds
                          ? Icon(Icons.check_rounded, color: palette.primary)
                          : null,
                      onTap: () {
                        HapticUtils.selection();
                        setState(() => _livePeriodSeconds = opt.seconds);
                      },
                    ),
                ],
              ),
            if (_selectedMode == 2) ...[
              TextField(
                controller: _placeNameCtrl,
                decoration: InputDecoration(
                  hintText: 'Название места (например, Кофейня)',
                  filled: true,
                  fillColor: palette.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider, width: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  hintText: 'Адрес (необязательно)',
                  filled: true,
                  fillColor: palette.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.divider, width: 0.5),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TheavFloatingPillButton(
              label: _selectedMode == 1
                  ? 'Начать трансляцию'
                  : (_selectedMode == 2
                      ? 'Отправить место'
                      : 'Отправить геопозицию'),
              icon: const iconoir.MapPin(
                width: 18,
                height: 18,
                color: Colors.white,
              ),
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
