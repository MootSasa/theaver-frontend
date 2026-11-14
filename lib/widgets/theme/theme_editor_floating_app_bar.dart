import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../settings/settings_floating_header.dart';

/// Total height of the floating app bar including vertical spacing.
const double kThemeEditorAppBarTotalHeight =
    SettingsFloatingHeader.topClearanceOffset;

/// Floating AppBar for the Theme Editor featuring 3 distinct pills:
/// 1. Left pill: Back button (`44x44` circular pill)
/// 2. Center capsule: tightly hugging title oval
/// 3. Right capsule: Share & Apply actions
class ThemeEditorFloatingAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onApply;
  final bool isSaving;

  const ThemeEditorFloatingAppBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onShare,
    required this.onApply,
    this.isSaving = false,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(kThemeEditorAppBarTotalHeight);

  @override
  Widget build(BuildContext context) {
    final foregroundColor = SettingsFloatingHeader.foregroundColorOf(context);

    return SettingsFloatingHeader(
      title: title,
      onBack: onBack,
      actions: [
        SettingsHeaderAction(
          onTap: onShare,
          icon: iconoir.ShareAndroid(
            width: 20.0,
            height: 20.0,
            color: foregroundColor,
          ),
        ),
        SettingsHeaderAction(
          enabled: !isSaving,
          onTap: isSaving ? null : onApply,
          child: isSaving
              ? SizedBox(
                  width: 18.0,
                  height: 18.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              : iconoir.Check(
                  width: 22.0,
                  height: 22.0,
                  color: foregroundColor,
                ),
        ),
      ],
    );
  }
}
