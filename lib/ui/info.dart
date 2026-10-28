import 'package:flutter/material.dart';
import '../data/settings.dart';
import '../engine/config.dart';
import '../engine/models.dart';
import '../theme.dart';
import 'home.dart';
import 'setup.dart';

// ---------------- Guide ----------------
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  static const _steps = [
    (Icons.group_add_rounded, 'تجهيز اللاعبين واختيار الأدوار',
        'اختاروا من 5 إلى 12 لاعباً، واكتبوا الأسماء (لا اسم فارغاً ولا مكرراً)، ثم اختاروا الوضع: الأساسي أو الكلاسيكي أو المخصص. التطبيق هو الحكم، فلا حاجة لراوٍ.'),
    (Icons.visibility_rounded, 'كشف الأدوار بشكل سري',
        'يمرَّر الهاتف لاعباً لاعباً. كل لاعب يؤكد أنه هو، ويرى دوره وحده، ثم يخفيه. أفراد الدجگال يرون زملاءهم سراً.'),
    (Icons.nightlight_round, 'مرحلة الليل',
        'يغمض الجميع أعينهم، ثم تُنادى الأدوار بالترتيب: الدجگال، ثم ولد الصنتي، ثم المحقق، ثم القناص الصالح. في فريق الدجگال يغتال شيخ المافيا (إن وُجد) وتُسكت مافيا التسكيت لاعباً في نقاش اليوم التالي. صاحب الدور وحده يفتح عينيه ويستلم الهاتف. وإن كان الدور ميتاً أو غير مشارك تظهر شاشة تمويه لا تكشف شيئاً.'),
    (Icons.wb_sunny_rounded, 'مرحلة النهار والنقاش',
        'يعلن التطبيق من خسرناه الليلة. يتحدث كل لاعب حي 15 ثانية بالدور. لا حلف بالله ولا أحاديث جانبية ولا مقاطعة.'),
    (Icons.how_to_vote_rounded, 'التصويت والدفاع والإقصاء',
        'يصوّت الجميع بصمت، واحداً بعد الآخر. صاحب أعلى الأصوات يدافع عن نفسه دقيقة، ثم يقرر الباقون إقصاءه أو إبقاءه. التعادل يُحسم بالقاعدة المختارة في الإعدادات.'),
    (Icons.emoji_events_rounded, 'الفوز واحتساب النقاط',
        'الصالحون يفوزون بإقصاء كل الدجگال. الدجگال يفوزون حين يتساوى عددهم مع عدد الفريق الآخر الحي أو يزيد. كل لاعب حي في الفريق الفائز يحصل على 70 نقطة.'),
  ];

  final pc = PageController();
  int page = 0;
  int get _total => _steps.length + 1;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  void _go(int d) => pc.animateToPage(page + d,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  Widget _stepPage(int i) {
    final s = _steps[i];
    return Center(
      child: SingleChildScrollView(
        child: Column(children: [
          Icon(s.$1, size: 80, color: sandy),
          const SizedBox(height: 16),
          Text('الخطوة ${i + 1}', style: const TextStyle(color: cream)),
          const SizedBox(height: 6),
          Text(s.$2, textAlign: TextAlign.center, style: titleStyle),
          const SizedBox(height: 16),
          Text(s.$3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.6)),
        ]),
      ),
    );
  }

  Widget _rolesPage() => ListView(children: [
        const Text('الأدوار', textAlign: TextAlign.center, style: titleStyle),
        const SizedBox(height: 10),
        for (final r in Role.values)
          GCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.arabic} — ${factionName(r.faction)}',
                  style: const TextStyle(color: sandy, fontSize: 16)),
              const SizedBox(height: 4),
              Text(roleDesc[r]!),
            ]),
          ),
      ]);

  @override
  Widget build(BuildContext context) => GScaffold(
        title: 'كيف تلعب غزي؟',
        child: Column(children: [
          LinearProgressIndicator(
            value: (page + 1) / _total,
            color: sandy,
            backgroundColor: earth,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView(
              controller: pc,
              onPageChanged: (i) => setState(() => page = i),
              children: [for (var i = 0; i < _steps.length; i++) _stepPage(i), _rolesPage()],
            ),
          ),
          Row(children: [
            Expanded(child: GButton('السابق', primary: false, onPressed: page > 0 ? () => _go(-1) : null)),
            const SizedBox(width: 10),
            Expanded(
              child: page < _total - 1
                  ? GButton('التالي', onPressed: () => _go(1))
                  : GButton('ابدأ اللعب',
                      onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const SetupScreen()))),
            ),
          ]),
        ]),
      );
}

// ---------------- Settings ----------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => GScaffold(
        title: 'الإعدادات',
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(children: [
            SwitchListTile(
              title: const Text('المؤثرات الصوتية'),
              value: settings.sound,
              onChanged: (v) => settings.change(() => settings.sound = v),
            ),
            SwitchListTile(
              title: const Text('الاهتزاز'),
              value: settings.vibration,
              onChanged: (v) => settings.change(() => settings.vibration = v),
            ),
            SwitchListTile(
              title: const Text('عرض المقدمة عند فتح اللعبة'),
              value: settings.introEnabled,
              onChanged: (v) => settings.change(() => settings.introEnabled = v),
            ),
            SwitchListTile(
              title: const Text('يحق لولد الصنتي حماية نفسه'),
              value: settings.doctorSelf,
              onChanged: (v) => settings.change(() => settings.doctorSelf = v),
            ),
            CounterRow(
              label: 'وقت كلام اللاعب (الأصل $defaultSpeakSeconds)',
              value: settings.speakSeconds,
              min: 5,
              max: 120,
              step: 5,
              suffix: ' ث',
              onChanged: (v) => settings.change(() => settings.speakSeconds = v),
            ),
            CounterRow(
              label: 'وقت الدفاع (الأصل $defaultDefenseSeconds)',
              value: settings.defenseSeconds,
              min: 15,
              max: 180,
              step: 15,
              suffix: ' ث',
              onChanged: (v) => settings.change(() => settings.defenseSeconds = v),
            ),
            const SizedBox(height: 8),
            const Text('عند تعادل الأصوات'),
            const SizedBox(height: 6),
            SegmentedButton<TieRule>(
              segments: const [
                ButtonSegment(value: TieRule.none, label: Text('لا إقصاء')),
                ButtonSegment(value: TieRule.revote, label: Text('إعادة التصويت')),
                ButtonSegment(value: TieRule.random, label: Text('عشوائي')),
              ],
              selected: {settings.tieRule},
              onSelectionChanged: (s) => settings.change(() => settings.tieRule = s.first),
            ),
            const SizedBox(height: 12),
            const Text('حجم الخط'),
            const SizedBox(height: 6),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 0.9, label: Text('صغير')),
                ButtonSegment(value: 1.0, label: Text('عادي')),
                ButtonSegment(value: 1.2, label: Text('كبير')),
              ],
              selected: {settings.textScale},
              onSelectionChanged: (s) => settings.change(() => settings.textScale = s.first),
            ),
            GButton('إعادة عرض المقدمة',
                primary: false,
                icon: Icons.replay_rounded,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const IntroScreen(replay: true)))),
            GButton('قواعد اللعبة',
                primary: false,
                icon: Icons.help_outline_rounded,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const GuideScreen()))),
            GButton('حول غزي',
                primary: false,
                icon: Icons.info_outline_rounded,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
            GButton('إعادة ضبط الإعدادات',
                primary: false, icon: Icons.restart_alt_rounded, onPressed: settings.resetSettings),
          ]),
        ),
      );
}

// ---------------- About ----------------
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => GScaffold(
        title: 'حول اللعبة',
        child: ListView(children: [
          Image.asset('assets/ghazi.png', height: 220, cacheHeight: 660),
          const SizedBox(height: 12),
          const Center(child: Text('غزي — GHAZI', style: titleStyle)),
          const SizedBox(height: 6),
          const Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('@_eyu8', style: TextStyle(fontSize: 28, color: sandy, letterSpacing: 2)),
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('الإصدار 0.3.0', style: TextStyle(color: cream))),
          const SizedBox(height: 8),
          const GCard(
            child: Text(
              'لعبة جماعية بهاتف واحد، بلا راوٍ: التطبيق يدير الأدوار والليل والنهار والتصويت والفوز.',
              textAlign: TextAlign.center,
            ),
          ),
          const HeritagePhoto(),
        ]),
      );
}

/// The gathering photo (original, unmodified file) used as the heritage
/// section of the identity.
class HeritagePhoto extends StatelessWidget {
  const HeritagePhoto({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1.6,
            child: Image.asset(
              'assets/originals/photo_gathering_original.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              cacheWidth: 1000,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text('التراث والتواصل', style: TextStyle(color: cream)),
      ]);
}

// ---------------- History ----------------
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) => GScaffold(
        title: 'سجل المباريات',
        actions: [
          IconButton(
            tooltip: 'مسح السجل',
            icon: const Icon(Icons.delete_outline_rounded, color: sandy),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('مسح السجل؟'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                  TextButton(
                      onPressed: () {
                        settings.clearHistory();
                        Navigator.pop(ctx);
                      },
                      child: const Text('مسح')),
                ],
              ),
            ),
          ),
        ],
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            if (settings.history.isEmpty) {
              return const Center(child: Text('لا توجد مباريات بعد'));
            }
            return ListView(children: [
              for (final h in settings.history)
                GCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${h.time.year}-${_two(h.time.month)}-${_two(h.time.day)} '
                      '${_two(h.time.hour)}:${_two(h.time.minute)}',
                      style: const TextStyle(color: cream),
                    ),
                    Text('فاز ${factionName(h.winner)} — ${h.score} نقطة — الناجون ${h.survivors}',
                        style: const TextStyle(color: sandy, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(h.players
                        .map((p) =>
                            '${p['n']} (${Role.values.byName(p['r'] as String).arabic})${p['a'] == true ? '' : ' ✗'}')
                        .join('، ')),
                  ]),
                ),
            ]);
          },
        ),
      );
}
