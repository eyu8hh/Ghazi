import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghazi/data/settings.dart';
import 'package:ghazi/engine/config.dart';
import 'package:ghazi/engine/match.dart';
import 'package:ghazi/engine/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchController mk(Map<Role, int> c, {AppSettings? s, int seed = 1}) {
  final n = c.values.fold(0, (a, b) => a + b);
  return MatchController.create(
      [for (var i = 0; i < n; i++) 'P$i'], RoleConfig(c), s ?? AppSettings(),
      rng: Random(seed));
}


void toNight(MatchController c) {
  for (var i = 0; i < c.game.players.length; i++) {
    c.nextReveal();
  }

  if (c.phase == Phase.returnToFirst) {
    c.beginFirstNight();
  }
}


/// Plays a whole night. Stages without a living participant ignore the
/// argument, exactly like the camouflage screens in the UI.
void playNight(MatchController c,
    {Player? kill, Player? protect, Player? shoot, Player? silence}) {
  while (c.phase == Phase.night) {
    final r = c.stageRole;
    c.submitNight(switch (r) {
      Role.mafia => c.mafiaStepIsSilence ? silence : kill,
      Role.doctor => protect,
      Role.sniper => shoot,
      _ => null,
    });
  }
}

Player good(MatchController c) => c.game.players.firstWhere((p) => !p.isMafia);
Player roleOf(MatchController c, Role r) =>
    c.game.players.firstWhere((p) => p.role == r);

void main() {
  test('three modes only; basic and classic roles', () {
    expect(Preset.values, [Preset.basic, Preset.classic, Preset.custom]);
    expect(presetRoles(Preset.basic), {Role.doctor, Role.investigator});
    expect(presetRoles(Preset.classic), {
      Role.doctor,
      Role.investigator,
      Role.sniper,
      Role.mayor,
      Role.goodBoy,
      Role.sheikh,
      Role.silencer,
    });
    expect(presetRoles(Preset.custom), isEmpty);
  });

  test('buildConfig: modes valid for all counts, no silent role drops', () {
    for (var n = 5; n <= 12; n++) {
      final cfg = buildConfig(n, presetRoles(Preset.basic));
      expect(cfg.validate(n), isNull, reason: 'basic $n');
      expect(cfg.mafia, autoMafia(n));
      expect(cfg.count(Role.sheikh), 0); // specialists are not in the basic mode
    }
    // classic needs 1 Dajjal + 5 extended roles: invalid for 5 players,
    // reported and never silently fixed
    final cfg = buildConfig(5, presetRoles(Preset.classic));
    expect(cfg.validate(5), isNotNull);
    expect(cfg.count(Role.sniper), 1);
    for (var n = 6; n <= 12; n++) {
      expect(buildConfig(n, presetRoles(Preset.classic)).validate(n), isNull,
          reason: 'classic $n');
    }
  });

  test('manual Dajjal count respected and validated', () {
    final c = buildConfig(8, {}, mafia: 3);
    expect(c.mafia, 3);
    expect(c.validate(8), isNull);
    expect(buildConfig(6, {}, mafia: 3).validate(6), isNotNull);
  });

  test('reveal leads to night, which starts with the Dajjal stage', () {
    final c = mk({Role.mafia: 1, Role.doctor: 1, Role.kartiya: 3});
    expect(c.phase, Phase.reveal);
    toNight(c);
    expect(c.phase, Phase.night);
    expect(c.nightIdx, 0);
    expect(c.stageRole, Role.mafia);
    expect(c.stageActive, isTrue);
    expect(c.stageActor!.isMafia, isTrue);
  });

  test('night order is fixed; absent roles get camouflage stages', () {
    expect(nightOrder,
        [Role.mafia, Role.doctor, Role.investigator, Role.sniper]);
    final c = mk({Role.mafia: 1, Role.kartiya: 4}); // no special roles at all
    toNight(c);
    final seen = <Role>[];
    final active = <bool>[];
    while (c.phase == Phase.night) {
      seen.add(c.stageRole);
      active.add(c.stageActive);
      c.submitNight(c.stageRole == Role.mafia ? good(c) : null);
    }
    expect(seen, nightOrder);
    expect(active, [true, false, false, false]);
    expect(c.phase, Phase.dawn);
    expect(c.dawnDeaths, hasLength(1));
  });

  test('night kill, protection, and dawn', () {
    var c = mk({Role.mafia: 1, Role.doctor: 1, Role.kartiya: 3});
    toNight(c);
    final t = roleOf(c, Role.kartiya);
    playNight(c, kill: t);
    expect(c.phase, Phase.dawn);
    expect(c.dawnDeaths, [t]);

    c = mk({Role.mafia: 1, Role.doctor: 1, Role.kartiya: 3});
    toNight(c);
    final t2 = roleOf(c, Role.kartiya);
    playNight(c, kill: t2, protect: t2);
    expect(c.dawnDeaths, isEmpty);
    expect(t2.alive, isTrue);
  });

  test('two Dajjal with different picks still kill exactly one', () {
    final c = mk({Role.mafia: 2, Role.kartiya: 4});
    toNight(c);
    final ks = c.game.players.where((p) => !p.isMafia).toList();
    var i = 0;
    while (c.phase == Phase.night) {
      c.submitNight(c.stageRole == Role.mafia ? ks[i++ % 2] : null);
    }
    expect(i, 2); // each Dajjal voted once
    expect(c.dawnDeaths, hasLength(1));
  });

  test('sniper shot at night: hit on Dajjal keeps the sniper alive', () {
    final c = mk({Role.mafia: 2, Role.sniper: 1, Role.kartiya: 4});
    toNight(c);
    final m = roleOf(c, Role.mafia);
    final s = roleOf(c, Role.sniper);
    playNight(c, shoot: m);
    expect(c.phase, Phase.dawn);
    expect(c.dawnDeaths, [m]);
    expect(s.alive, isTrue);
    expect(c.game.sniperShotUsed, isTrue);

    // next night the sniper stage is a camouflage screen
    c.phase = Phase.dayEnd;
    c.continueAfterDay();
    expect(c.phase, Phase.night);
    while (c.stageRole != Role.sniper) {
      c.submitNight(null);
    }
    expect(c.stageActive, isFalse);
  });

  test('sniper may skip and keeps the bullet; wrong target costs the sniper', () {
    final c = mk({Role.mafia: 1, Role.sniper: 1, Role.kartiya: 4});
    toNight(c);
    final s = roleOf(c, Role.sniper);
    playNight(c); // everybody skips
    expect(c.dawnDeaths, isEmpty);
    expect(c.game.sniperShotUsed, isFalse);

    c.phase = Phase.dayEnd;
    c.continueAfterDay();
    final k = roleOf(c, Role.kartiya);
    playNight(c, shoot: k);
    expect(c.dawnDeaths, containsAll([k, s]));
    expect(s.alive, isFalse);
  });

  test('Good Boy killed at night picks a player, announced at dawn', () {
    final c = mk({Role.mafia: 1, Role.goodBoy: 1, Role.kartiya: 4});
    toNight(c);
    final gb = roleOf(c, Role.goodBoy);
    playNight(c, kill: gb);
    expect(c.phase, Phase.goodBoy);
    expect(c.goodBoyPlayer, gb);
    final k = roleOf(c, Role.kartiya);
    c.goodBoyPick(k);
    expect(c.phase, Phase.dawn);
    expect(c.dawnDeaths, containsAll([gb, k]));
    expect(k.alive, isFalse);
  });

  test('Good Boy voted out picks a player before the day ends', () {
    final c = mk({Role.mafia: 1, Role.goodBoy: 1, Role.kartiya: 5});
    final gb = roleOf(c, Role.goodBoy);
    c.accused = gb;
    c.phase = Phase.defense;
    c.startVerdict();
    while (c.phase == Phase.verdict) {
      c.castVerdict(true);
    }
    expect(c.phase, Phase.goodBoy);
    final k = roleOf(c, Role.kartiya);
    c.goodBoyPick(k);
    expect(c.phase, Phase.dayEnd);
    expect(c.dayDeaths, containsAll([gb, k]));
    expect(c.game.alive, hasLength(5));
  });

  test('full day: vote out the Dajjal and the good team wins, 70 per survivor', () {
    final c = mk({Role.mafia: 1, Role.kartiya: 4});
    toNight(c);
    playNight(c, kill: good(c));
    expect(c.phase, Phase.dawn);
    c.startDiscussion();
    while (c.phase == Phase.discuss) {
      c.nextSpeaker();
    }
    expect(c.phase, Phase.vote);
    final mafia = c.game.players.firstWhere((p) => p.isMafia);
    while (c.phase == Phase.vote) {
      final v = c.voters[c.voterIdx];
      c.castVote(v == mafia ? c.game.alive.firstWhere((p) => p != mafia) : mafia);
    }
    expect(c.phase, Phase.defense);
    expect(c.accused, mafia);
    c.startVerdict();
    while (c.phase == Phase.verdict) {
      c.castVerdict(true);
    }
    expect(c.phase, Phase.dayEnd);
    c.continueAfterDay();
    expect(c.phase, Phase.ended);
    expect(c.result!.winner, Faction.good);
    expect(c.result!.survivors, 3);
    expect(c.result!.score, 3 * 70);
  });

  test('Dajjal win when they equal the living rest', () {
    final c = mk({Role.mafia: 1, Role.kartiya: 4});
    toNight(c);
    Player victim() => c.game.alive.firstWhere((p) => !p.isMafia);
    for (var i = 0; i < 2; i++) {
      playNight(c, kill: victim()); // 1 Dajjal vs 3, then 1 vs 2: continues
      expect(c.phase, Phase.dawn);
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
    }
    playNight(c, kill: victim()); // 1 vs 1: the Dajjal win
    expect(c.phase, Phase.ended);
    expect(c.result!.winner, Faction.mafia);
    expect(c.result!.survivors, 1);
    expect(c.result!.score, 70);
  });

  group('overlapping night abilities', () {
    test('sniper and Dajjal pick the same player: dies once, shot not fired', () {
      final c = mk({Role.mafia: 2, Role.sniper: 1, Role.kartiya: 4});
      toNight(c);
      final v = roleOf(c, Role.kartiya);
      final s = roleOf(c, Role.sniper);
      playNight(c, kill: v, shoot: v);
      expect(c.dawnDeaths, [v]); // listed once
      expect(s.alive, isTrue); // target was already dead: no shot, no penalty
      expect(c.game.sniperShotUsed, isFalse); // the bullet is kept
    });

    test('protected player still dies to the sniper (and costs the sniper)', () {
      final c = mk({Role.mafia: 2, Role.doctor: 1, Role.sniper: 1, Role.kartiya: 3});
      toNight(c);
      final v = roleOf(c, Role.kartiya);
      final s = roleOf(c, Role.sniper);
      playNight(c, kill: v, protect: v, shoot: v);
      expect(v.alive, isFalse);
      expect(s.alive, isFalse);
      expect(c.dawnDeaths, containsAll([v, s]));
    });

    test('sniper killed by the Dajjal the same night does not shoot', () {
      final c = mk({Role.mafia: 2, Role.sniper: 1, Role.kartiya: 4});
      toNight(c);
      final s = roleOf(c, Role.sniper);
      final m = roleOf(c, Role.mafia);
      playNight(c, kill: s, shoot: m);
      expect(c.dawnDeaths, [s]);
      expect(m.alive, isTrue);
      expect(c.game.sniperShotUsed, isFalse);
    });

    test('night can end the match: sniper kills the last Dajjal', () {
      final c = mk({Role.mafia: 1, Role.sniper: 1, Role.kartiya: 4});
      toNight(c);
      final m = roleOf(c, Role.mafia);
      final v = roleOf(c, Role.kartiya);
      playNight(c, kill: v, shoot: m); // victim still counted, then check
      expect(c.phase, Phase.ended);
      expect(c.result!.winner, Faction.good);
      expect(c.result!.survivors, 4); // 5 good - 1 victim
      expect(c.result!.score, 4 * 70);
    });

    test('night can end the match: wrong shot hands the Dajjal the win', () {
      final c = mk({Role.mafia: 1, Role.sniper: 1, Role.kartiya: 3});
      toNight(c);
      final k = roleOf(c, Role.kartiya);
      playNight(c, shoot: k); // sniper and kartiya die: 1 Dajjal vs 2 good
      expect(c.phase, Phase.dawn);
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
      playNight(c, kill: c.game.alive.firstWhere((p) => !p.isMafia));
      expect(c.phase, Phase.ended); // 1 vs 1
      expect(c.result!.winner, Faction.mafia);
    });

    test('Good Boy chosen victim can be the last Dajjal: good team wins', () {
      final c = mk({Role.mafia: 1, Role.goodBoy: 1, Role.kartiya: 4});
      toNight(c);
      final gb = roleOf(c, Role.goodBoy);
      final m = roleOf(c, Role.mafia);
      playNight(c, kill: gb);
      expect(c.phase, Phase.goodBoy); // match not decided before the pick
      c.goodBoyPick(m);
      expect(c.phase, Phase.ended);
      expect(c.result!.winner, Faction.good);
    });

    test('Good Boy killed by the sniper takes a player too', () {
      final c = mk({Role.mafia: 2, Role.sniper: 1, Role.goodBoy: 1, Role.kartiya: 3});
      toNight(c);
      final gb = roleOf(c, Role.goodBoy);
      final s = roleOf(c, Role.sniper);
      playNight(c, shoot: gb);
      expect(c.phase, Phase.goodBoy);
      expect(s.alive, isFalse); // wrong target: sniper eliminated as well
      final k = roleOf(c, Role.kartiya);
      c.goodBoyPick(k);
      expect(c.dawnDeaths, containsAll([gb, s, k]));
    });

    test('doctor cannot protect himself when the setting is off', () {
      final st = AppSettings()..doctorSelf = false;
      final c = mk({Role.mafia: 1, Role.doctor: 1, Role.kartiya: 3}, s: st);
      toNight(c);
      final d = roleOf(c, Role.doctor);
      playNight(c, kill: d, protect: d);
      expect(d.alive, isFalse);
    });
  });

  group('Dajjal specialists: sheikh and silencer', () {
    final classic = presetRoles(Preset.classic);

    test('distribution: they take places inside the Dajjal team', () {
      for (var n = 5; n <= 7; n++) {
        final c = buildConfig(n, classic);
        expect(c.count(Role.sheikh), 0, reason: 'n=$n has a single Dajjal');
        expect(c.count(Role.silencer), 0);
        expect(c.mafia, 1);
      }
      for (var n = 8; n <= 12; n++) {
        final c = buildConfig(n, classic);
        expect(c.count(Role.sheikh), 1, reason: 'n=$n');
        expect(c.count(Role.silencer), 1);
        expect(c.mafia, autoMafia(n)); // team size stays correct
        expect(c.count(Role.mafia), autoMafia(n) - 2); // the rest are plain
        expect(c.validate(n), isNull, reason: 'n=$n');
        expect(c.merged, isFalse);
      }
      final p = assignRoles(
          [for (var i = 0; i < 12; i++) 'P$i'], buildConfig(12, classic), Random(2));
      expect(p.where((x) => x.isMafia), hasLength(3));
      expect(p.where((x) => x.role == Role.sheikh), hasLength(1));
      expect(p.where((x) => x.role == Role.silencer), hasLength(1));
      expect(p.where((x) => x.role == Role.mafia), hasLength(1));
    });

    test('respects enabled roles and the manual Dajjal count', () {
      var c = buildConfig(9, {Role.sheikh});
      expect([c.count(Role.sheikh), c.count(Role.silencer), c.count(Role.mafia)],
          [1, 0, 1]);
      c = buildConfig(8, {Role.silencer});
      expect([c.count(Role.sheikh), c.count(Role.silencer), c.count(Role.mafia)],
          [0, 1, 1]);
      c = buildConfig(8, {}); // custom with nothing enabled: plain Dajjal only
      expect([c.count(Role.sheikh), c.count(Role.silencer), c.count(Role.mafia)],
          [0, 0, 2]);
      c = buildConfig(10, classic, mafia: 1);
      expect(c.count(Role.sheikh), 0); // one Dajjal: no specialists
      c = buildConfig(10, classic, mafia: 3);
      expect(c.mafia, 3);
      expect(c.validate(10), isNull);
      expect(RoleConfig({Role.sheikh: 1, Role.kartiya: 4}).validate(5), isNotNull);
    });

    test('dual option merges both abilities into the sheikh only when enabled', () {
      var c = buildConfig(8, classic, dual: true);
      expect(c.merged, isTrue);
      expect(c.count(Role.sheikh), 1);
      expect(c.count(Role.silencer), 0);
      expect(c.mafia, 2); // team size unchanged
      expect(c.count(Role.mafia), 1);
      expect(c.validate(8), isNull);
      // option on but only one specialist enabled: nothing is merged
      c = buildConfig(8, {Role.sheikh}, dual: true);
      expect(c.merged, isFalse);
      // option off: two separate players
      c = buildConfig(8, classic);
      expect(c.merged, isFalse);
      expect(c.count(Role.silencer), 1);
    });

    test('night flow: only the sheikh chooses the victim, then the silencer', () {
      final c = mk({Role.sheikh: 1, Role.silencer: 1, Role.kartiya: 5});
      toNight(c);
      final sheikh = roleOf(c, Role.sheikh);
      final sil = roleOf(c, Role.silencer);
      final ks = c.game.players.where((p) => p.role == Role.kartiya).toList();
      expect(c.nightKillers, [sheikh]);
      expect(c.nightSilencer, sil);
      expect(c.mafiaStepCount, 2);
      expect(c.stageActor, sheikh);
      expect(c.mafiaStepIsSilence, isFalse);
      c.submitNight(ks[0]); // assassination
      expect(c.stageRole, Role.mafia);
      expect(c.mafiaStepIsSilence, isTrue);
      expect(c.stageActor, sil);
      c.submitNight(ks[1]); // silencing
      expect(c.stageRole, Role.doctor);
      while (c.phase == Phase.night) {
        c.submitNight(null);
      }
      expect(c.phase, Phase.dawn);
      expect(c.dawnDeaths, [ks[0]]);
      expect(c.silenced, ks[1]);
      // the silenced player skips today's discussion but is still alive
      c.startDiscussion();
      expect(c.speakers, isNot(contains(ks[1])));
      expect(c.speakers, hasLength(5));
      expect(ks[1].alive, isTrue);
      // the effect ends with the day
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
      expect(c.silenced, isNull);
    });

    test('sheikh dead: the living Dajjal vote on the victim again', () {
      final c = mk({Role.sheikh: 1, Role.mafia: 1, Role.silencer: 1, Role.kartiya: 5});
      toNight(c);
      playNight(c);
      final sheikh = roleOf(c, Role.sheikh);
      c.game.eliminateByVote(sheikh);
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
      expect(c.phase, Phase.night);
      final plain = roleOf(c, Role.mafia);
      final sil = roleOf(c, Role.silencer);
      expect(c.nightKillers, containsAll([plain, sil]));
      expect(c.nightKillers, hasLength(2));
      expect(c.nightSilencer, sil); // silencing is still available
      final v = roleOf(c, Role.kartiya);
      playNight(c, kill: v);
      expect(c.dawnDeaths, [v]);
    });

    test('silencer dead: no silencing step, sheikh keeps the assassination', () {
      final c = mk({Role.sheikh: 1, Role.silencer: 1, Role.kartiya: 5});
      toNight(c);
      playNight(c);
      c.game.eliminateByVote(roleOf(c, Role.silencer));
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
      expect(c.nightSilencer, isNull); // the ability is not transferred
      expect(c.nightKillers, [roleOf(c, Role.sheikh)]);
      expect(c.mafiaStepCount, 1);
      final v = roleOf(c, Role.kartiya);
      playNight(c, kill: v);
      expect(c.dawnDeaths, [v]);
      expect(c.silenced, isNull);
    });

    test('silencer killed by the sniper the same night: nobody is silenced', () {
      final c =
          mk({Role.sheikh: 1, Role.silencer: 1, Role.sniper: 1, Role.kartiya: 4});
      toNight(c);
      final sil = roleOf(c, Role.silencer);
      final s = roleOf(c, Role.sniper);
      final ks = c.game.players.where((p) => p.role == Role.kartiya).toList();
      playNight(c, kill: ks[0], silence: ks[1], shoot: sil);
      expect(sil.alive, isFalse);
      expect(s.alive, isTrue); // hit a Dajjal: the sniper survives
      expect(c.silenced, isNull);
      expect(c.dawnDeaths, containsAll([ks[0], sil]));
    });

    test('dual power: the sheikh does both steps and only he knows', () {
      final names = [for (var i = 0; i < 8; i++) 'P$i'];
      final st = AppSettings()..dualPower = true;
      final cfg = buildConfig(8, presetRoles(Preset.classic), dual: st.dualPower);
      final c = MatchController.create(names, cfg, st, rng: Random(4));
      expect(c.game.players.where((p) => p.role == Role.silencer), isEmpty);
      final sheikh = roleOf(c, Role.sheikh);
      final plain = roleOf(c, Role.mafia);
      expect(c.game.canSilence(sheikh), isTrue);
      expect(c.game.canSilence(plain), isFalse);
      toNight(c);
      expect(c.nightKillers, [sheikh]);
      expect(c.nightSilencer, sheikh);
      expect(c.mafiaStepCount, 2);
      final ks = c.game.players.where((p) => !p.isMafia).toList();
      c.submitNight(ks[0]);
      expect(c.mafiaStepIsSilence, isTrue);
      expect(c.stageActor, sheikh);
      c.submitNight(ks[1]);
      while (c.phase == Phase.night) {
        c.submitNight(null);
      }
      expect(c.silenced, ks[1]);
      // when the sheikh dies the merged ability is gone
      c.game.eliminateByVote(sheikh);
      c.phase = Phase.dayEnd;
      c.continueAfterDay();
      expect(c.nightSilencer, isNull);
      expect(c.nightKillers, [plain]);
    });

    test('dual option off: abilities stay on two different players', () {
      final names = [for (var i = 0; i < 8; i++) 'P$i'];
      final cfg = buildConfig(8, presetRoles(Preset.classic));
      final c = MatchController.create(names, cfg, AppSettings(), rng: Random(4));
      final sheikh = roleOf(c, Role.sheikh);
      final sil = roleOf(c, Role.silencer);
      expect(sheikh, isNot(sil));
      expect(c.game.canSilence(sheikh), isFalse);
      expect(c.game.canSilence(sil), isTrue);
    });

    test('they count as Dajjal for the win: both must go for the good team', () {
      final c = mk({Role.sheikh: 1, Role.silencer: 1, Role.kartiya: 3});
      toNight(c);
      final ks = c.game.players.where((p) => p.role == Role.kartiya).toList();
      playNight(c, kill: ks[0], silence: ks[1]); // 2 Dajjal vs 2 good
      expect(c.phase, Phase.ended);
      expect(c.result!.winner, Faction.mafia);
      expect(c.result!.survivors, 2);
      expect(c.result!.score, 2 * 70);

      final g = mk({Role.sheikh: 1, Role.silencer: 1, Role.kartiya: 5}).game;
      g.eliminateByVote(g.players.firstWhere((p) => p.role == Role.sheikh));
      expect(g.checkVictory(), isNull);
      g.eliminateByVote(g.players.firstWhere((p) => p.role == Role.silencer));
      expect(g.checkVictory()!.winner, Faction.good);
      expect(g.checkVictory()!.score, 5 * 70);
    });
  });

  test('tie rules: none, revote, random', () {
    List<Player> tieSetup(MatchController c) {
      c.startVote();
      final p = c.game.players;
      for (final t in [p[1], p[3], p[1], p[0], p[3]]) {
        c.castVote(t);
      }
      return p;
    }

    final s = AppSettings();
    var c = mk({Role.mafia: 1, Role.kartiya: 4}, s: s);
    tieSetup(c);
    expect(c.phase, Phase.tie);
    expect(c.tiedLeaders, hasLength(2));
    c.resolveTie();
    expect(c.phase, Phase.dayEnd);
    expect(c.dayDeaths, isEmpty);

    s.tieRule = TieRule.revote;
    c = mk({Role.mafia: 1, Role.kartiya: 4}, s: s);
    tieSetup(c);
    c.resolveTie();
    expect(c.phase, Phase.vote);
    expect(c.candidates, hasLength(2));

    s.tieRule = TieRule.random;
    c = mk({Role.mafia: 1, Role.kartiya: 4}, s: s);
    tieSetup(c);
    c.resolveTie();
    expect(c.phase, Phase.defense);
    expect(c.tiedLeaders, contains(c.accused));
  });

  test('actions are ignored outside their phase', () {
    final c = mk({Role.mafia: 1, Role.kartiya: 4});
    c.submitNight(null); // still in reveal
    c.castVote(good(c));
    c.startVerdict();
    c.goodBoyPick(good(c));
    expect(c.phase, Phase.reveal);
    expect(c.nightIdx, 0);
  });

  test('mayor revealed counts three in the verdict', () {
    final c = mk({Role.mafia: 1, Role.mayor: 1, Role.kartiya: 3});
    final mayor = c.game.players.firstWhere((p) => p.role == Role.mayor);
    mayor.mayorRevealed = true;
    final target = c.game.players.firstWhere((p) => p.role == Role.kartiya);
    c.accused = target;
    c.phase = Phase.defense;
    c.startVerdict();
    while (c.phase == Phase.verdict) {
      final v = c.voters[c.voterIdx];
      c.castVerdict(v == mayor); // only the mayor says "eliminate": 3 vs 3 -> stays
    }
    expect(target.alive, isTrue);
  });

  group('settings', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('day timers default to 15 s (speaker) and 60 s (defense)', () {
      expect(AppSettings().speakSeconds, 15);
      expect(AppSettings().defenseSeconds, 60);
    });

    test('legacy stored values are migrated without losing history', () async {
      SharedPreferences.setMockInitialValues({
        'preset': 'special', // legacy "special" is now the classic mode
        'speak': 60,
        'defense': 90,
        'names': ['علي', 'سعيد'],
        'history': [
          '{"t":"2026-01-01T10:00:00.000","w":"mafia","s":70,"v":1,'
              '"p":[{"n":"علي","r":"mafia","a":true}]}'
        ],
      });
      final s = AppSettings();
      await s.load();
      expect(s.preset, Preset.classic);
      expect(s.enabled, presetRoles(Preset.classic));
      expect(s.speakSeconds, 15);
      expect(s.defenseSeconds, 60);
      expect(s.names, ['علي', 'سعيد']);
      expect(s.history, hasLength(1));
    });

    test('legacy simple/classic become the basic mode; custom is kept', () async {
      SharedPreferences.setMockInitialValues({'preset': 'simple'});
      var s = AppSettings();
      await s.load();
      expect(s.preset, Preset.basic);
      SharedPreferences.setMockInitialValues({'preset': 'classic'});
      s = AppSettings();
      await s.load();
      expect(s.preset, Preset.basic);
      expect(s.enabled, {Role.doctor, Role.investigator});
      SharedPreferences.setMockInitialValues(
          {'preset': 'custom', 'enabled': ['sniper', 'unknownRole']});
      s = AppSettings();
      await s.load();
      expect(s.preset, Preset.custom);
      expect(s.enabled, {Role.sniper});
    });

    test('current schema round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppSettings();
      await s.load();
      s.applyPreset(Preset.classic);
      s.change(() => s.speakSeconds = 20);
      final s2 = AppSettings();
      await s2.load();
      expect(s2.preset, Preset.classic);
      expect(s2.enabled, presetRoles(Preset.classic));
      expect(s2.speakSeconds, 20);
    });
  });

  test('no retired wording left in the app source', () {
    const banned = [
      'المافيا', // team is now «الدجگال» (except «شيخ المافيا», checked below)
      'الطبيب',
      'الإسعاف',
      'الليلة سرّ',
    ];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync().replaceAll('شيخ المافيا', '');
      for (final b in banned) {
        expect(text.contains(b), isFalse, reason: '${f.path} contains $b');
      }
    }
  });
}
