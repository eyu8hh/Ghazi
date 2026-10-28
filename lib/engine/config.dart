import 'dart:math';
import 'models.dart';

const minPlayers = 5;
const maxPlayers = 12;

/// The three play modes: basic, classic (extended roles) and custom.
enum Preset { basic, classic, custom }

enum TieRule { none, revote, random }

const optionalRoles = [
  Role.doctor,
  Role.investigator,
  Role.sniper,
  Role.mayor,
  Role.goodBoy,
];

int autoMafia(int n) => n <= 7 ? 1 : (n <= 11 ? 2 : 3);
int maxMafia(int n) => (n - 1) ~/ 2;

/// Dajjal specialists. They only take part when the match has at least two
/// Dajjal; a match may mix them with plain Dajjal.
const mafiaSpecialRoles = [Role.sheikh, Role.silencer];

/// Basic: Dajjal + Wild al-Santi + Investigator + Kartiya.
/// Classic: every extended role (including the Dajjal specialists).
/// Custom: chosen by the players.
Set<Role> presetRoles(Preset p) => switch (p) {
      Preset.basic => {Role.doctor, Role.investigator},
      Preset.classic => {
          Role.doctor,
          Role.investigator,
          Role.sniper,
          Role.mayor,
          Role.goodBoy,
          Role.sheikh,
          Role.silencer
        },
      Preset.custom => <Role>{},
    };

/// Collapses inner whitespace and trims, so "  علي   " and "علي" are equal.
String normalizeName(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Returns an Arabic error for empty or duplicated names, or null if valid.
/// Never alters its input.
String? validateNames(List<String> raw) {
  final names = raw.map(normalizeName).toList();
  if (names.any((n) => n.isEmpty)) return 'أدخلوا أسماء جميع اللاعبين';
  if (names.map((n) => n.toLowerCase()).toSet().length != names.length) {
    return 'الأسماء يجب ألا تتكرر';
  }
  return null;
}

/// Builds a config from enabled optional roles. Never drops an enabled role;
/// if there are too many, [RoleConfig.validate] reports the problem.
///
/// [mafia] is the TOTAL number of Dajjal. With two or more Dajjal the enabled
/// specialists (sheikh / silencer) take some of those places; the rest are
/// plain Dajjal. With [dual] and both specialists enabled, ONE Dajjal (the
/// sheikh) carries both abilities, so only one place is used.
RoleConfig buildConfig(int n, Set<Role> enabled, {int? mafia, bool dual = false}) {
  final total = mafia ?? autoMafia(n);
  final c = <Role, int>{};
  var specials = 0;
  var merged = false;
  if (total >= 2) {
    final sheikh = enabled.contains(Role.sheikh);
    final silencer = enabled.contains(Role.silencer);
    if (sheikh) {
      c[Role.sheikh] = 1;
      specials++;
    }
    if (silencer && !(dual && sheikh)) {
      c[Role.silencer] = 1;
      specials++;
    }
    merged = dual && sheikh && silencer;
  }
  c[Role.mafia] = total - specials;
  for (final r in optionalRoles) {
    if (enabled.contains(r)) c[r] = 1;
  }
  final used = c.values.fold(0, (a, b) => a + b);
  c[Role.kartiya] = used < n ? n - used : 0;
  return RoleConfig(c, merged: merged);
}

class RoleConfig {
  RoleConfig(Map<Role, int> counts, {this.merged = false})
      : counts = Map.unmodifiable(counts);
  final Map<Role, int> counts;

  /// True when one Dajjal (the sheikh) also carries the silencer's ability.
  final bool merged;

  int count(Role r) => counts[r] ?? 0;
  int get total => counts.values.fold(0, (a, b) => a + b);
  /// Total size of the Dajjal team (plain Dajjal + specialists).
  int get mafia => counts.entries
      .where((e) => e.key.faction == Faction.mafia)
      .fold(0, (a, e) => a + e.value);

  /// Returns an Arabic error message, or null when valid. Never alters input.
  String? validate(int players) {
    if (players < minPlayers || players > maxPlayers) {
      return 'عدد اللاعبين يجب أن يكون بين 5 و 12';
    }
    if (counts.values.any((c) => c < 0)) return 'عدد غير صالح';
    if (mafia < 1) return 'يجب أن يوجد فرد واحد على الأقل من الدجگال';
    if (total > players) {
      return 'الأدوار المفعّلة ($total) أكثر من عدد اللاعبين ($players)';
    }
    if (total != players) {
      return 'مجموع الأدوار ($total) لا يساوي عدد اللاعبين ($players)';
    }
    if (mafia < 2 && (count(Role.sheikh) > 0 || count(Role.silencer) > 0)) {
      return 'شيخ المافيا ومافيا التسكيت يحتاجان إلى فردين على الأقل من الدجگال';
    }
    if (mafia * 2 >= players) return 'الدجگال كثيرون جداً: يفوزون من أول لحظة';
    for (final r in [...optionalRoles, ...mafiaSpecialRoles]) {
      if (count(r) > 1) return 'الدور ${r.arabic} يسمح بنسخة واحدة فقط';
    }
    return null;
  }

  /// Provisional table from the spec; kartiya fills the remainder.
  static RoleConfig suggested(int n) {
    final mafia = n <= 7 ? 1 : (n <= 11 ? 2 : 3);
    final c = <Role, int>{Role.mafia: mafia, Role.doctor: 1};
    if (n >= 6) c[Role.investigator] = 1;
    if (n == 10 || n == 12) c[Role.sniper] = 1;
    final used = c.values.fold(0, (a, b) => a + b);
    c[Role.kartiya] = n - used;
    return RoleConfig(c);
  }
}

List<Player> assignRoles(List<String> names, RoleConfig cfg, Random rng) {
  final err = cfg.validate(names.length);
  if (err != null) throw ArgumentError(err);
  final roles = <Role>[
    for (final e in cfg.counts.entries)
      for (var i = 0; i < e.value; i++) e.key,
  ]..shuffle(rng);
  return [for (var i = 0; i < names.length; i++) Player(names[i], roles[i])];
}
