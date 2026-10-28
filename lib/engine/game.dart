import 'dart:math';
import 'models.dart';

/// Switches that stay configurable from the settings screen.
class GameRules {
  const GameRules({this.doctorMaySelfProtect = true, this.dualMafiaPower = false});
  final bool doctorMaySelfProtect;

  /// One Dajjal (the sheikh) also carries the silencer's ability.
  final bool dualMafiaPower;
}

class Game {
  Game(this.players, {Random? rng, this.rules = const GameRules()})
      : rng = rng ?? Random();
  final List<Player> players;
  final Random rng;
  final GameRules rules;
  bool _goodBoyUsed = false;

  /// The sniper owns a single bullet for the whole match.
  bool sniperShotUsed = false;

  /// Set when the Good Boy has just been eliminated and still has to choose
  /// the living player who dies with him. Cleared by [goodBoyTake].
  Player? pendingGoodBoy;

  List<Player> get alive => players.where((p) => p.alive).toList();
  int get aliveMafia => alive.where((p) => p.isMafia).length;
  int get aliveGood => alive.length - aliveMafia;

  /// Teammates of [p], excluding p. Empty for non-mafia.
  List<String> teammatesOf(Player p) => !p.isMafia
      ? const []
      : players.where((q) => q.isMafia && q != p).map((q) => q.name).toList();

  /// Whether [p] (alive or not) owns the silencing ability.
  bool canSilence(Player p) =>
      p.role == Role.silencer || (rules.dualMafiaPower && p.role == Role.sheikh);

  /// Who chooses the night victim. The assassination belongs to the sheikh;
  /// while he lives he alone chooses. If he is gone (or absent) every living
  /// Dajjal votes, as in the original game. (The source material does not
  /// say what happens to the power when the sheikh dies: this keeps the
  /// original behavior.)
  List<Player> get nightKillers {
    final team = alive.where((p) => p.isMafia).toList();
    final sheikh = team.where((p) => p.role == Role.sheikh).firstOrNull;
    return sheikh != null ? [sheikh] : team;
  }

  /// The living Dajjal who may silence a player tonight, if any. The ability
  /// is not transferred when its owner dies.
  Player? get nightSilencer =>
      alive.where((p) => p.isMafia && canSilence(p)).firstOrNull;

  /// Private investigation result: only the team, never the exact role.
  bool investigate(Player target) => target.isMafia;

  /// Resolves the night kill. Returns the eliminated players (may be empty).
  List<Player> resolveNight(
      {required Player? mafiaTarget, Player? protectedPlayer}) {
    if (mafiaTarget == null || !mafiaTarget.alive) return [];
    if (identical(mafiaTarget, protectedPlayer)) return [];
    return _eliminate(mafiaTarget);
  }

  /// The sniper's single shot.
  /// - target is Mafia: the target dies, the sniper stays alive.
  /// - target is on the other team: the target dies and the sniper is
  ///   eliminated too.
  List<Player> sniperShoot(Player sniper, Player target) {
    if (sniperShotUsed || !sniper.alive || !target.alive) return [];
    if (identical(sniper, target)) return [];
    sniperShotUsed = true;
    final out = _eliminate(target);
    if (!target.isMafia) out.addAll(_eliminate(sniper));
    return out;
  }

  /// Tally votes: voter -> target. Mayor counts 3 once revealed.
  /// Returns leaders (more than one entry means a tie).
  List<Player> tally(Map<Player, Player> votes) {
    final score = <Player, int>{};
    votes.forEach((voter, target) {
      if (!voter.alive || !target.alive) return;
      score[target] = (score[target] ?? 0) +
          (voter.role == Role.mayor && voter.mayorRevealed ? 3 : 1);
    });
    if (score.isEmpty) return [];
    final top = score.values.reduce(max);
    return score.entries
        .where((e) => e.value == top)
        .map((e) => e.key)
        .toList();
  }

  List<Player> eliminateByVote(Player p) => _eliminate(p);

  /// Completes the Good Boy's ability: [target] dies with him.
  List<Player> goodBoyTake(Player target) {
    if (pendingGoodBoy == null || !target.alive) return [];
    pendingGoodBoy = null;
    return _eliminate(target);
  }

  List<Player> _eliminate(Player p) {
    if (!p.alive) return [];
    p.alive = false;
    // Good Boy: whether voted out or killed at night, he picks one living
    // player to take with him (once per match).
    if (p.role == Role.goodBoy && !_goodBoyUsed && alive.isNotEmpty) {
      _goodBoyUsed = true;
      pendingGoodBoy = p;
    }
    return [p];
  }

  MatchResult? checkVictory() {
    if (aliveMafia == 0) {
      return MatchResult(Faction.good, aliveGood, aliveGood * pointsPerSurvivor);
    }
    if (aliveMafia >= aliveGood) {
      return MatchResult(
          Faction.mafia, aliveMafia, aliveMafia * pointsPerSurvivor);
    }
    return null;
  }
}
