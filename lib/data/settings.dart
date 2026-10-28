import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/config.dart';
import '../engine/models.dart';

class HistoryEntry {
  HistoryEntry(this.time, this.winner, this.score, this.survivors, this.players);
  final DateTime time;
  final Faction winner;
  final int score;
  final int survivors;
  final List<Map<String, dynamic>> players; // n, r, a

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'w': winner.name,
        's': score,
        'v': survivors,
        'p': players,
      };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        DateTime.parse(j['t'] as String),
        Faction.values.byName(j['w'] as String),
        j['s'] as int,
        j['v'] as int,
        (j['p'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
}

final settings = AppSettings();

/// Day timers required by the rules: 15 s per speaker, 60 s for the defense.
const defaultSpeakSeconds = 15;
const defaultDefenseSeconds = 60;

/// Storage schema. 1 = legacy presets (simple/classic/special/custom),
/// 2 = current presets (basic/classic/custom).
const _schema = 2;

/// Maps a stored preset name to the current [Preset]; never throws.
Preset presetFromStorage(String? name, int schema) {
  if (name == null) return Preset.basic;
  if (schema < 2) {
    return switch (name) {
      'special' => Preset.classic,
      'custom' => Preset.custom,
      _ => Preset.basic, // legacy 'simple' and 'classic'
    };
  }
  return Preset.values.asNameMap()[name] ?? Preset.basic;
}

class AppSettings extends ChangeNotifier {
  bool sound = true;
  bool vibration = true;
  bool introEnabled = true;
  bool doctorSelf = true;

  /// Allows one Dajjal (the sheikh) to carry the silencer's ability as well.
  bool dualPower = false;
  int speakSeconds = defaultSpeakSeconds;
  int defenseSeconds = defaultDefenseSeconds;
  TieRule tieRule = TieRule.none;
  double textScale = 1.0;
  int playerCount = 6;
  Preset preset = Preset.basic;
  Set<Role> enabled = presetRoles(Preset.basic);
  int? mafiaManual;
  List<String> names = [];
  List<HistoryEntry> history = [];
  SharedPreferences? _p;

  void tap() {
    if (vibration) HapticFeedback.selectionClick();
    if (sound) SystemSound.play(SystemSoundType.click);
  }

  Future<void> load() async {
    final p = _p = await SharedPreferences.getInstance();
    try {
      sound = p.getBool('sound') ?? sound;
      vibration = p.getBool('vibration') ?? vibration;
      introEnabled = p.getBool('intro') ?? introEnabled;
      doctorSelf = p.getBool('doctorSelf') ?? doctorSelf;
      dualPower = p.getBool('dualPower') ?? dualPower;
      // New keys: timers saved by older versions (60 s / 90 s) are ignored.
      speakSeconds = p.getInt('speakSec') ?? speakSeconds;
      defenseSeconds = p.getInt('defenseSec') ?? defenseSeconds;
      textScale = p.getDouble('scale') ?? textScale;
      playerCount = (p.getInt('count') ?? playerCount).clamp(minPlayers, maxPlayers).toInt();
      final tie = p.getString('tie');
      tieRule = TieRule.values.asNameMap()[tie] ?? tieRule;
      final schema = p.getInt('schema') ?? 1;
      preset = presetFromStorage(p.getString('preset'), schema);
      final en = p.getStringList('enabled');
      enabled = preset == Preset.custom && en != null
          ? en.map((n) => Role.values.asNameMap()[n]).whereType<Role>().toSet()
          : presetRoles(preset);
      final m = p.getInt('mafia') ?? -1;
      mafiaManual = m < 0 ? null : m;
      names = p.getStringList('names') ?? names;
      history = (p.getStringList('history') ?? [])
          .map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt stored data: keep defaults.
    }
    notifyListeners();
  }

  void change(VoidCallback f) {
    f();
    notifyListeners();
    _save();
  }

  void _save() {
    final p = _p;
    if (p == null) return;
    p.setBool('sound', sound);
    p.setBool('vibration', vibration);
    p.setBool('intro', introEnabled);
    p.setBool('doctorSelf', doctorSelf);
    p.setBool('dualPower', dualPower);
    p.setInt('schema', _schema);
    p.setInt('speakSec', speakSeconds);
    p.setInt('defenseSec', defenseSeconds);
    p.setDouble('scale', textScale);
    p.setInt('count', playerCount);
    p.setString('tie', tieRule.name);
    p.setString('preset', preset.name);
    p.setStringList('enabled', enabled.map((r) => r.name).toList());
    p.setInt('mafia', mafiaManual ?? -1);
    p.setStringList('names', names);
    p.setStringList('history', history.map((h) => jsonEncode(h.toJson())).toList());
  }

  // Role preferences
  void setPlayerCount(int n) => change(() {
        playerCount = n.clamp(minPlayers, maxPlayers).toInt();
        if (mafiaManual != null && mafiaManual! > maxMafia(playerCount)) {
          mafiaManual = maxMafia(playerCount);
        }
      });
  void applyPreset(Preset p) => change(() {
        preset = p;
        if (p != Preset.custom) enabled = presetRoles(p);
      });
  void toggleRole(Role r, bool on) => change(() {
        on ? enabled.add(r) : enabled.remove(r);
        preset = Preset.custom;
      });
  void setMafiaManual(int? m) => change(() => mafiaManual = m);
  void setDualPower(bool v) => change(() => dualPower = v);
  void setNames(List<String> n) => change(() => names = n);
  void resetRoles() => change(() {
        preset = Preset.basic;
        enabled = presetRoles(Preset.basic);
        mafiaManual = null;
        dualPower = false;
      });

  void resetSettings() => change(() {
        sound = true;
        vibration = true;
        introEnabled = true;
        doctorSelf = true;
        speakSeconds = defaultSpeakSeconds;
        defenseSeconds = defaultDefenseSeconds;
        tieRule = TieRule.none;
        textScale = 1.0;
      });

  void addHistory(HistoryEntry e) => change(() {
        history.insert(0, e);
        if (history.length > 100) history.removeLast();
      });
  void clearHistory() => change(() => history = []);
}
