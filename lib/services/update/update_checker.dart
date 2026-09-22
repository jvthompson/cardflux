import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The exact release-asset filename every published Cardflux release must
/// attach -- kept as one constant so the checker (here) and the publish
/// tooling (`tool/publish_release.ps1`) can never drift apart on the name.
const cardfluxReleaseAssetName = 'cardflux-windows.zip';

/// Polls GitHub Releases once per app launch to see whether a newer build of
/// Cardflux has been published, so [HomeScreen] can offer to install it.
/// Deliberately best-effort: any failure (offline, no releases yet, GitHub
/// rate-limited) just leaves [updateAvailable] false rather than surfacing an
/// error, since this is a convenience check, not a required app function --
/// mirrors `fetchPublicIPv4()`'s catch-and-return-null approach in
/// `network_info.dart`.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({this.repo = 'jvthompson/cardflux'});

  final String repo;

  bool _updateAvailable = false;
  String? _latestTag;
  String? _downloadUrl;
  int? _downloadSize;

  bool get updateAvailable => _updateAvailable;
  String? get latestTag => _latestTag;
  String? get downloadUrl => _downloadUrl;
  int? get downloadSize => _downloadSize;

  Future<void> checkForUpdate() async {
    final client = HttpClient();
    try {
      final localBuild = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
      if (localBuild == null) return;

      final request = await client.getUrl(Uri.https('api.github.com', '/repos/$repo/releases/latest'));
      // GitHub rejects requests with no User-Agent; Accept pins the response
      // shape to the REST API's JSON representation.
      request.headers.set(HttpHeaders.userAgentHeader, 'Cardflux-Updater');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tag = json['tag_name'] as String?;
      if (tag == null) return;
      final remoteBuild = int.tryParse(RegExp(r'\+(\d+)$').firstMatch(tag)?.group(1) ?? '');
      if (remoteBuild == null || remoteBuild <= localBuild) return;

      final assets = json['assets'] as List<dynamic>? ?? [];
      Map<String, dynamic>? asset;
      for (final entry in assets.cast<Map<String, dynamic>>()) {
        if (entry['name'] == cardfluxReleaseAssetName) {
          asset = entry;
          break;
        }
      }
      if (asset == null) return;

      _updateAvailable = true;
      _latestTag = tag;
      _downloadUrl = asset['browser_download_url'] as String?;
      _downloadSize = asset['size'] as int?;
      notifyListeners();
    } catch (_) {
      // Offline, rate-limited, malformed response, etc. -- silently skip.
    } finally {
      client.close(force: true);
    }
  }
}
