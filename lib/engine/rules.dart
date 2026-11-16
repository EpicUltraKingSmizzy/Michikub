/// House rules, chosen by the host before a game.
class HouseRules {
  /// Minimum points for a player's first meld. 0 means Off (no minimum and
  /// the board can be rearranged from the first turn).
  final int firstMeld;
  final int handSize;
  final int jokers;

  /// Seconds per turn. 0 means Off.
  final int turnSeconds;
  final int passDraw;

  const HouseRules({
    this.firstMeld = 30,
    this.handSize = 14,
    this.jokers = 2,
    this.turnSeconds = 60,
    this.passDraw = 1,
  });

  static const classic = HouseRules();
  static const List<int> timerOptions = [0, 30, 60, 120];

  HouseRules copyWith({int? firstMeld, int? handSize, int? jokers, int? turnSeconds, int? passDraw}) =>
      HouseRules(
        firstMeld: firstMeld ?? this.firstMeld,
        handSize: handSize ?? this.handSize,
        jokers: jokers ?? this.jokers,
        turnSeconds: turnSeconds ?? this.turnSeconds,
        passDraw: passDraw ?? this.passDraw,
      );

  /// Clamps every value into its allowed range.
  HouseRules normalized() => HouseRules(
        firstMeld: firstMeld <= 0 ? 0 : firstMeld.clamp(3, 50),
        handSize: handSize.clamp(7, 20),
        jokers: jokers.clamp(0, 4),
        turnSeconds: timerOptions.contains(turnSeconds) ? turnSeconds : 60,
        passDraw: passDraw.clamp(1, 3),
      );

  Map<String, dynamic> toJson() => {
        'firstMeld': firstMeld,
        'handSize': handSize,
        'jokers': jokers,
        'turnSeconds': turnSeconds,
        'passDraw': passDraw,
      };

  factory HouseRules.fromJson(Map<String, dynamic> j) => HouseRules(
        firstMeld: j['firstMeld'] as int? ?? 30,
        handSize: j['handSize'] as int? ?? 14,
        jokers: j['jokers'] as int? ?? 2,
        turnSeconds: j['turnSeconds'] as int? ?? 60,
        passDraw: j['passDraw'] as int? ?? 1,
      ).normalized();

  @override
  bool operator ==(Object other) =>
      other is HouseRules &&
      other.firstMeld == firstMeld &&
      other.handSize == handSize &&
      other.jokers == jokers &&
      other.turnSeconds == turnSeconds &&
      other.passDraw == passDraw;

  @override
  int get hashCode => Object.hash(firstMeld, handSize, jokers, turnSeconds, passDraw);

  String summary() => [
        firstMeld == 0 ? 'No first-meld minimum' : 'First meld $firstMeld',
        '$handSize tiles',
        '$jokers joker${jokers == 1 ? '' : 's'}',
        turnSeconds == 0 ? 'No timer' : '${turnSeconds}s turns',
        'Pass draws $passDraw',
      ].join(' · ');
}

/// Test-only switches for solo play, set under Options > Test tools.
/// They only apply to Practice and Pass-and-play games.
class TestTools {
  final bool enabled;

  /// Fixed shuffle seed (null = random).
  final int? seed;

  /// Guarantee the first human a joker in the opening hand.
  final bool giveJoker;

  /// Limit the draw pile to this many tiles after dealing (null = full).
  final int? pileLimit;

  /// Override the turn timer in seconds (null = use house rules).
  final int? timerOverride;

  /// Show the "Test" entries in the in-game menu (win now, draw 5, etc).
  final bool cheatMenu;

  const TestTools({
    this.enabled = false,
    this.seed,
    this.giveJoker = false,
    this.pileLimit,
    this.timerOverride,
    this.cheatMenu = true,
  });

  static const off = TestTools();

  TestTools copyWith({
    bool? enabled,
    int? Function()? seed,
    bool? giveJoker,
    int? Function()? pileLimit,
    int? Function()? timerOverride,
    bool? cheatMenu,
  }) =>
      TestTools(
        enabled: enabled ?? this.enabled,
        seed: seed != null ? seed() : this.seed,
        giveJoker: giveJoker ?? this.giveJoker,
        pileLimit: pileLimit != null ? pileLimit() : this.pileLimit,
        timerOverride: timerOverride != null ? timerOverride() : this.timerOverride,
        cheatMenu: cheatMenu ?? this.cheatMenu,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'seed': seed,
        'giveJoker': giveJoker,
        'pileLimit': pileLimit,
        'timerOverride': timerOverride,
        'cheatMenu': cheatMenu,
      };

  factory TestTools.fromJson(Map<String, dynamic> j) => TestTools(
        enabled: j['enabled'] as bool? ?? false,
        seed: j['seed'] as int?,
        giveJoker: j['giveJoker'] as bool? ?? false,
        pileLimit: j['pileLimit'] as int?,
        timerOverride: j['timerOverride'] as int?,
        cheatMenu: j['cheatMenu'] as bool? ?? true,
      );
}
