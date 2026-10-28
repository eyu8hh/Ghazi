import 'dart:async';
import 'package:flutter/material.dart';
import 'data/settings.dart';
import 'engine/models.dart';

// Palette taken from the original photos: warm sand, earthy brown, natural
// green, sky blue and the red of the carpet (الزربية).
const night = Color(0xFF17100B); // dark earth background
const earth = Color(0xFF3B2A1D); // earthy brown (cards)
const sandy = Color(0xFFD9B27C); // warm sand (accent / primary)
const rug = Color(0xFF8E3328); // carpet red (Dajjal team, warnings)
const cream = Color(0xFFF1E6D3); // text on dark
const grass = Color(0xFF3F5B2F); // natural green (good team)
const sky = Color(0xFF7FAEDB); // sky blue (info)

const fontFamily = 'Tajawal';

ThemeData ghaziTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: night,
      colorScheme: const ColorScheme.dark(
          primary: sandy, onPrimary: night, secondary: rug, surface: earth),
      appBarTheme: const AppBarTheme(
          backgroundColor: night, foregroundColor: cream, centerTitle: true, elevation: 0),
    );

class GScaffold extends StatelessWidget {
  const GScaffold({super.key, required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: child)),
      );
}

class GButton extends StatelessWidget {
  const GButton(this.label,
      {super.key, required this.onPressed, this.icon, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: FilledButton(
          onPressed: onPressed == null
              ? null
              : () {
                  settings.tap();
                  onPressed!();
                },
          style: FilledButton.styleFrom(
            backgroundColor: primary ? sandy : earth,
            foregroundColor: primary ? night : cream,
            disabledBackgroundColor: earth.withValues(alpha: 0.4),
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ]),
        ),
      );
}


class GCard extends StatelessWidget {
  const GCard({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: color ?? earth,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );
}

const titleStyle = TextStyle(fontSize: 24, color: sandy, fontWeight: FontWeight.bold);

class PickerStep extends StatefulWidget {
  const PickerStep({
    super.key,
    required this.title,
    required this.options,
    required this.onConfirm,
    this.subtitle,
    this.skipLabel,
    this.confirmLabel = 'تأكيد',
  });
  final String title;
  final String? subtitle;
  final List<Player> options;
  final void Function(Player?) onConfirm;
  final String? skipLabel;
  final String confirmLabel;
  @override
  State<PickerStep> createState() => _PickerStepState();
}

class _PickerStepState extends State<PickerStep> {
  Player? sel;

  Widget _chip(Player p) {
    final on = sel == p;
    return GestureDetector(
      onTap: () {
        settings.tap();
        setState(() => sel = p);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: on ? sandy : earth,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? sandy : cream.withValues(alpha: 0.2)),
        ),
        child: Text(p.name,
            style: TextStyle(
                fontSize: 18,
                color: on ? night : cream,
                fontWeight: on ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, textAlign: TextAlign.center, style: titleStyle),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(widget.subtitle!,
                  textAlign: TextAlign.center, style: const TextStyle(color: cream)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [for (final p in widget.options) _chip(p)],
              ),
            ),
          ),
          if (widget.skipLabel != null)
            GButton(widget.skipLabel!, primary: false, onPressed: () => widget.onConfirm(null)),
          GButton(widget.confirmLabel,
              onPressed: sel == null ? null : () => widget.onConfirm(sel)),
        ],
      );
}

class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.seconds, this.onDone});
  final int seconds;
  final VoidCallback? onDone;
  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late int left = widget.seconds;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => left--);
      if (left <= 0) {
        t.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(left > 0 ? '$left' : 'انتهى الوقت',
            style: TextStyle(fontSize: left > 0 ? 72 : 36, color: left > 5 ? cream : sandy)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (left / widget.seconds).clamp(0.0, 1.0),
          color: sandy,
          backgroundColor: earth,
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
        ),
      ]);
}

class CounterRow extends StatelessWidget {
  const CounterRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.suffix = '',
  });
  final String label;
  final int value, min, max, step;
  final String suffix;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        IconButton(
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(
          width: 64,
          child: Text('$value$suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: sandy, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ]);
}

const roleDesc = <Role, String>{
  Role.mafia:
      'يعرفون بعضهم، ويختار كل فرد منهم ضحية كل ليلة. يفوزون حين يتساوى عددهم مع عدد الفريق الآخر الحي أو يزيد.',
  Role.sheikh:
      'صاحب الاغتيال: ما دام حياً فهو وحده من يختار ضحية الدجگال كل ليلة. وإن مات اختار الدجگال الأحياء الضحية بالتصويت.',
  Role.silencer:
      'يُسكت لاعباً في نقاش النهار التالي: لا يتكلم فيه، لكنه يصوّت عادة. لا تنتقل هذه القدرة إلى غيره إن مات.',
  Role.doctor: 'يحمي لاعباً واحداً كل ليلة من هجوم الدجگال.',
  Role.investigator:
      'يتحقق سراً من لاعب كل ليلة، ويعرف هل هو من الدجگال أم من الصالحين، دون أن يعرف دوره الدقيق. (الشيخ الصالح هو الدور نفسه)',
  Role.sniper:
      'يملك طلقة واحدة، يستعملها في الليلة التي يختارها أو يتجاوزها. إصابة أحد الدجگال تقتل الهدف ويبقى القناص حياً؛ وإصابة لاعب من الفريق الآخر تقتله ويُقصى القناص معه.',
  Role.mayor: 'الوحيد المسموح له بكشف هويته علناً، وبعدها يُحسب صوته بثلاثة.',
  Role.goodBoy:
      'إذا أُقصي بالتصويت أو قُتل ليلاً، يختار لاعباً حياً يموت معه، مرة واحدة فقط.',
  Role.kartiya: 'صالح عادي بلا قدرات خاصة: يناقش ويصوّت.',
};

String factionName(Faction f) => f == Faction.mafia ? 'الدجگال' : 'الصالحون';
