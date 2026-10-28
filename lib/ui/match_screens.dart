import 'dart:async';
import 'package:flutter/material.dart';
import '../data/settings.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../engine/models.dart';
import '../theme.dart';

class MatchScreen extends StatelessWidget {
  const MatchScreen(this.c, {super.key});
  final MatchController c;

  String get _title => switch (c.phase) {
        Phase.reveal => 'كشف الأدوار',
        Phase.night => 'الليل',
        Phase.goodBoy => 'الولد الصالح',
        Phase.dawn || Phase.discuss || Phase.dayEnd => 'النهار',
        Phase.vote || Phase.tie || Phase.defense || Phase.verdict => 'التصويت',
        Phase.ended => 'النتيجة',
      };

  Widget _body() => switch (c.phase) {
        Phase.reveal => RevealView(c),
        Phase.night => NightView(c),
        Phase.goodBoy => GoodBoyView(c),
        Phase.dawn => DawnView(c),
        Phase.discuss => DiscussView(c),
        Phase.vote => VoteView(c),
        Phase.tie => TieView(c),
        Phase.defense => DefenseView(c),
        Phase.verdict => VerdictView(c),
        Phase.dayEnd => DayEndView(c),
        Phase.ended => EndView(c),
      };

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('إنهاء المباراة؟'),
              content: const Text('سيضيع تقدّم المباراة الحالية.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false), child: const Text('متابعة')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنهاء')),
              ],
            ),
          );
          if (ok == true && context.mounted) Navigator.of(context).pop();
        },
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => GScaffold(
            title: _title,
            child: AnimatedSwitcher(
              // The previous screen disappears instantly (it may hold a secret
              // role or result); only the new screen fades in.
              duration: const Duration(milliseconds: 250),
              reverseDuration: Duration.zero,
              child: KeyedSubtree(key: ValueKey(c.viewKey), child: _body()),
            ),
          ),
        ),
      );
}

Widget _center(List<Widget> children) =>
    Center(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children)));

Widget _icon(IconData i) => Icon(i, size: 72, color: sandy);

// ---------------- Reveal ----------------
class RevealView extends StatefulWidget {
  const RevealView(this.c, {super.key});
  final MatchController c;
  @override
  State<RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends State<RevealView> {
  bool shown = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = c.game.players[c.revealIndex];
    if (!shown) {
      return _center([
        _icon(Icons.phone_android_rounded),
        const SizedBox(height: 16),
        const Text('مرّر الهاتف إلى', style: TextStyle(fontSize: 18, color: cream)),
        Text(p.name, style: const TextStyle(fontSize: 36, color: sandy, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('${c.revealIndex + 1} / ${c.game.players.length}',
            style: const TextStyle(color: cream)),
        const SizedBox(height: 24),
        GButton('أنا ${p.name} وحدي أرى الشاشة — اعرض دوري',
            onPressed: () => setState(() => shown = true)),
      ]);
    }
    final mates = c.game.teammatesOf(p);
    return _center([
      const Text('دورك السري', style: TextStyle(fontSize: 18, color: cream)),
      GCard(
        color: p.isMafia ? rug : grass,
        child: Column(children: [
          Text(p.role.arabic,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, color: sandy, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(roleDesc[p.role]!, textAlign: TextAlign.center),
          if (p.role == Role.sheikh && c.game.canSilence(p)) ...[
            const SizedBox(height: 8),
            Text('وبحسب الإعداد المفعّل تحمل أيضاً قدرة ${Role.silencer.arabic}: ${roleDesc[Role.silencer]}',
                textAlign: TextAlign.center),
          ],
          if (p.isMafia) ...[
            const Divider(height: 24),
            Text(
              mates.isEmpty
                  ? 'أنت الدجگال الوحيد — لا يوجد زملاء.'
                  : 'زملاؤك في الدجگال: ${mates.join('، ')}',
              textAlign: TextAlign.center,
            ),
          ],
        ]),
      ),
      GButton(
        c.revealIndex == c.game.players.length - 1 ? 'حفظت — أخفِ وابدأ الليل' : 'حفظت دوري — أخفِ',
        icon: Icons.visibility_off_rounded,
        onPressed: c.nextReveal,
      ),
    ]);
  }
}

// ---------------- Night ----------------
/// One night stage (Dajjal, Wild al-Santi, Investigator, Sniper). Everybody
/// closes their eyes; only the holder of the called role takes the phone.
/// When the role is dead or absent a camouflage screen is shown instead.
class NightView extends StatefulWidget {
  const NightView(this.c, {super.key});
  final MatchController c;
  @override
  State<NightView> createState() => _NightViewState();
}

class _NightViewState extends State<NightView> {
  bool ready = false;
  Player? picked;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final role = c.stageRole;
    final name = role.arabic;

    if (!c.stageActive) return DecoyStage(c: c, name: name);

    final a = c.stageActor!;
    if (!ready) {
      final isMafia = role == Role.mafia;
      final silence = c.mafiaStepIsSilence;
      return _center([
        _icon(Icons.nightlight_round),
        const SizedBox(height: 16),
        const Text('الليل — أغمضوا أعينكم جميعاً',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: cream)),
        const SizedBox(height: 8),
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, color: sandy, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          !isMafia
              ? 'يفتح صاحب هذا الدور عينيه ويستلم الهاتف.'
              : silence
                  ? 'يفتح من يملك قدرة التسكيت عينيه ويستلم الهاتف.'
                  : c.nightKillers.length == 1 && c.nightKillers.first.role == Role.sheikh
                      ? 'يفتح شيخ المافيا عينيه ويستلم الهاتف للاغتيال.'
                      : 'يفتح أفراد الدجگال أعينهم، ويستلم كل واحد منهم الهاتف بدوره (${c.mafiaIdx + 1} / ${c.mafiaStepCount}).',
          textAlign: TextAlign.center,
          style: const TextStyle(color: cream),
        ),
        const SizedBox(height: 24),
        GButton(isMafia ? 'أنا من الدجگال — جاهز' : 'أنا $name — جاهز',
            onPressed: () => setState(() => ready = true)),
      ]);
    }

    switch (role) {
      case Role.mafia:
        if (c.mafiaStepIsSilence) {
          return PickerStep(
            title: 'من تُسكت في نقاش النهار؟',
            subtitle: 'لن يتكلم في النقاش القادم، ويصوّت عادة',
            options: c.game.alive.where((p) => p != a).toList(),
            onConfirm: c.submitNight,
          );
        }
        return PickerStep(
          title: 'اختر ضحية الليلة',
          subtitle: 'الخطوة ${c.mafiaIdx + 1} / ${c.mafiaStepCount}',
          options: c.game.alive.where((p) => !p.isMafia).toList(),
          onConfirm: c.submitNight,
        );
      case Role.doctor:
        return PickerStep(
          title: 'من تحمي الليلة؟',
          options: c.game.alive
              .where((p) => c.game.rules.doctorMaySelfProtect || p != a)
              .toList(),
          onConfirm: c.submitNight,
        );
      case Role.investigator:
        final t = picked;
        if (t == null) {
          return PickerStep(
            title: 'من تريد التحقق منه؟',
            options: c.game.alive.where((p) => p != a).toList(),
            onConfirm: (p) => setState(() => picked = p),
          );
        }
        return _center([
          _icon(Icons.search_rounded),
          const SizedBox(height: 16),
          Text(t.name, style: const TextStyle(fontSize: 32, color: sandy)),
          const SizedBox(height: 8),
          Text(c.game.investigate(t) ? 'من الدجگال' : 'من الصالحين',
              style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 24),
          GButton('فهمت — أخفِ',
              icon: Icons.visibility_off_rounded, onPressed: () => c.submitNight(null)),
        ]);
      case Role.sniper:
        return PickerStep(
          title: 'من تقنص؟',
          subtitle: 'طلقة واحدة فقط — يمكنك تجاوزها',
          options: c.game.alive.where((p) => p != a).toList(),
          skipLabel: 'لا أقنص هذه الليلة',
          onConfirm: c.submitNight,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Camouflage stage: looks like a normal stage to anyone listening, shows
/// nothing, and ends by itself after a few seconds.
class DecoyStage extends StatefulWidget {
  const DecoyStage({super.key, required this.c, required this.name});
  final MatchController c;
  final String name;
  @override
  State<DecoyStage> createState() => _DecoyStageState();
}

class _DecoyStageState extends State<DecoyStage> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final seconds = 6 + widget.c.game.rng.nextInt(5);
    _t = Timer(Duration(seconds: seconds), () {
      if (mounted) widget.c.submitNight(null);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _center([
        _icon(Icons.nightlight_round),
        const SizedBox(height: 16),
        const Text('الليل — أغمضوا أعينكم جميعاً',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: cream)),
        const SizedBox(height: 8),
        Text(widget.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, color: sandy, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('يفتح صاحب هذا الدور عينيه ويستلم الهاتف.',
            textAlign: TextAlign.center, style: TextStyle(color: cream)),
      ]);
}

// ---------------- Good Boy ----------------
/// The eliminated Good Boy chooses a living player who dies with him.
class GoodBoyView extends StatefulWidget {
  const GoodBoyView(this.c, {super.key});
  final MatchController c;
  @override
  State<GoodBoyView> createState() => _GoodBoyViewState();
}

class _GoodBoyViewState extends State<GoodBoyView> {
  bool ready = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final gb = c.goodBoyPlayer;
    if (gb == null) return const SizedBox.shrink();
    if (!ready) {
      return _center([
        _icon(Icons.star_rounded),
        const SizedBox(height: 16),
        const Text('الولد الصالح — مرّر الهاتف إلى',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: cream)),
        Text(gb.name,
            style: const TextStyle(fontSize: 36, color: sandy, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        GButton('أنا ${gb.name}', onPressed: () => setState(() => ready = true)),
      ]);
    }
    return PickerStep(
      title: 'اختر لاعباً يموت معك',
      subtitle: 'لك اختيار واحد فقط',
      options: c.game.alive,
      confirmLabel: 'تأكيد الاختيار',
      onConfirm: (p) => c.goodBoyPick(p!),
    );
  }
}

// ---------------- Day ----------------
String _names(List<Player> l) => l.map((p) => p.name).join('، ');

class DawnView extends StatelessWidget {
  const DawnView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) => _center([
        _icon(Icons.wb_sunny_rounded),
        const SizedBox(height: 12),
        const Text('طلع النهار', style: titleStyle),
        const SizedBox(height: 12),
        Text(
          c.dawnDeaths.isEmpty
              ? 'مرّت الليلة بسلام — لم يخسر أحد.'
              : 'خسرنا الليلة: ${_names(c.dawnDeaths)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 12),
        if (c.silenced != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('أُسكت في نقاش اليوم: ${c.silenced!.name}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: sandy)),
          ),
        Text('الأحياء: ${_names(c.game.alive)}',
            textAlign: TextAlign.center, style: const TextStyle(color: cream)),
        const SizedBox(height: 20),
        GButton('ابدأ النقاش', icon: Icons.forum_rounded, onPressed: c.startDiscussion),
      ]);
}

class DiscussView extends StatelessWidget {
  const DiscussView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) {
    final sp = c.speakers[c.speakerIdx];
    final last = c.speakerIdx == c.speakers.length - 1;
    final mayor = c.mayor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('الدور في الحديث', textAlign: TextAlign.center, style: TextStyle(color: cream)),
      Text(sp.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 36, color: sandy, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      // When the 15 s end, the next speaker (or the vote) starts by itself.
      Countdown(
          key: ValueKey('sp${c.speakerIdx}'),
          seconds: settings.speakSeconds,
          onDone: c.nextSpeaker),
      const SizedBox(height: 12),
      if (mayor != null && mayor.mayorRevealed)
        GCard(child: Text('العمدة: ${mayor.name} — صوته بثلاثة', textAlign: TextAlign.center)),
      if (c.canRevealMayor)
        GButton('العمدة يكشف هويته', primary: false, icon: Icons.badge_rounded, onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('كشف العمدة'),
              content: const Text('يضغط العمدة فقط. هل أنت العمدة وتريد كشف هويتك؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم')),
              ],
            ),
          );
          if (ok == true) c.revealMayor();
        }),
      const Spacer(),
      const GCard(
        child: Text(
          'تذكير: لا حلف بالله، لا أحاديث جانبية، لا مقاطعة للمتحدث، '
          'ولا تأثير على اللعبة بعد الإقصاء.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cream, fontSize: 13),
        ),
      ),
      GButton(last ? 'بدء التصويت' : 'المتحدث التالي',
          icon: last ? Icons.how_to_vote_rounded : Icons.arrow_back_rounded,
          onPressed: c.nextSpeaker),
    ]);
  }
}

class VoteView extends StatelessWidget {
  const VoteView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) {
    final voter = c.voters[c.voterIdx];
    return PickerStep(
      key: ValueKey('v${c.voterIdx}-${c.revoted}'),
      title: 'صوت ${voter.name}',
      subtitle: 'ممنوع الكلام أثناء التصويت (${c.voterIdx + 1}/${c.voters.length})',
      options: c.candidates.where((p) => p != voter).toList(),
      confirmLabel: 'تأكيد التصويت',
      onConfirm: (p) => c.castVote(p!),
    );
  }
}

class TieView extends StatelessWidget {
  const TieView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) {
    const rules = {
      TieRule.none: 'القاعدة المختارة: لا إقصاء عند التعادل.',
      TieRule.revote: 'القاعدة المختارة: إعادة التصويت بين المتعادلين (مرة واحدة).',
      TieRule.random: 'القاعدة المختارة: اختيار عشوائي بين المتعادلين.',
    };
    return _center([
      _icon(Icons.balance_rounded),
      const SizedBox(height: 12),
      const Text('تعادل!', style: titleStyle),
      const SizedBox(height: 8),
      Text(_names(c.tiedLeaders), style: const TextStyle(fontSize: 22)),
      const SizedBox(height: 8),
      Text(rules[c.settings.tieRule]!, textAlign: TextAlign.center, style: const TextStyle(color: cream)),
      const SizedBox(height: 20),
      GButton('متابعة', onPressed: c.resolveTie),
    ]);
  }
}

class DefenseView extends StatelessWidget {
  const DefenseView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('أعلى الأصوات — وقت الدفاع',
              textAlign: TextAlign.center, style: TextStyle(color: cream)),
          Text(c.accused!.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, color: sandy, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // When the defense minute ends, the elimination vote starts by itself.
          Countdown(seconds: settings.defenseSeconds, onDone: c.startVerdict),
          const Spacer(),
          GButton('انتهى الدفاع — التصويت على الإقصاء',
              icon: Icons.how_to_vote_rounded, onPressed: c.startVerdict),
        ],
      );
}

class VerdictView extends StatelessWidget {
  const VerdictView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) {
    final voter = c.voters[c.voterIdx];
    return _center([
      Text('هل يُقصى ${c.accused!.name}؟', textAlign: TextAlign.center, style: titleStyle),
      const SizedBox(height: 8),
      Text('صوت ${voter.name} (${c.voterIdx + 1}/${c.voters.length}) — ممنوع الكلام',
          textAlign: TextAlign.center, style: const TextStyle(color: cream)),
      const SizedBox(height: 24),
      GButton('إقصاء', icon: Icons.close_rounded, onPressed: () => c.castVerdict(true)),
      GButton('إبقاء', primary: false, icon: Icons.check_rounded,
          onPressed: () => c.castVerdict(false)),
    ]);
  }
}

class DayEndView extends StatelessWidget {
  const DayEndView(this.c, {super.key});
  final MatchController c;
  @override
  Widget build(BuildContext context) => _center([
        _icon(Icons.gavel_rounded),
        const SizedBox(height: 12),
        Text(
          c.dayDeaths.isEmpty ? 'لم يُقصَ أحد اليوم.' : 'أُقصي: ${_names(c.dayDeaths)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22),
        ),
        if (c.dayDeaths.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('تُكشف الأدوار في نهاية المباراة', style: TextStyle(color: cream)),
          ),
        const SizedBox(height: 20),
        GButton('متابعة', onPressed: c.continueAfterDay),
      ]);
}

// ---------------- End ----------------
class EndView extends StatefulWidget {
  const EndView(this.c, {super.key});
  final MatchController c;
  @override
  State<EndView> createState() => _EndViewState();
}

class _EndViewState extends State<EndView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.c.saveResult());
  }

  void _again() {
    final names = widget.c.game.players.map((p) => p.name).toList();
    final cfg = buildConfig(names.length, settings.enabled, mafia: settings.mafiaManual);
    final err = cfg.validate(names.length);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MatchScreen(MatchController.create(names, cfg, settings))));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final r = c.result!;
    return ListView(children: [
      _icon(Icons.emoji_events_rounded),
      const SizedBox(height: 8),
      Text(r.winner == Faction.mafia ? 'فاز فريق الدجگال' : 'فاز فريق الصالحين',
          textAlign: TextAlign.center, style: titleStyle),
      Text('الناجون: ${r.survivors} — لكل ناجٍ $pointsPerSurvivor نقطة (المجموع ${r.score})',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      for (final p in c.game.players)
        GCard(
          color: p.isMafia ? rug : grass,
          child: Row(children: [
            Icon(p.alive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: p.alive ? sandy : cream.withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Expanded(child: Text(p.name, style: const TextStyle(fontSize: 18))),
            Text(p.role.arabic, style: const TextStyle(color: cream)),
            if (p.alive && p.isMafia == (r.winner == Faction.mafia))
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Text('+$pointsPerSurvivor', style: const TextStyle(color: sandy)),
              ),
          ]),
        ),
      GButton('مباراة جديدة بنفس اللاعبين', icon: Icons.replay_rounded, onPressed: _again),
      GButton('القائمة الرئيسية',
          primary: false,
          icon: Icons.home_rounded,
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
    ]);
  }
}
