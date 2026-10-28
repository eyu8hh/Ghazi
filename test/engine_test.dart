import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghazi/engine/config.dart';
import 'package:ghazi/engine/game.dart';
import 'package:ghazi/engine/models.dart';

List<String> names(int n) => [for (var i = 0; i < n; i++) 'P$i'];

Game game(Map<Role, int> c, {int seed = 1}) {
  final n = c.values.fold(0, (a, b) => a + b);
  return Game(assignRoles(names(n), RoleConfig(c), Random(seed)),
      rng: Random(seed));
}

Player of(Game g, Role r) => g.players.firstWhere((p) => p.role == r);

void main() {
  test('display names: Dajjal and Wild al-Santi, internal ids unchanged', () {
    expect(Role.mafia.arabic, 'الدجگال');
    expect(Role.doctor.arabic, 'ولد الصنتي');
    expect(Role.sheikh.arabic, 'شيخ المافيا');
    expect(Role.silencer.arabic, 'مافيا التسكيت');
    expect(Role.sheikh.faction, Faction.mafia);
    expect(Role.silencer.faction, Faction.mafia);
    expect(Role.mafia.name, 'mafia');
    expect(Role.doctor.name, 'doctor');
    expect(Role.investigator.arabic, contains('المحقق'));
    expect(Role.investigator.arabic, contains('الشيخ الصالح'));
    expect(Role.sniper.arabic, 'القناص الصالح');
    expect(Role.mayor.arabic, 'العمدة');
    expect(Role.goodBoy.arabic, 'الولد الصالح');
    expect(Role.kartiya.arabic, 'كارطية');
  });

  test('Dajjal count: 5-7 = 1, 8-11 = 2, 12 = 3', () {
    for (var n = 5; n <= 7; n++) {
      expect(autoMafia(n), 1, reason: 'n=$n');
    }
    for (var n = 8; n <= 11; n++) {
      expect(autoMafia(n), 2, reason: 'n=$n');
    }
    expect(autoMafia(12), 3);
  });

  test('suggested config valid for 5..12', () {
    for (var n = 5; n <= 12; n++) {
      final c = RoleConfig.suggested(n);
      expect(c.total, n);
      expect(c.validate(n), isNull, reason: 'n=$n');
    }
  });

  test('invalid counts and configs rejected', () {
    expect(RoleConfig.suggested(5).validate(4), isNotNull);
    expect(RoleConfig.suggested(5).validate(13), isNotNull);
    expect(RoleConfig({Role.kartiya: 5}).validate(5), isNotNull);
    expect(RoleConfig({Role.mafia: 1, Role.kartiya: 3}).validate(5), isNotNull);
    expect(RoleConfig({Role.mafia: 3, Role.kartiya: 2}).validate(5), isNotNull);
    expect(
        RoleConfig({Role.mafia: 1, Role.goodBoy: 2, Role.kartiya: 3}).validate(6),
        isNotNull);
    expect(
        () => assignRoles(names(5), RoleConfig({Role.kartiya: 5}), Random(1)),
        throwsArgumentError);
  });

  test('name validation trims, collapses spaces, rejects empty and duplicate', () {
    expect(normalizeName('  علي   بن  عمر '), 'علي بن عمر');
    expect(validateNames(['علي', 'سعيد']), isNull);
    expect(validateNames(['علي', '   ']), isNotNull);
    expect(validateNames(['علي', ' علي ']), isNotNull);
    expect(validateNames(['علي  بن', 'علي بن']), isNotNull);
    expect(validateNames(['Ali', 'ali']), isNotNull);
  });

  test('specialists see their teammates and count as Dajjal', () {
    final g = game({Role.sheikh: 1, Role.silencer: 1, Role.kartiya: 5});
    final sh = of(g, Role.sheikh);
    final si = of(g, Role.silencer);
    expect(sh.isMafia, isTrue);
    expect(g.teammatesOf(sh), [si.name]);
    expect(g.teammatesOf(si), [sh.name]);
    expect(g.aliveMafia, 2);
  });

  test('assignment matches config', () {
    final p = assignRoles(names(8), RoleConfig.suggested(8), Random(3));
    expect(p.where((x) => x.isMafia).length, 2);
  });

  test('teammates exclude self; none for single Dajjal', () {
    final g = game({Role.mafia: 2, Role.kartiya: 4});
    final m = g.players.firstWhere((p) => p.isMafia);
    expect(g.teammatesOf(m), hasLength(1));
    expect(g.teammatesOf(m), isNot(contains(m.name)));
    final solo = game({Role.mafia: 1, Role.kartiya: 4});
    expect(solo.teammatesOf(of(solo, Role.mafia)), isEmpty);
    expect(solo.teammatesOf(of(solo, Role.kartiya)), isEmpty);
  });

  test('protection and kill', () {
    final g = game({Role.mafia: 1, Role.doctor: 1, Role.kartiya: 3});
    final t = of(g, Role.kartiya);
    expect(g.resolveNight(mafiaTarget: t, protectedPlayer: t), isEmpty);
    expect(t.alive, isTrue);
    expect(g.resolveNight(mafiaTarget: t), [t]);
    expect(t.alive, isFalse);
    expect(g.resolveNight(mafiaTarget: t), isEmpty);
  });

  test('investigator learns the team only', () {
    final g = game({Role.mafia: 1, Role.investigator: 1, Role.kartiya: 3});
    expect(g.investigate(of(g, Role.mafia)), isTrue);
    expect(g.investigate(of(g, Role.kartiya)), isFalse);
    expect(g.investigate(of(g, Role.investigator)), isFalse);
  });

  test('mayor counts triple only when revealed', () {
    final g = game({Role.mafia: 1, Role.mayor: 1, Role.kartiya: 4});
    final mayor = of(g, Role.mayor);
    final k = g.players.where((p) => p.role == Role.kartiya).toList();
    final votes = {mayor: k[0], k[1]: k[2], k[3]: k[2]};
    expect(g.tally(votes), [k[2]]);
    mayor.mayorRevealed = true;
    expect(g.tally(votes), [k[0]]);
  });

  test('tie returns multiple leaders', () {
    final g = game({Role.mafia: 1, Role.kartiya: 4});
    final k = g.players.where((p) => p.role == Role.kartiya).toList();
    expect(g.tally({k[0]: k[1], k[1]: k[0]}), hasLength(2));
  });

  test('good boy voted out: chooses who dies with him, once only', () {
    final g = game({Role.mafia: 1, Role.goodBoy: 1, Role.kartiya: 6});
    final gb = of(g, Role.goodBoy);
    expect(g.eliminateByVote(gb), [gb]);
    expect(g.pendingGoodBoy, gb);
    final pick = of(g, Role.kartiya);
    expect(g.goodBoyTake(pick), [pick]);
    expect(g.pendingGoodBoy, isNull);
    expect(g.alive, hasLength(6));
    // no second trigger, and nothing to take without a pending Good Boy
    expect(g.goodBoyTake(of(g, Role.mafia)), isEmpty);
  });

  test('good boy killed at night also takes a player', () {
    final g = game({Role.mafia: 1, Role.goodBoy: 1, Role.kartiya: 4});
    final gb = of(g, Role.goodBoy);
    expect(g.resolveNight(mafiaTarget: gb), [gb]);
    expect(g.pendingGoodBoy, gb);
  });

    test('victory and scoring: 70 per living winner', () {
    expect(pointsPerSurvivor, 70);

    final g = game({Role.mafia: 1, Role.kartiya: 4});
    expect(g.checkVictory(), isNull);

    g.eliminateByVote(of(g, Role.mafia));

    final r = g.checkVictory()!;
    expect(r.winner, Faction.good);
    expect(r.survivors, 4);
    expect(r.score, 4 * 70);

    // Valid 5-player game: after eliminating 3 good players,
    // one Dajjal and one good player remain.
    final g2 = game({Role.mafia: 1, Role.kartiya: 4});

    for (var i = 0; i < 3; i++) {
      final target = g2.players.firstWhere(
        (p) => p.role == Role.kartiya && p.alive,
      );
      g2.eliminateByVote(target);
    }

    final r2 = g2.checkVictory()!;
    expect(r2.winner, Faction.mafia);
    expect(r2.survivors, 1);
    expect(r2.score, 70);
  });

  test('sniper hits a Dajjal: target dies, sniper stays alive', () {
    final g = game({Role.mafia: 2, Role.sniper: 1, Role.kartiya: 4});
    final s = of(g, Role.sniper);
    final m = of(g, Role.mafia);
    expect(g.sniperShoot(s, m), [m]);
    expect(m.alive, isFalse);
    expect(s.alive, isTrue);
  });

  test('sniper hits the other team: target and sniper both eliminated', () {
    final g = game({Role.mafia: 1, Role.sniper: 1, Role.kartiya: 3});
    final s = of(g, Role.sniper);
    final k = of(g, Role.kartiya);
    final dead = g.sniperShoot(s, k);
    expect(dead, containsAll([s, k]));
    expect(k.alive, isFalse);
    expect(s.alive, isFalse);
  });

  test('sniper has a single bullet', () {
    final g = game({Role.mafia: 2, Role.sniper: 1, Role.kartiya: 4});
    final s = of(g, Role.sniper);
    final ms = g.players.where((p) => p.isMafia).toList();
    expect(g.sniperShotUsed, isFalse);
    g.sniperShoot(s, ms[0]);
    expect(g.sniperShotUsed, isTrue);
    expect(g.sniperShoot(s, ms[1]), isEmpty);
    expect(ms[1].alive, isTrue);
  });
}
