
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/settings.dart';
import 'config.dart';
import 'game.dart';
import 'models.dart';

enum NightAction {
  mafiaKill,
  silence,
  doctor,
  investigator,
  sniper,
  decoy,
}

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
  ended,
}

const nightOrder = [
  Role.mafia,
  Role.doctor,
  Role.investigator,
  Role.sniper,
];

class MatchController extends ChangeNotifier {
  MatchController(this.game, this.settings);

  static MatchController create(
    List<String> names,
    RoleConfig cfg,
    AppSettings s, {
    Random? rng,
  }) {
    final r = rng ?? Random();
    final players = assignRoles(names, cfg, r);

    return MatchController(
      Game(
        players,
        rng: r,
        rules: GameRules(
          doctorMaySelfProtect: s.doctorSelf,
          dualMafiaPower: cfg.merged,
        ),
      ),
      s,
    );
  }

  final Game game;
  final AppSettings settings;

  Phase phase = Phase.reveal;
  int revealIndex = 0;
  int round = 1;

  // ترتيب مرور الهاتف على اللاعبين الأحياء.
  List<Player> nightPlayers = [];
  int nightPlayerIdx = 0;

  // إجراءات اللاعب الذي يحمل الهاتف حاليًا.
  List<NightAction> playerNightActions = [];
  int playerNightActionIdx = 0;

  NightAction get currentNightAction =>
      playerNightActions.isEmpty ||
              playerNightActionIdx >= playerNightActions.length
          ? NightAction.decoy
          : playerNightActions[playerNightActionIdx];

  Player? get currentNightPlayer =>
      nightPlayerIdx >= 0 && nightPlayerIdx < nightPlayers.length
          ? nightPlayers[nightPlayerIdx]
          : null;

  // متغيرات المحافظة على إجراءات المافيا الحالية.
  int nightIdx = 0;
  List<Player> nightKillers = [];
  Player? nightSilencer;
  int mafiaIdx = 0;

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
      '$phase-$round-$revealIndex-$nightIdx-$mafiaIdx-'
      '$nightPlayerIdx-$playerNightActionIdx-'
      '$speakerIdx-$voterIdx-$revoted';

  // ----- reveal -----

  void nextReveal() {
    if (phase != Phase.reveal) return;

    revealIndex++;

    if (revealIndex >= game.players.length) {
      phase = Phase.returnToFirst;
    }

    notifyListeners();
  }

  void beginFirstNight() {
    if (phase != Phase.returnToFirst) return;
    _startNight();
  }

  // ----- night -----

  Role get stageRole => switch (currentNightAction) {
        NightAction.mafiaKill || NightAction.silence => Role.mafia,
        NightAction.doctor => Role.doctor,
        NightAction.investigator => Role.investigator,
        NightAction.sniper => Role.sniper,
        NightAction.decoy => Role.kartiya,
      };

  bool get stageActive => currentNightPlayer != null;

  Player? get stageActor => currentNightPlayer;

  int get mafiaStepCount =>
      nightKillers.length + (nightSilencer != null ? 1 : 0);

  bool get mafiaStepIsSilence =>
      currentNightAction == NightAction.silence;

  List<NightAction> _actionsFor(Player player) {
    final actions = <NightAction>[];

    if (nightKillers.contains(player)) {
      actions.add(NightAction.mafiaKill);
    }

    if (identical(nightSilencer, player)) {
      actions.add(NightAction.silence);
    }

    if (player.role == Role.doctor) {
      actions.add(NightAction.doctor);
    }

    if (player.role == Role.investigator) {
      actions.add(NightAction.investigator);
    }

    if (player.role == Role.sniper && !game.sniperShotUsed) {
      actions.add(NightAction.sniper);
    }

    // اللاعب الذي لا يملك إجراءً حقيقيًا يحصل على اختيار تمويهي.
    if (actions.isEmpty) {
      actions.add(NightAction.decoy);
    }

    return actions;
  }

  void _prepareCurrentPlayer() {
    final player = currentNightPlayer;

    playerNightActionIdx = 0;
    playerNightActions =
        player == null ? [] : _actionsFor(player);
  }

  void _startNight() {
    nightKillers = List<Player>.of(game.nightKillers);
    nightSilencer = game.nightSilencer;

    silencedTarget = null;
    silenced = null;

    mafiaIdx = 0;
    mafiaVotes = {};

    protectedPlayer = null;
    sniperTarget = null;

    _nightSniper = game.alive
        .where((p) => p.role == Role.sniper)
        .firstOrNull;

    // كل لاعب حي يأخذ دوره في هذه الليلة.
    nightPlayers = List<Player>.of(game.alive);
    nightPlayerIdx = 0;
    nightIdx = 0;

    _prepareCurrentPlayer();

    phase = Phase.night;
    notifyListeners();
  }

  void submitNight(Player? target) {
    if (phase != Phase.night) return;

    final actor = currentNightPlayer;
    if (actor == null) return;

    final action = currentNightAction;

    switch (action) {
      case NightAction.mafiaKill:
        if (target != null && target.alive) {
          mafiaVotes[target] = (mafiaVotes[target] ?? 0) + 1;
        }
        mafiaIdx++;

      case NightAction.silence:
        if (target != null &&
            target.alive &&
            !identical(target, actor)) {
          silencedTarget = target;
        }
        mafiaIdx++;

      case NightAction.doctor:
        final self = identical(target, actor);
        protectedPlayer =
            (self && !game.rules.doctorMaySelfProtect)
                ? null
                : target;

      case NightAction.investigator:
        // تعرض الواجهة نتيجة التحقيق قبل استدعاء submitNight.

      case NightAction.sniper:
        sniperTarget = target;

      case NightAction.decoy:
        // الاختيار التمويهي لا يؤثر في اللعبة.
        break;
    }

    playerNightActionIdx++;

    // إذا كان اللاعب يملك أكثر من قدرة، يكمل إجراءاته أولًا.
    if (playerNightActionIdx < playerNightActions.length) {
      notifyListeners();
      return;
    }

    // الانتقال إلى اللاعب التالي.
    nightPlayerIdx++;
    nightIdx = nightPlayerIdx;

    if (nightPlayerIdx >= nightPlayers.length) {
      playerNightActions = [];
      playerNightActionIdx = 0;
      _resolveNight();
      return;
    }

    _prepareCurrentPlayer();
    notifyListeners();
  }

  void _resolveNight() {
    Player? victim;

    if (mafiaVotes.isNotEmpty) {
      final top = mafiaVotes.values.reduce(max);

      final tied = mafiaVotes.entries
          .where((e) => e.value == top)
          .map((e) => e.key)
          .toList();

      victim = tied[game.rng.nextInt(tied.length)];
    }

    dawnDeaths = List.of(
      game.resolveNight(
        mafiaTarget: victim,
        protectedPlayer: protectedPlayer,
      ),
    );

    final sn = _nightSniper;
    final target = sniperTarget;

    if (sn != null && sn.alive && target != null && target.alive) {
      dawnDeaths.addAll(game.sniperShoot(sn, target));
    }

    // لا يعمل التسكيت إذا مات صاحبه أو هدفه أثناء الليل.
    final sil = nightSilencer;
    final silenceTarget = silencedTarget;

    silenced = (sil != null &&
            sil.alive &&
            silenceTarget != null &&
            silenceTarget.alive)
        ? silenceTarget
        : null;

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

  Player? get mayor =>
      game.alive.where((p) => p.role == Role.mayor).firstOrNull;

  bool get canRevealMayor => mayor != null && !mayor!.mayorRevealed;

  void revealMayor() {
    final m = mayor;
    if (m == null) return;

    m.mayorRevealed = true;
    notifyListeners();
  }

  void startDiscussion() {
    if (phase != Phase.dawn) return;

    speakers = game.alive
        .where((p) => !identical(p, silenced))
        .toList();

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

    final voter = voters[voterIdx];
    final weight =
        (voter.role == Role.mayor && voter.mayorRevealed) ? 3 : 1;

    if (eliminate) {
      yes += weight;
    } else {
      no += weight;
    }

    voterIdx++;

    if (voterIdx >= voters.length) {
      final player = accused;
      _finishDay(
        yes > no && player != null
            ? game.eliminateByVote(player)
            : [],
      );
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

    settings.addHistory(
      HistoryEntry(
        DateTime.now(),
        r.winner,
        r.score,
        r.survivors,
        [
          for (final p in game.players)
            {'n': p.name, 'r': p.role.name, 'a': p.alive},
        ],
      ),
    );
  }
}
