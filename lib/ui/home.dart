import 'package:flutter/material.dart';
import '../theme.dart';
import 'info.dart';
import 'setup.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, this.replay = false});
  final bool replay;
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..forward().whenComplete(_next);

  void _next() {
    if (!mounted) return;
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 700),
      pageBuilder: (_, __, ___) => const MenuScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          // Original landscape photo (file kept unmodified in assets/originals).
          Image.asset('assets/originals/photo_landscape_original.jpg',
              fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 900),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0xE617100B)],
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = Curves.easeOut.transform(_c.value);
                return Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * t,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('غزي',
                          style: TextStyle(
                              fontSize: 96,
                              height: 1.1,
                              color: cream,
                              fontWeight: FontWeight.bold)),
                      const Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text('GHAZI',
                            style: TextStyle(fontSize: 22, letterSpacing: 14, color: cream)),
                      ),
                      const SizedBox(height: 28),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text('@_eyu8',
                            style: TextStyle(
                              fontSize: 34,
                              letterSpacing: 2,
                              color: sandy,
                              shadows: [
                                Shadow(color: sandy.withValues(alpha: 0.6 * t), blurRadius: 24)
                              ],
                            )),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      );
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  static final items = <(String, IconData, Widget Function())>[
    ('لعبة جديدة', Icons.play_arrow_rounded, () => const SetupScreen()),
    ('كيف تلعب غزي؟', Icons.help_outline_rounded, () => const GuideScreen()),
    ('الأدوار', Icons.groups_rounded, () => const RolesScreen()),
    ('سجل المباريات', Icons.history_rounded, () => const HistoryScreen()),
    ('الإعدادات', Icons.settings_rounded, () => const SettingsScreen()),
    ('حول اللعبة', Icons.info_outline_rounded, () => const AboutScreen()),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _MenuHeader(),
              const SizedBox(height: 20),
              for (var i = 0; i < items.length; i++)
                GButton(
                  items[i].$1,
                  icon: items[i].$2,
                  primary: i == 0,
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => items[i].$3())),
                ),
            ],
          ),
        ),
      );
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader();
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1.45,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset('assets/images/cover_wide.jpg', fit: BoxFit.cover, cacheWidth: 900),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x00000000), Color(0xCC17100B)],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: const [
                  Text('غزي',
                      style: TextStyle(
                          fontSize: 64, height: 1.1, color: cream, fontWeight: FontWeight.bold)),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('GHAZI',
                        style: TextStyle(fontSize: 16, letterSpacing: 8, color: cream)),
                  ),
                  SizedBox(height: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('@_eyu8', style: TextStyle(fontSize: 16, color: sandy)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
}
