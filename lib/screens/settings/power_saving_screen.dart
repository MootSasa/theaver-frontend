import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/power_saving_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../utils/haptic_utils.dart';

class PowerSavingScreen extends StatelessWidget {
  const PowerSavingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SettingsFloatingScaffold(
      title: l10n.translate('power_saving_title'),
      body: Consumer<PowerSavingProvider>(
        builder: (context, provider, _) {
          final settings = provider.settings;
          return ListView(
            padding: EdgeInsets.only(
              top: SettingsFloatingHeader.topClearanceOf(context) + 8,
              bottom: 24,
            ),
            children: [
              AdaptiveSwitchListTile(
                title: Text(l10n.translate('power_saving_enable')),
                subtitle: Text(l10n.translate('power_saving_enable_desc')),
                value: settings.powerSavingEnabled,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(powerSavingEnabled: value);
                },
              ),
              const Divider(),
              ListTile(
                title: Text(l10n.translate('power_saving_threshold')),
                subtitle: Text('${settings.batteryThreshold}%'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  HapticUtils.tap();
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
                                selected: settings.batteryThreshold == threshold,
                                onTap: () {
                                  provider.updateSettings(batteryThreshold: threshold);
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
                value: settings.reduceBackgroundActivity,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(reduceBackgroundActivity: value);
                },
              ),
              AdaptiveSwitchListTile(
                title: Text(l10n.translate('power_saving_lower_brightness')),
                subtitle: Text(l10n.translate('power_saving_lower_brightness_desc')),
                value: settings.lowerScreenBrightness,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(lowerScreenBrightness: value);
                },
              ),
              AdaptiveSwitchListTile(
                title: Text(l10n.translate('power_saving_limit_fps')),
                subtitle: Text(l10n.translate('power_saving_limit_fps_desc')),
                value: settings.limitFrameRate,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(limitFrameRate: value);
                },
              ),
              AdaptiveSwitchListTile(
                title: Text(l10n.translate('power_saving_disable_vibration')),
                subtitle: Text(l10n.translate('power_saving_disable_vibration_desc')),
                value: settings.disableVibrations,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(disableVibrations: value);
                },
              ),
              AdaptiveSwitchListTile(
                title: Text(l10n.translate('power_saving_disable_location')),
                subtitle: Text(l10n.translate('power_saving_disable_location_desc')),
                value: settings.disableLocationServices,
                onChanged: (bool value) {
                  HapticUtils.selection();
                  provider.updateSettings(disableLocationServices: value);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
