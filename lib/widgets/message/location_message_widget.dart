import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';

/// Telegram-style compact OpenStreetMap preview for `location`, `live_location`, and `venue` messages.
class LocationMessageWidget extends StatefulWidget {
  final Message message;
  final bool isMe;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final VoidCallback? onStopLiveLocation;

  const LocationMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    this.onStopLiveLocation,
  });

  @override
  State<LocationMessageWidget> createState() => _LocationMessageWidgetState();
}

class _LocationMessageWidgetState extends State<LocationMessageWidget> {
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _syncLiveTimer();
  }

  @override
  void didUpdateWidget(covariant LocationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaPayload != widget.message.mediaPayload ||
        oldWidget.message.messageType != widget.message.messageType) {
      _syncLiveTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  double? _readDouble(String key) {
    final val = widget.message.mediaPayload?[key];
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  String _readString(String key) =>
      (widget.message.mediaPayload?[key] ?? '').toString().trim();

  bool get _isLive => widget.message.messageType == 'live_location';
  bool get _isVenue => widget.message.messageType == 'venue';

  bool get _isLiveActive {
    if (!_isLive) return false;
    final rawFlag = widget.message.mediaPayload?['is_live_active'];
    if (rawFlag == false || rawFlag == 'false') return false;
    final exp = _parseExpiry();
    if (exp == null) return rawFlag == true;
    return exp.isAfter(DateTime.now().toUtc());
  }

  DateTime? _parseExpiry() {
    final raw = _readString('live_expires_at');
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  void _syncLiveTimer() {
    _countdownTimer?.cancel();
    final exp = _parseExpiry();
    if (!_isLive || exp == null || !_isLiveActive) {
      _remainingSeconds = 0;
      return;
    }
    final diff = exp.difference(DateTime.now().toUtc()).inSeconds;
    _remainingSeconds = diff > 0 ? diff : 0;
    if (_remainingSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!mounted) return;
        final left = exp.difference(DateTime.now().toUtc()).inSeconds;
        setState(() => _remainingSeconds = left > 0 ? left : 0);
        if (left <= 0) _countdownTimer?.cancel();
      });
    }
  }

  String _formatRemaining(int sec) {
    if (sec <= 0) return 'Трансляция завершена';
    final hours = sec ~/ 3600;
    final mins = (sec % 3600) ~/ 60;
    if (hours > 0) return 'Ещё $hours ч $mins мин';
    if (mins > 0) return 'Ещё $mins мин';
    return 'Меньше минуты';
  }

  Future<void> _openExternalMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=${lat.toStringAsFixed(6)}&mlon=${lng.toStringAsFixed(6)}#map=16/${lat.toStringAsFixed(6)}/${lng.toStringAsFixed(6)}',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        GlassToastService().showError(context, 'Не удалось открыть карту');
      }
    } catch (_) {
      if (mounted) {
        GlassToastService().showError(context, 'Не удалось открыть карту');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = _readDouble('latitude');
    final lng = _readDouble('longitude');
    if (lat == null || lng == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconoir.MapPin(width: 18, height: 18, color: widget.accentColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.message.content.isNotEmpty
                  ? widget.message.content
                  : 'Геопозиция недоступна',
              style: TextStyle(color: widget.textColor, fontSize: 14),
            ),
          ),
        ],
      );
    }

    final point = LatLng(lat, lng);
    final placeName = _readString('place_name').isNotEmpty
        ? _readString('place_name')
        : _readString('title');
    final address = _readString('address');
    final liveActive = _isLiveActive;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 268),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => _openExternalMap(lat, lng),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 248,
                height: 148,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: FlutterMap(
                        key: ValueKey('loc_map_${lat}_$lng'),
                        options: MapOptions(
                          initialCenter: point,
                          initialZoom: 15.0,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
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
                                point: point,
                                width: 38,
                                height: 38,
                                alignment: Alignment.topCenter,
                                child: Icon(
                                  Icons.location_pin,
                                  size: 36,
                                  color: liveActive
                                      ? const Color(0xFF34C759)
                                      : widget.accentColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconoir.OpenInWindow(
                              width: 12,
                              height: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'OSM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLive)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: liveActive
                                ? const Color(0xFF34C759)
                                : Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            liveActive ? 'LIVE' : 'Завершена',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_isVenue && (placeName.isNotEmpty || address.isNotEmpty)) ...[
            if (placeName.isNotEmpty)
              Text(
                placeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (address.isNotEmpty)
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: widget.subtextColor, fontSize: 12),
              ),
          ] else if (_isLive) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    liveActive
                        ? _formatRemaining(_remainingSeconds)
                        : 'Трансляция геопозиции завершена',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: liveActive
                          ? widget.textColor
                          : widget.subtextColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.isMe && liveActive && widget.onStopLiveLocation != null)
                  TextButton(
                    onPressed: widget.onStopLiveLocation,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Остановить',
                      style: TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ] else
            Text(
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              style: TextStyle(color: widget.subtextColor, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}
