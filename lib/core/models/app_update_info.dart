class AppUpdateInfo {
  final String id;
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String releaseNotes;
  final bool isForced;
  final DateTime? createdAt;

  const AppUpdateInfo({
    required this.id,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isForced,
    this.createdAt,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> map) {
    return AppUpdateInfo(
      id: map['id']?.toString() ?? '',
      versionCode: (map['version_code'] as num?)?.toInt() ?? 0,
      versionName: map['version_name']?.toString() ?? '',
      apkUrl: map['apk_url']?.toString() ?? '',
      releaseNotes: map['release_notes']?.toString() ?? '',
      isForced: map['is_forced'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  bool get isApkUrl => apkUrl.toLowerCase().contains('.apk');
  bool get isStoreUrl =>
      apkUrl.toLowerCase().contains('play.google.com') ||
      apkUrl.toLowerCase().contains('apps.apple.com') ||
      apkUrl.startsWith('market://');
}
