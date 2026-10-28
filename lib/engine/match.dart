import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/settings.dart';
import 'config.dart';
import 'game.dart';
import 'models.dart';

enum Phase {
  reveal,
  returnToFirst,
  night,
  goodBoy,
  dawn,
  discuss,
  vote,
  tie,
  defense,
  verdict,
  dayEnd,
  ended
}

/// Fixed night order: Dajjal, Wild al-Santi, Investigator, Sniper.
/// A stage whose role is dead or absent is played as a camouflage screen so
/// that nothing about the role set leaks to the table.
const nightOrder = [Role.mafia, Role.doctor, Role.investigator, Role.sniper];

/// Drives one match: reveal -> (night -> day)* -> ended.
class MatchController extends ChangeNotifier {
  MatchController(this.game, this.settings);

  static MatchController create(List<String> names, RoleConfig cfg, AppSettings s,
      {Random? rng}) {
    final r = rng ?? Random();
    final players = assignRoles(names, cfg, r);
    return MatchController(
        Game(players, rng: r, rules: GameRules(doctorMaySelfProtect: s.doctorSelf, dualMafiaPower: cfg.merged)),
        s);
  }

  final Game game;
  final AppSettings settings;

  Phase phase = Phase.reveal;
  int revealIndex = 0;
  int round = 1;

  /// Index of the current stage in [nightOrder].
  int nightIdx = 0;

  /// Dajjal stage steps: first the kill votes of [nightKillers], then (if
  /// someone owns it) the silencing choice of [nightSilencer].
  List<Player> nightKillers = [];
  Player? nightSilencer;
  int mafiaIdx = 0;

  /// Player silenced for today's discussion (chosen the night before).
  Player? silencedTarget, silenced;
  bool _goodBoyAtNight = false;
  Map<Player, int> mafiaVotes = {};
  Player? protectedPlayer, sniperTarget, _nightSniper;
  List<Player> dawnDeaths = [];

  List<Player> speakers = [];
  int speakerIdx = 0;

  List<Player> voters = [];
  int voterIdx = 0;
  Map<Player, Player> votes = {};
  List<Player> candidates = [];
  List<Player> tiedLeaders = [];
  bool revoted = false;
  Player? accused;
  int yes = 0, no = 0;
  List<Player> dayDeaths = [];

  MatchResult? result;
  bool _saved = false;

  String get viewKey =>
      '$phase-$round-$revealIndex-$nightIdx-$mafiaIdx-$speakerIdx-$voterIdx-$revoted';

  // ----- reveal -----
  void nextReveal() {
    if (phase != Phase.reveal) return;
    revealIndex++;
    if (revealIndex >= game.players.length) {
      // Everyone has seen their own role. Return the phone to the first player.
      phase = Phase.returnToFirst;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  /// Called after the first player confirms they have the phone again.
  void beginFirstNight() {
    if (phase != Phase.returnToFirst) return;
    _startNight();
  }

  // ----- night -----
  Role get stageRole => nightOrder[nightIdx];

  /// True when the current stage has a living participant. Otherwise the
  /// stage is a camouflage screen.
  bool get stageActive => switch (stageRole) {
        Role.mafia => mafiaStepCount > 0,
        Role.sniper =>
          !game.sniperShotUsed && game.alive.any((p) => p.role == Role.sniper),
        _ => game.alive.any((p) => p.role == stageRole),
      };

  /// The player holding the phone in the current (active) stage.
  Player? get stageActor {
    if (!stageActive) return null;
    if (stageRole == Role.mafia) {
      return mafiaIdx < nightKillers.length ? nightKillers[mafiaIdx] : nightSilencer;
    }
    return game.alive.firstWhere((p) => p.role == stageRole);
  }

  int get mafiaStepCount => nightKillers.length + (nightSilencer != null ? 1 : 0);

  /// True while the current Dajjal step is the silencing choice.
  bool get mafiaStepIsSilence =>
      stageRole == Role.mafia && mafiaIdx >= nightKillers.length;

  void _startNight() {
    nightKillers = game.nightKillers;
    nightSilencer = game.nightSilencer;
    silencedTarget = silenced = null;
    nightIdx = 0;
    mafiaIdx = 0;
    mafiaVotes = {};
    protectedPlayer = sniperTarget = null;
    _nightSniper = game.alive.where((p) => p.role == Role.sniper).firstOrNull;
    phase = Phase.night;
    notifyListeners();
  }

  /// Submits the current stage. For a camouflage stage the argument is
  /// ignored and the stage simply ends.
  void submitNight(Player? target) {
    if (phase != Phase.night) return;
    if (stageActive) {
      switch (stageRole) {
        case Role.mafia:
          if (mafiaStepIsSilence) {
            final who = stageActor;
            if (target != null && target.alive && !identical(target, who)) {
              silencedTarget = target;
            }
          } else if (target != null && target.alive) {
            mafiaVotes[target] = (mafiaVotes[target] ?? 0) + 1;
          }
          mafiaIdx++;
          if (mafiaIdx < mafiaStepCount) {
            notifyListeners();
            return;
          }
        case Role.doctor:
          final self = identical(target, stageActor);
          protectedPlayer =
              (self && !game.rules.doctorMaySelfProtect) ? null : target;
        case Role.sniper:
          sniperTarget = target;
        default:
          break;
      }
    }
    nightIdx++;
    if (nightIdx >= nightOrder.length) {
      _resolveNight();
    } else {
      notifyListeners();
    }
  }

  void _resolveNight() {
    Player? victim;
    if (mafiaVotes.isNotEmpty) {
      final top = mafiaVotes.values.reduce(max);
      final tied =
          mafiaVotes.entries.where((e) => e.value == top).map((e) => e.key).toList();
      victim = tied[game.rng.nextInt(tied.length)];
    }
    dawnDeaths = List.of(
        game.resolveNight(mafiaTarget: victim, protectedPlayer: protectedPlayer));
    final sn = _nightSniper;
    final t = sniperTarget;
    if (sn != null && sn.alive && t != null && t.alive) {
      dawnDeaths.addAll(game.sniperShoot(sn, t));
    }
    // Silencing only works if its owner survived the night and the target too.
    final sil = nightSilencer;
    final st = silencedTarget;
    silenced = (sil != null && sil.alive && st != null && st.alive) ? st : null;
    if (game.pendingGoodBoy != null) {
      _goodBoyAtNight = true;
      phase = Phase.goodBoy;
      notifyListeners();
    } else {
      _finishNight();
    }
  }

  void _finishNight() {
    result = game.checkVictory();
    phase = result != null ? Phase.ended : Phase.dawn;
    notifyListeners();
  }

  // ----- Good Boy -----
  /// The eliminated Good Boy picks a living player who dies with him.
  Player? get goodBoyPlayer => game.pendingGoodBoy;

  void goodBoyPick(Player target) {
    if (phase != Phase.goodBoy) return;
    final taken = game.goodBoyTake(target);
    if (taken.isEmpty) return;
    if (_goodBoyAtNight) {
      dawnDeaths.addAll(taken);
      _finishNight();
    } else {
      dayDeaths.addAll(taken);
      phase = Phase.dayEnd;
      notifyListeners();
    }
  }

  // ----- day -----
  Player? get mayor => game.alive.where((p) => p.role == Role.mayor).firstOrNull;
  bool get canRevealMayor => mayor != null && !mayor!.mayorRevealed;

  void revealMayor() {
    final m = mayor;
    if (m == null) return;
    m.mayorRevealed = true;
    notifyListeners();
  }

  void startDiscussion() {
    if (phase != Phase.dawn) return;
    // The silenced player does not speak in today's discussion (still votes).
    speakers = game.alive.where((p) => !identical(p, silenced)).toList();
    speakerIdx = 0;
    revoted = false;
    phase = Phase.discuss;
    notifyListeners();
  }

  void nextSpeaker() {
    if (phase != Phase.discuss) return;
    speakerIdx++;
    if (speakerIdx >= speakers.length) {
      startVote();
    } else {
      notifyListeners();
    }
  }

  void startVote({List<Player>? only}) {
    voters = game.alive;
    voterIdx = 0;
    votes = {};
    candidates = only ?? game.alive;
    phase = Phase.vote;
    notifyListeners();
  }

  void castVote(Player target) {
    if (phase != Phase.vote) return;
    votes[voters[voterIdx]] = target;
    voterIdx++;
    if (voterIdx >= voters.length) {
      _finishVote();
    } else {
      notifyListeners();
    }
  }

  void _finishVote() {
    final leaders = game.tally(votes);
    tiedLeaders = leaders;
    if (leaders.isEmpty) {
      _finishDay([]);
    } else if (leaders.length == 1) {
      accused = leaders.first;
      phase = Phase.defense;
      notifyListeners();
    } else {
      phase = Phase.tie;
      notifyListeners();
    }
  }

  /// Applies the configured tie rule (no rule is invented: the players choose).
  void resolveTie() {
    if (phase != Phase.tie) return;
    switch (settings.tieRule) {
      case TieRule.none:
        _finishDay([]);
      case TieRule.random:
        accused = tiedLeaders[game.rng.nextInt(tiedLeaders.length)];
        phase = Phase.defense;
        notifyListeners();
      case TieRule.revote:
        if (!revoted) {
          revoted = true;
          startVote(only: tiedLeaders);
        } else {
          _finishDay([]);
        }
    }
  }

  void startVerdict() {
    if (phase != Phase.defense || accused == null) return;
    voters = game.alive.where((p) => p != accused).toList();
    voterIdx = 0;
    yes = 0;
    no = 0;
    phase = Phase.verdict;
    notifyListeners();
  }

  void castVerdict(bool eliminate) {
    if (phase != Phase.verdict) return;
    final v = voters[voterIdx];
    final w = (v.role == Role.mayor && v.mayorRevealed) ? 3 : 1;
    eliminate ? yes += w : no += w;
    voterIdx++;
    if (voterIdx >= voters.length) {
      final a = accused;
      _finishDay(yes > no && a != null ? game.eliminateByVote(a) : []);
    } else {
      notifyListeners();
    }
  }

  void _finishDay(List<Player> deaths) {
    dayDeaths = List.of(deaths);
    if (game.pendingGoodBoy != null) {
      _goodBoyAtNight = false;
      phase = Phase.goodBoy;
    } else {
      phase = Phase.dayEnd;
    }
    notifyListeners();
  }

  void continueAfterDay() {
    if (phase != Phase.dayEnd) return;
    result = game.checkVictory();
    accused = null;
    if (result != null) {
      phase = Phase.ended;
      notifyListeners();
    } else {
      round++;
      _startNight();
    }
  }

  void saveResult() {
    final r = result;
    if (_saved || r == null) return;
    _saved = true;
    settings.addHistory(HistoryEntry(DateTime.now(), r.winner, r.score, r.survivors, [
      for (final p in game.players) {'n': p.name, 'r': p.role.name, 'a': p.alive}
    ]));
  }
}
