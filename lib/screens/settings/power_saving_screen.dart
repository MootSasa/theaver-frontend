import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/adaptive_switch.dart';

class PowerSavingScreen extends StatefulWidget {
  const PowerSavingScreen({Key? key}) : super(key: key);

  @override
  State<PowerSavingScreen> createState() => _PowerSavingScreenState();
}

class _PowerSavingScreenState extends State<PowerSavingScreen> {
  final SettingsService _settingsService = SettingsService();
  late PowerSavingSettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = _settingsService.powerSavingSettings;
    setState(() => _isLoading = false);
  }

  Future<void> _updateSettings({
    bool? powerSavingEnabled,
    int? batteryThreshold,
    bool? reduceBackgroundActivity,
    bool? lowerScreenBrightness,
    bool? limitFrameRate,
    bool? disableVibrations,
    bool? disableLocationServices,
  }) async {
    await _settingsService.updatePowerSavingSettings(
      powerSavingEnabled: powerSavingEnabled,
      batteryThreshold: batteryThreshold,
      reduceBackgroundActivity: reduceBackgroundActivity,
      lowerScreenBrightness: lowerScreenBrightness,
      limitFrameRate: limitFrameRate,
      disableVibrations: disableVibrations,
      disableLocationServices: disableLocationServices,
    );
    _settings = _settingsService.powerSavingSettings;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('power_saving_title')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_enable')),
                  subtitle: Text(l10n.translate('power_saving_enable_desc')),
                  value: _settings.powerSavingEnabled,
                  onChanged: (bool value) {
                    _updateSettings(powerSavingEnabled: value);
                  },
                ),
                const Divider(),
                ListTile(
                  title: Text(l10n.translate('power_saving_threshold')),
                  subtitle: Text('${_settings.batteryThreshold}%'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext dialogContext) {
                        return AlertDialog(
                          title: Text(l10n.translate('power_saving_threshold_title')),
                          content: SingleChildScrollView(
                            child: ListBody(
                              children: [20, 15, 10, 5].map((int threshold) {
                                return ListTile(
                                  title: Text('$threshold%'),
                                  selected: _settings.batteryThreshold == threshold,
                                  onTap: () {
                                    _updateSettings(batteryThreshold: threshold);
                                    Navigator.of(dialogContext).pop();
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const Divider(),
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_reduce_background')),
                  subtitle: Text(l10n.translate('power_saving_reduce_background_desc')),
                  value: _settings.reduceBackgroundActivity,
                  onChanged: (bool value) {
                    _updateSettings(reduceBackgroundActivity: value);
                  },
                ),
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_lower_brightness')),
                  subtitle: Text(l10n.translate('power_saving_lower_brightness_desc')),
                  value: _settings.lowerScreenBrightness,
                  onChanged: (bool value) {
                    _updateSettings(lowerScreenBrightness: value);
                  },
                ),
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_limit_fps')),
                  subtitle: Text(l10n.translate('power_saving_limit_fps_desc')),
                  value: _settings.limitFrameRate,
                  onChanged: (bool value) {
                    _updateSettings(limitFrameRate: value);
                  },
                ),
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_disable_vibration')),
                  subtitle: Text(l10n.translate('power_saving_disable_vibration_desc')),
                  value: _settings.disableVibrations,
                  onChanged: (bool value) {
                    _updateSettings(disableVibrations: value);
                  },
                ),
                AdaptiveSwitchListTile(
                  title: Text(l10n.translate('power_saving_disable_location')),
                  subtitle: Text(l10n.translate('power_saving_disable_location_desc')),
                  value: _settings.disableLocationServices,
                  onChanged: (bool value) {
                    _updateSettings(disableLocationServices: value);
                  },
                ),
              ],
            ),
    );
  }
}
