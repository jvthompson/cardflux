import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/app_directory.dart';
import '../../data/decks_directory_settings.dart';
import '../../data/games_directory_settings.dart';

enum UpdatePhase { downloading, extracting, verifying, launchingInstaller }

/// Downloads a Cardflux release zip, extracts it, and hands off to an
/// external PowerShell helper that waits for this process to exit, mirrors
/// the new files onto the install directory (preserving the user's
/// game_library/deck_library folders), relaunches the app, and cleans up
/// after itself. Windows locks a running .exe and its loaded DLLs, so the
/// running app can never perform that file-swap on itself directly.
///
/// Every step up through launching the helper is safe to abort -- nothing
/// touches the install directory until the detached helper process actually
/// runs, so a caller should call `exit(0)` immediately after
/// [downloadAndApply] returns, and only then.
class AppUpdater {
  Future<void> downloadAndApply({
    required String downloadUrl,
    required void Function(UpdatePhase phase, double? progress) onProgress,
  }) async {
    final tempDir = Directory(
      p.join(Directory.systemTemp.path, 'cardflux_update_${DateTime.now().millisecondsSinceEpoch}'),
    )..createSync(recursive: true);

    final zipPath = p.join(tempDir.path, 'update.zip');
    onProgress(UpdatePhase.downloading, 0);
    await _download(downloadUrl, zipPath, onProgress);

    onProgress(UpdatePhase.extracting, null);
    final stagedDir = p.join(tempDir.path, 'staged');
    await _extract(zipPath, stagedDir);

    onProgress(UpdatePhase.verifying, null);
    if (!File(p.join(stagedDir, 'Cardflux.exe')).existsSync()) {
      throw StateError('Downloaded update package is missing Cardflux.exe -- aborting.');
    }

    final installDir = appDirectoryPath;
    final excludeDirs = await _libraryPathsInsideInstallDir(installDir);
    final logPath = p.join(tempDir.path, 'apply_update.log');
    final scriptPath = p.join(tempDir.path, 'apply_update.ps1');
    File(scriptPath).writeAsStringSync(
      _buildHelperScript(installDir: installDir, stagedDir: stagedDir, excludeDirs: excludeDirs, logPath: logPath),
    );

    onProgress(UpdatePhase.launchingInstaller, null);
    await _launchHelper(scriptPath);
  }

  /// Launches the helper script via WMI's `Win32_Process.Create` rather than
  /// `Process.start(..., mode: ProcessStartMode.detached)`. Confirmed by
  /// testing: a plain detached child of this process does not reliably
  /// survive `exit(0)` -- the helper never got to run a single line, even
  /// though process creation itself reported success, consistent with
  /// Windows tearing the child down alongside this process's group/job when
  /// it exits. Spawning through WMI makes the new process a child of the WMI
  /// provider host (a separate system service) instead of this process, so
  /// it's fully independent of whatever process tree/job this app belongs
  /// to. This also gives a real success/failure signal (WMI's `ReturnValue`)
  /// where `Process.start` gave none.
  Future<void> _launchHelper(String scriptPath) async {
    final commandLine =
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$scriptPath" -TargetPid $pid';
    final escaped = commandLine.replaceAll("'", "''");
    final wmiCommand =
        '\$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = \'$escaped\' }; '
        'Write-Output \$r.ReturnValue';
    final result = await Process.run('powershell.exe', ['-NoProfile', '-Command', wmiCommand]);
    final returnValue = result.stdout.toString().trim();
    if (result.exitCode != 0 || returnValue != '0') {
      throw StateError('Failed to launch update helper (WMI ReturnValue=$returnValue): ${result.stderr}');
    }
  }

  Future<void> _download(String url, String destPath, void Function(UpdatePhase, double?) onProgress) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Update download failed with HTTP ${response.statusCode}.');
      }
      final contentLength = response.contentLength;
      final sink = File(destPath).openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0) onProgress(UpdatePhase.downloading, received / contentLength);
        }
      } finally {
        await sink.close();
      }
      if (contentLength > 0 && received != contentLength) {
        throw StateError('Update download was incomplete ($received of $contentLength bytes).');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extract(String zipPath, String destDir) async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$destDir' -Force",
    ]);
    if (result.exitCode != 0) {
      throw StateError('Failed to extract update package: ${result.stderr}');
    }
  }

  /// Reads the *actual configured* Games/Deck Library paths (not the default
  /// folder names) so a user who relocated or renamed either folder -- but
  /// left it inside the install directory -- still gets it correctly
  /// excluded from the file-swap below.
  Future<List<String>> _libraryPathsInsideInstallDir(String installDir) async {
    final normalizedInstall = p.normalize(installDir);
    final candidates = [await GamesDirectorySettings().getPath(), await DecksDirectorySettings().getPath()];
    return [
      for (final candidate in candidates)
        if (p.isWithin(normalizedInstall, p.normalize(candidate))) p.normalize(candidate),
    ];
  }

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  String _buildHelperScript({
    required String installDir,
    required String stagedDir,
    required List<String> excludeDirs,
    required String logPath,
  }) {
    final excludeArgs = excludeDirs.map(_psQuote).join(', ');
    return '''
param([int]\$TargetPid)
Start-Transcript -Path ${_psQuote(logPath)} -Append | Out-Null

# Wait for Cardflux.exe to fully release its file/DLL locks before copying.
Wait-Process -Id \$TargetPid -Timeout 30 -ErrorAction SilentlyContinue

\$excludeDirs = @($excludeArgs)
robocopy ${_psQuote(stagedDir)} ${_psQuote(installDir)} /MIR /XD @excludeDirs /NFL /NDL /NJH /R:3 /W:1
\$rc = \$LASTEXITCODE
# Robocopy exit codes 0-7 are all success states (bit flags); only >=8 is a
# real failure -- do NOT check `-eq 0`.
if (\$rc -ge 8) {
  # Write-Host (not Add-Content) -- the transcript already has this file
  # open for writing, so a second writer here would fail with a sharing
  # violation. Write-Host's output is captured by the transcript itself.
  Write-Host "robocopy failed with exit code \$rc"
  Stop-Transcript | Out-Null
  exit 1
}

Start-Process -FilePath (Join-Path ${_psQuote(installDir)} 'Cardflux.exe') -WorkingDirectory ${_psQuote(installDir)}

Stop-Transcript | Out-Null
Remove-Item -Path ${_psQuote(stagedDir)} -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Split-Path ${_psQuote(stagedDir)} -Parent) -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path \$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
''';
  }
}
