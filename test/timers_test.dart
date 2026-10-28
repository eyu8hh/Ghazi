import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghazi/data/settings.dart';
import 'package:ghazi/engine/config.dart';
import 'package:ghazi/engine/match.dart';
import 'package:ghazi/engine/models.dart';
import 'package:ghazi/theme.dart';
import 'package:ghazi/ui/match_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchController newMatch() => MatchController.create(
    ['علي', 'سعيد', 'يوسف', 'حمزة', 'أيوب'],
    RoleConfig({Role.mafia: 1, Role.kartiya: 4}),
    settings,
    rng: Random(1));

Future<void> show(WidgetTester t, MatchController c) async {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(theme: ghaziTheme(), home: MatchScreen(c)));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default timers: 15 s speaker, 60 s defense', () {
    expect(settings.speakSeconds, 15);
    expect(settings.defenseSeconds, 60);
  });

  testWidgets('Countdown calls onDone exactly once when it reaches zero',
      (t) async {
    var done = 0;
    await t.pumpWidget(MaterialApp(
        home: Countdown(seconds: 3, onDone: () => done++)));
    await t.pump(const Duration(seconds: 2));
    expect(done, 0);
    await t.pump(const Duration(seconds: 1));
    expect(done, 1);
    await t.pump(const Duration(seconds: 5));
    expect(done, 1);
  });

  testWidgets('speaker timer: 15 s per living player, then the vote starts',
      (t) async {
    final c = newMatch();
    c.phase = Phase.dawn;
    c.startDiscussion();
    await show(t, c);
    expect(c.speakers, hasLength(5));
    for (var i = 0; i < 5; i++) {
      expect(c.phase, Phase.discuss, reason: 'speaker $i');
      expect(c.speakerIdx, i);
      await t.pump(const Duration(seconds: 14));
      expect(c.speakerIdx, i, reason: 'still speaking at 14 s');
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(c.phase, Phase.vote);
  });

  testWidgets('defense timer: one minute, then the elimination vote starts',
      (t) async {
    final c = newMatch();
    c.accused = c.game.players.first;
    c.phase = Phase.defense;
    await show(t, c);
    await t.pump(const Duration(seconds: 59));
    expect(c.phase, Phase.defense);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.phase, Phase.verdict);
  });

  testWidgets('pressing next early cancels the old timer (no double advance)',
      (t) async {
    final c = newMatch();
    c.phase = Phase.dawn;
    c.startDiscussion();
    await show(t, c);
    await t.pump(const Duration(seconds: 5));
    await t.tap(find.text('المتحدث التالي'));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.speakerIdx, 1);
    await t.pump(const Duration(seconds: 10)); // old timer would have fired
    expect(c.speakerIdx, 1);
    await t.pump(const Duration(seconds: 5)); // new timer's 15 s are over
    expect(c.speakerIdx, 2);
  });

  testWidgets('secret role is not shown on the next screen after hiding',
      (t) async {
    final c = newMatch();
    await show(t, c);
    expect(find.text('دورك السري'), findsNothing);
    await t.tap(find.textContaining('وحدي أرى الشاشة'));
    await t.pump();
    expect(find.text('دورك السري'), findsOneWidget);
    await t.tap(find.textContaining('حفظت دوري'));
    // two zero-length frames (far below the 250 ms fade): the old screen,
    // which held the secret role, must already be gone
    await t.pump();
    await t.pump();
    expect(find.text('دورك السري'), findsNothing);
  });
}
