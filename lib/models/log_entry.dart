/// One line of the in-game action log (see `GameSession`'s logging helpers)
/// -- [message] is already fully composed (actor name + action text), so a
/// viewer/exporter only ever needs to prepend `formatElapsedTime(elapsedMs)`.
class LogEntry {
  const LogEntry({required this.elapsedMs, required this.message});

  /// Milliseconds since the match's clock start (see `GameSession._clockStart`).
  final int elapsedMs;
  final String message;

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      elapsedMs: json['elapsedMs'] as int,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'elapsedMs': elapsedMs, 'message': message};
}

/// Formats [elapsedMs] as "HH:MM:SS" -- hand-rolled (no `intl` dependency),
/// matching the rest of the app's date/time formatting.
String formatElapsedTime(int elapsedMs) {
  final totalSeconds = elapsedMs ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(seconds)}';
}
