/// Cross-platform types for app update package installation.
enum UpdateInstallStatus {
  launched,
  permissionRequested,
  openedExternally,
  reloadedWeb,
  unsupported,
  failed,
}

class UpdateInstallResult {
  final UpdateInstallStatus status;
  final String message;

  const UpdateInstallResult(this.status, [this.message = '']);

  bool get isSuccess =>
      status == UpdateInstallStatus.launched ||
      status == UpdateInstallStatus.permissionRequested ||
      status == UpdateInstallStatus.openedExternally ||
      status == UpdateInstallStatus.reloadedWeb;
}

abstract class UpdatePlatformAdapter {
  String get platformName;

  Future<String> detectArchitecture();

  Future<String?> resolveUpdateSavePath(String downloadUrl, int latestBuild);

  Future<bool> fileExistsAndMatchesSha256(String path, String? expectedSha256);

  Future<void> verifyDownloadedFile(String path, String? expectedSha256);

  Future<void> deleteFileIfExists(String path);

  Future<UpdateInstallResult> installDownloadedPackage(String filePath);

  void reloadWebPage();
}
