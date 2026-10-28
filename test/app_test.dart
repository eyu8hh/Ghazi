import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghazi/data/settings.dart';
import 'package:ghazi/main.dart';
import 'package:ghazi/theme.dart';
import 'package:ghazi/ui/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bigScreen(WidgetTester t) async {
  t.view.physicalSize = const Size(800, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget menuApp() => MaterialApp(
      theme: ghaziTheme(),
      locale: const Locale('ar'),
      home: const MenuScreen(),
    );

const sixNames = ['علي', 'سعيد', 'يوسف', 'حمزة', 'أيوب', 'كمال'];

Future<void> openSetup(WidgetTester t) async {
  await bigScreen(t);
  await settings.load();
  await t.pumpWidget(menuApp());
  await t.tap(find.text('لعبة جديدة'));
  await t.pumpAndSettle();
}

Future<void> fillNames(WidgetTester t, List<String> names) async {
  for (var i = 0; i < names.length; i++) {
    await t.enterText(find.byType(TextField).at(i), names[i]);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('intro shows @_eyu8 (no slogan) then the menu', (t) async {
    await bigScreen(t);
    await settings.load();
    await t.pumpWidget(const GhaziApp());
    expect(find.text('@_eyu8'), findsOneWidget);
    expect(find.text('الليلة سرّ، والنهار حساب'), findsNothing);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('لعبة جديدة'), findsOneWidget);
    expect(find.text('الليلة سرّ، والنهار حساب'), findsNothing);
    // real RTL layout
    final ctx = t.element(find.text('لعبة جديدة'));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });

  final destinations = {
    'لعبة جديدة': 'ابدأ المباراة',
    'كيف تلعب غزي؟': 'تجهيز اللاعبين واختيار الأدوار',
    'الأدوار': 'الكلاسيكي',
    'سجل المباريات': 'لا توجد مباريات بعد',
    'الإعدادات': 'إعادة عرض المقدمة',
    'حول اللعبة': '@_eyu8',
  };
  destinations.forEach((button, marker) {
    testWidgets('menu "$button" navigates', (t) async {
      await bigScreen(t);
      await settings.load();
      await t.pumpWidget(menuApp());
      await t.tap(find.text(button));
      await t.pumpAndSettle();
      expect(find.text(marker), findsWidgets);
    });
  });

  testWidgets('roles screen offers exactly three modes', (t) async {
    await bigScreen(t);
    await settings.load();
    await t.pumpWidget(menuApp());
    await t.tap(find.text('الأدوار'));
    await t.pumpAndSettle();
    expect(find.text('الأساسي'), findsOneWidget);
    expect(find.text('الكلاسيكي'), findsOneWidget);
    expect(find.text('المخصص'), findsOneWidget);
    expect(find.text('أدوار خاصة'), findsNothing);
    expect(find.text('ولد الصنتي'), findsWidgets);
    expect(find.text('شيخ المافيا'), findsWidgets);
    expect(find.text('مافيا التسكيت'), findsWidgets);
    expect(find.text('دجگالي واحد يجمع القدرتين'), findsOneWidget);
  });

  testWidgets('setup rejects empty names', (t) async {
    await openSetup(t);
    await t.tap(find.text('ابدأ المباراة'));
    await t.pumpAndSettle();
    expect(find.text('أدخلوا أسماء جميع اللاعبين'), findsOneWidget);
  });

  testWidgets('setup rejects duplicate names after trimming', (t) async {
    await openSetup(t);
    await fillNames(t, ['علي', 'سعيد', 'يوسف', 'حمزة', 'أيوب', '  علي  ']);
    await t.tap(find.text('ابدأ المباراة'));
    await t.pumpAndSettle();
    expect(find.text('الأسماء يجب ألا تتكرر'), findsOneWidget);
    expect(find.text('كشف الأدوار'), findsNothing);
  });

  testWidgets('role is hidden until the player confirms, then hidden again',
      (t) async {
    await openSetup(t);
    await fillNames(t, sixNames);
    await t.tap(find.text('ابدأ المباراة'));
    await t.pumpAndSettle();

    expect(find.text('علي'), findsOneWidget);
    expect(find.text('دورك السري'), findsNothing);

    await t.tap(find.text('أنا علي وحدي أرى الشاشة — اعرض دوري'));
    await t.pumpAndSettle();
    expect(find.text('دورك السري'), findsOneWidget);

    await t.tap(find.text('حفظت دوري — أخفِ'));
    await t.pumpAndSettle();
    expect(find.text('دورك السري'), findsNothing);
    expect(find.text('سعيد'), findsOneWidget);
  });
}
