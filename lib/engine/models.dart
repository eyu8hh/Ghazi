enum Faction { mafia, good }

/// Internal identifiers (enum names) never change: they are used as storage
/// keys. Only [arabic] is shown to players.
enum Role {
  mafia(Faction.mafia, 'الدجگال'),
  sheikh(Faction.mafia, 'شيخ المافيا'),
  silencer(Faction.mafia, 'مافيا التسكيت'),
  doctor(Faction.good, 'ولد الصنتي'),
  investigator(Faction.good, 'المحقق / الشيخ الصالح'),
  sniper(Faction.good, 'القناص الصالح'),
  mayor(Faction.good, 'العمدة'),
  goodBoy(Faction.good, 'الولد الصالح'),
  kartiya(Faction.good, 'كارطية');

  const Role(this.faction, this.arabic);
  final Faction faction;
  final String arabic;
}

/// Points awarded to every living member of the winning team.
const pointsPerSurvivor = 70;

class Player {
  Player(this.name, this.role);
  final String name;
  final Role role;
  bool alive = true;
  bool mayorRevealed = false;
  bool get isMafia => role.faction == Faction.mafia;
}

class MatchResult {
  const MatchResult(this.winner, this.survivors, this.score);
  final Faction winner;
  final int survivors;

  /// Team total: [survivors] x [pointsPerSurvivor].
  final int score;
}
