// Data models exchanged with the Patchfly server.

class PatchflyUpdate {
  final String patchId;
  final int patchNumber;
  final String sha256;
  final String signature;
  final int sizeBytes;
  final String downloadUrl;
  final bool isDelta;
  final String? basePatchId;
  final String? minAppVersion;
  final String? maxAppVersion;
  final int rolloutPercent;
  final String releaseVersion;
  final String channel;
  final String? releaseNotes;

  PatchflyUpdate({
    required this.patchId,
    required this.patchNumber,
    required this.sha256,
    required this.signature,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.isDelta,
    this.basePatchId,
    this.minAppVersion,
    this.maxAppVersion,
    required this.rolloutPercent,
    required this.releaseVersion,
    required this.channel,
    this.releaseNotes,
  });

  factory PatchflyUpdate.fromJson(Map<String, dynamic> j) {
    final update = j['update'] as Map<String, dynamic>?;
    if (update == null) throw FormatException('No update in response');
    final patch = update['patch'] as Map<String, dynamic>;
    final release = update['release'] as Map<String, dynamic>;
    return PatchflyUpdate(
      patchId: patch['id'] as String,
      patchNumber: patch['patchNumber'] as int,
      sha256: patch['sha256'] as String,
      signature: patch['signature'] as String,
      sizeBytes: patch['sizeBytes'] as int,
      downloadUrl: patch['downloadUrl'] as String,
      isDelta: patch['isDelta'] as bool? ?? false,
      basePatchId: patch['basePatchId'] as String?,
      minAppVersion: patch['minAppVersion'] as String?,
      maxAppVersion: patch['maxAppVersion'] as String?,
      rolloutPercent: patch['rolloutPercent'] as int? ?? 100,
      releaseVersion: release['version'] as String,
      channel: release['channel'] as String? ?? 'stable',
      releaseNotes: release['notes'] as String?,
    );
  }

  @override
  String toString() =>
      'PatchflyUpdate(patch#$patchNumber v$releaseVersion channel=$channel '
      'sha=$sha256)';
}

class PatchflyConfig {
  final String serverUrl;
  final String sdkKey;
  final String channel;
  final String? deviceId;

  const PatchflyConfig({
    required this.serverUrl,
    required this.sdkKey,
    this.channel = 'stable',
    this.deviceId,
  });
}

class PatchflyException implements Exception {
  final String message;
  PatchflyException(this.message);
  @override
  String toString() => 'PatchflyException: $message';
}

class PatchflyNetworkException extends PatchflyException {
  PatchflyNetworkException(super.message);
  @override
  String toString() => 'PatchflyNetworkException: $message';
}

class PatchflySignatureException extends PatchflyException {
  PatchflySignatureException(super.message);
  @override
  String toString() => 'PatchflySignatureException: $message';
}

class PatchflyApplyException extends PatchflyException {
  PatchflyApplyException(super.message);
  @override
  String toString() => 'PatchflyApplyException: $message';
}
