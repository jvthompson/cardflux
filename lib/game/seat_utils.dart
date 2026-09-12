import '../models/player.dart';

/// Whether the seat at [seatIndex] (0 = host, 1..playerCount-1 = clients in
/// join order -- see `HostServer.roster`) belongs to the "far" group for the
/// shared free-table area's mirroring (`TableScreen.isMirrored`), as opposed
/// to the "near" group the host itself always belongs to. This is a fixed,
/// global property of a seat -- unlike hand/zone row placement (see
/// [computeHandRowLayout]), it does NOT depend on who's looking:
///   - 2 players: seat 0 near, seat 1 far (identical to the original
///     2-player-only host/client mirroring).
///   - 3 players: seat 0 near, seats 1-2 far.
///   - 4 players: seats 0-1 near, seats 2-3 far.
bool isFarMirrorSeat(int seatIndex, int playerCount) {
  return switch (playerCount) {
    2 => seatIndex == 1,
    3 => seatIndex >= 1,
    4 => seatIndex >= 2,
    _ => seatIndex >= (playerCount / 2).ceil(),
  };
}

/// Which players occupy the bottom vs. top of a given player's own screen.
/// Always egocentric -- [bottomRow] is always the viewer's *own* near/far
/// group, so the local player is always somewhere in it (not necessarily
/// first: in a 3-player game, the two far-seated players share the bottom
/// with each other on their own screens). [topRow] is always the *other*
/// group. Row length simply follows group size (1 for the near group in a
/// 2- or 3-player game, 2 otherwise) -- whichever group is bigger takes up
/// the row it's assigned to, the same way for every viewer.
class HandRowLayout {
  const HandRowLayout({required this.bottomRow, required this.topRow});

  final List<PlayerInfo> bottomRow;
  final List<PlayerInfo> topRow;
}

/// Computes [localPlayerId]'s own hand-row layout from a **fixed, viewer-
/// independent canonical seating** (partitioned into near/far groups by
/// [isFarMirrorSeat] -- the exact same grouping the shared free-table area's
/// mirroring uses, so the two concepts can never drift apart), flipped as a
/// whole for a viewer in the far group -- never a per-seat relative
/// rotation. This matters because a per-viewer relative rotation (an
/// earlier, buggy implementation) let two different viewers see the same
/// third player in different slots -- inconsistent with a real table, where
/// everyone agrees on who sits where. A viewer in the near group sees the
/// near/far lists as-is (bottom/top respectively); a viewer in the far
/// group sees them swapped *and* reversed -- both far-seated viewers always
/// end up seeing the identical arrangement as each other (not just each
/// their own consistent-with-itself view), with themselves somewhere in
/// their own bottom row.
///
/// Verified by hand against a 4-player mockup: with seats 0/1 near and 2/3
/// far, every near-seated viewer sees an identical `bottom=[seat0,seat1],
/// top=[seat2,seat3]` arrangement, and every far-seated viewer sees an
/// identical 180°-rotated `bottom=[seat3,seat2], top=[seat1,seat0]`.
///
/// For 3 players (near={seat0}, far={seat1,seat2}), this same transform
/// gives seat 0 alone at the bottom, full width, with the other two split
/// across the top (matching the earlier 3-player decision) -- and, for
/// either of the *other* two players, themselves sharing the bottom
/// together (split) with seat 0 now alone at the top. An earlier revision
/// special-cased 3 players to always show whoever's local alone at the
/// bottom regardless of group, which broke this: both non-seat-0 players
/// independently saw themselves solo instead of sharing the bottom with
/// each other, an inconsistency in the same spirit as the 4-player bug this
/// function was already written to avoid.
///
/// [players] is already in seat order (`HostServer.roster`, host-assigned
/// via `AssignSeatsScreen` for 3-4 players, join order otherwise).
HandRowLayout computeHandRowLayout(List<PlayerInfo> players, String localPlayerId) {
  final n = players.length;
  if (n <= 1) return HandRowLayout(bottomRow: players, topRow: const []);
  final mySeat = players.indexWhere((p) => p.id == localPlayerId);
  final near = <PlayerInfo>[];
  final far = <PlayerInfo>[];
  for (var seat = 0; seat < n; seat++) {
    (isFarMirrorSeat(seat, n) ? far : near).add(players[seat]);
  }
  final iAmFar = isFarMirrorSeat(mySeat, n);
  return iAmFar
      ? HandRowLayout(bottomRow: far.reversed.toList(), topRow: near.reversed.toList())
      : HandRowLayout(bottomRow: near, topRow: far);
}
