import 'package:web/web.dart' as web;

import 'update_platform_types.dart';

UpdatePlatformAdapter createUpdatePlatformAdapter() => _WebUpdatePlatformAdapter();

class _WebUpdatePlatformAdapter implements UpdatePlatformAdapter {
  @override
  String get platformName => 'web';

  @override
  Future<String> detectArchitecture() async => 'universal';

  @override
  Future<String?> resolveUpdateSavePath(String downloadUrl, int latestBuild) async => null;

  @override
  Future<bool> fileExistsAndMatchesSha256(String path, String? expectedSha256) async => false;

  @override
  Future<void> verifyDownloadedFile(String path, String? expectedSha256) async {
    throw UnsupportedError('Binary package downloads are not supported on Web');
  }

  @override
  Future<void> deleteFileIfExists(String path) async {}

  @override
  Future<UpdateInstallResult> installDownloadedPackage(String filePath) async {
    reloadWebPage();
    return const UpdateInstallResult(UpdateInstallStatus.reloadedWeb, 'Web reload triggered');
  }

  @override
  void reloadWebPage() {
    try {
      web.window.location.reload();
    } catch (_) {}
  }
}
