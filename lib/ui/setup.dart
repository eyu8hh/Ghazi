import 'package:flutter/material.dart';
import '../data/settings.dart';
import '../engine/config.dart';
import '../engine/match.dart';
import '../engine/models.dart';
import '../theme.dart';
import 'info.dart';
import 'match_screens.dart';

String describeConfig(RoleConfig cfg) => [
      for (final r in Role.values)
        if (cfg.count(r) > 0) '${r.arabic} × ${cfg.count(r)}'
    ].join('  •  ');

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final List<TextEditingController> ctrls = [
    for (var i = 0; i < settings.playerCount; i++)
      TextEditingController(text: i < settings.names.length ? settings.names[i] : '')
  ];
  String? error;

  @override
  void dispose() {
    for (final c in ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _setCount(int n) {
    settings.setPlayerCount(n);
    while (ctrls.length < n) {
      ctrls.add(TextEditingController());
    }
    while (ctrls.length > n) {
      ctrls.removeLast().dispose();
    }
    setState(() => error = null);
  }

  RoleConfig get _cfg =>
      buildConfig(settings.playerCount, settings.enabled, mafia: settings.mafiaManual, dual: settings.dualPower);

  void _start() {
    // Names are trimmed and inner whitespace collapsed before validation.
    final names = ctrls.map((c) => normalizeName(c.text)).toList();
    final err = validateNames(names) ?? _cfg.validate(names.length);
    if (err != null) {
      // Invalid setup: show the message, change nothing, do not start.
      setState(() => error = err);
      return;
    }
    settings.setNames(names);
    setState(() => error = null);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MatchScreen(MatchController.create(names, _cfg, settings))));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final cfgError = cfg.validate(settings.playerCount);
    return GScaffold(
      title: 'لعبة جديدة',
      actions: [
        IconButton(
          tooltip: 'كيف تلعب؟',
          icon: const Icon(Icons.help_outline_rounded, color: sandy),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const GuideScreen())),
        ),
      ],
      child: ListView(children: [
        CounterRow(
          label: 'عدد اللاعبين',
          value: settings.playerCount,
          min: minPlayers,
          max: maxPlayers,
          onChanged: _setCount,
        ),
        for (var i = 0; i < ctrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: ctrls[i],
              maxLength: 14,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'اللاعب ${i + 1}',
                filled: true,
                fillColor: earth,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        GCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('توزيع الأدوار', style: TextStyle(color: sandy, fontSize: 16)),
            const SizedBox(height: 6),
            Text(describeConfig(cfg)),
            if (cfgError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(cfgError, style: const TextStyle(color: Color(0xFFFF8A80))),
              ),
          ]),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(error!,
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        GButton('تخصيص الأدوار',
            primary: false,
            icon: Icons.tune_rounded,
            onPressed: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const RolesScreen()));
              if (!mounted) return;
              while (ctrls.length < settings.playerCount) {
                ctrls.add(TextEditingController());
              }
              while (ctrls.length > settings.playerCount) {
                ctrls.removeLast().dispose();
              }
              setState(() => error = null);
            }),
        GButton('ابدأ المباراة', icon: Icons.play_arrow_rounded, onPressed: _start),
      ]),
    );
  }
}

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  static const _presetNames = {
    Preset.basic: 'الأساسي',
    Preset.classic: 'الكلاسيكي',
    Preset.custom: 'المخصص',
  };

  @override
  Widget build(BuildContext context) => GScaffold(
        title: 'الأدوار',
        actions: [
          IconButton(
            tooltip: 'إعادة الضبط',
            icon: const Icon(Icons.restart_alt_rounded, color: sandy),
            onPressed: settings.resetRoles,
          ),
        ],
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final n = settings.playerCount;
            final cfg = buildConfig(n, settings.enabled, mafia: settings.mafiaManual, dual: settings.dualPower);
            final err = cfg.validate(n);
            return ListView(children: [
              Wrap(spacing: 8, children: [
                for (final p in Preset.values)
                  ChoiceChip(
                    label: Text(_presetNames[p]!),
                    selected: settings.preset == p,
                    onSelected: (_) => settings.applyPreset(p),
                  ),
              ]),
              const SizedBox(height: 8),
              CounterRow(
                label: 'عدد اللاعبين',
                value: n,
                min: minPlayers,
                max: maxPlayers,
                onChanged: settings.setPlayerCount,
              ),
              GCard(
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('عدد الدجگال تلقائي'),
                    subtitle: const Text('الدجگال دور أساسي ولا يمكن إلغاؤه'),
                    value: settings.mafiaManual == null,
                    onChanged: (v) => settings.setMafiaManual(v ? null : autoMafia(n)),
                  ),
                  if (settings.mafiaManual != null)
                    CounterRow(
                      label: 'عدد الدجگال',
                      value: settings.mafiaManual!,
                      min: 1,
                      max: maxMafia(n),
                      onChanged: settings.setMafiaManual,
                    ),
                ]),
              ),
              for (final r in [...optionalRoles, ...mafiaSpecialRoles])
                GCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.arabic),
                    subtitle: Text(mafiaSpecialRoles.contains(r)
                        ? '${factionName(r.faction)} — يشارك حين يكون عدد الدجگال اثنين فأكثر. ${roleDesc[r]}'
                        : '${factionName(r.faction)} — ${roleDesc[r]}'),
                    value: settings.enabled.contains(r),
                    onChanged: (v) => settings.toggleRole(r, v),
                  ),
                ),
              GCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('دجگالي واحد يجمع القدرتين'),
                  subtitle: const Text(
                      'يعمل حين يكون شيخ المافيا ومافيا التسكيت مفعّلين معاً وعدد الدجگال اثنين فأكثر: يحمل شيخ المافيا قدرة التسكيت أيضاً، فيُستعمل مكان واحد بدل اثنين. عند التعطيل يكون لكل قدرة لاعب مستقل.'),
                  value: settings.dualPower,
                  onChanged: settings.setDualPower,
                ),
              ),
              GCard(
                color: err == null ? earth : rug,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المجموع ${cfg.total} من $n — الدجگال ${cfg.mafia}',
                      style: const TextStyle(color: sandy)),
                  const SizedBox(height: 6),
                  Text(describeConfig(cfg)),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ]),
              ),
            ]);
          },
        ),
      );
}
