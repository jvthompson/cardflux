import 'table_state.dart';

/// A [TableState] snapshot written to disk by the host's/practice player's
/// "Save Game" action (see `SaveGameFileOps`), paired with when it was
/// captured. [state.searches] is always empty here -- an open Search window
/// is session-local UI state, not worth restoring on load.
class SavedGame {
  const SavedGame({required this.savedAt, required this.state});

  final DateTime savedAt;
  final TableState state;

  factory SavedGame.fromJson(Map<String, dynamic> json) {
    return SavedGame(
      savedAt: DateTime.parse(json['savedAt'] as String),
      state: TableState.fromJson((json['state'] as Map).cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toJson() => {'savedAt': savedAt.toIso8601String(), 'state': state.toJson()};
}
