import 'update_platform_types.dart';

UpdatePlatformAdapter createUpdatePlatformAdapter() => _StubUpdatePlatformAdapter();

class _StubUpdatePlatformAdapter implements UpdatePlatformAdapter {
  @override
  String get platformName => 'unknown';

  @override
  Future<String> detectArchitecture() async => 'universal';

  @override
  Future<String?> resolveUpdateSavePath(String downloadUrl, int latestBuild) async => null;

  @override
  Future<bool> fileExistsAndMatchesSha256(String path, String? expectedSha256) async => false;

  @override
  Future<void> verifyDownloadedFile(String path, String? expectedSha256) async {
    throw UnsupportedError('File downloads are not supported on this platform');
  }

  @override
  Future<void> deleteFileIfExists(String path) async {}

  @override
  Future<UpdateInstallResult> installDownloadedPackage(String filePath) async =>
      const UpdateInstallResult(UpdateInstallStatus.unsupported, 'Unsupported platform');

  @override
  void reloadWebPage() {}
}
