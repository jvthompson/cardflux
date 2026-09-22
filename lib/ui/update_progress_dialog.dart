import 'dart:io';

import 'package:flutter/material.dart';

import '../services/update/app_updater.dart';

/// Drives the download → extract → verify → install flow started from
/// [UpdateBanner], showing progress in a modal dialog. Follows the same
/// `showDialog` + `StatefulBuilder` shape as `_promptEditPlayerSettings`
/// (home_screen.dart:33-111).
///
/// On success this never returns normally: the app exits itself (releasing
/// its file/DLL locks) so the detached helper process can finish installing
/// and relaunch it -- by the time that would happen, the process is gone.
/// On failure, the dialog shows the error with a Close button; nothing in
/// `AppUpdater.downloadAndApply` touches the install directory until its
/// final, always-safe-to-reach step, so a failure here always leaves the
/// current install untouched.
Future<void> showUpdateProgressDialog(BuildContext context, {required String downloadUrl}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // `phase`/`progress`/`error` live in this outer builder's closure scope
    // (built once), not the inner StatefulBuilder's (rebuilt on every
    // setState) -- same nesting `_promptEditPlayerSettings` uses so mutable
    // state survives each rebuild instead of resetting to its initial value.
    builder: (context) {
      UpdatePhase? phase;
      double? progress;
      Object? error;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> run() async {
            try {
              await AppUpdater().downloadAndApply(
                downloadUrl: downloadUrl,
                onProgress: (p, prog) => setState(() {
                  phase = p;
                  progress = prog;
                }),
              );
              // The helper process has been launched and is waiting for this
              // process to exit -- give the final frame a moment to render,
              // then exit so it can proceed.
              await Future<void>.delayed(const Duration(milliseconds: 300));
              exit(0);
            } catch (e) {
              setState(() => error = e);
            }
          }

          // WidgetsBinding-free one-shot kickoff: StatefulBuilder has no
          // initState, so guard with a local flag captured by the closure.
          return _UpdateProgressBody(onStart: run, phase: phase, progress: progress, error: error);
        },
      );
    },
  );
}

class _UpdateProgressBody extends StatefulWidget {
  const _UpdateProgressBody({required this.onStart, required this.phase, required this.progress, required this.error});

  final Future<void> Function() onStart;
  final UpdatePhase? phase;
  final double? progress;
  final Object? error;

  @override
  State<_UpdateProgressBody> createState() => _UpdateProgressBodyState();
}

class _UpdateProgressBodyState extends State<_UpdateProgressBody> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      _started = true;
      widget.onStart();
    }

    if (widget.error != null) {
      return AlertDialog(
        title: const Text('Update Failed'),
        content: Text('${widget.error}'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    }

    return AlertDialog(
      title: const Text('Updating Cardflux'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: widget.progress),
          const SizedBox(height: 16),
          Text(_phaseLabel(widget.phase)),
        ],
      ),
    );
  }

  String _phaseLabel(UpdatePhase? phase) => switch (phase) {
    null || UpdatePhase.downloading => 'Downloading update'
        '${widget.progress != null ? ' (${(widget.progress! * 100).round()}%)' : ''}...',
    UpdatePhase.extracting => 'Extracting update...',
    UpdatePhase.verifying => 'Verifying update...',
    UpdatePhase.launchingInstaller => 'Installing — Cardflux will restart shortly...',
  };
}
