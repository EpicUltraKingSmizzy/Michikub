import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/host.dart';
import '../engine/rules.dart';

/// Everything saved on this phone. Nothing leaves the device.
class AppPrefs extends ChangeNotifier {
  SharedPreferences? _p;
  String name = 'Player';

  /// Your avatar (an id from avatars.dart), or null for your initial.
  String? avatar;
  HouseRules rules = HouseRules.classic;
  Map<String, HouseRules> presets = {};
  TestTools test = TestTools.off;
  bool haptics = true;

  /// Sound effects (Options).
  bool sound = true;
  bool highlightValid = true;
  List<BotLevel> practiceBots = [BotLevel.medium];
  List<String> hotSeatNames = ['Player 1', 'Player 2'];

  static final AppPrefs instance = AppPrefs();

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final p = _p!;
    name = p.getString('name') ?? name;
    avatar = p.getString('avatar');
    haptics = p.getBool('haptics') ?? true;
    sound = p.getBool('sound') ?? true;
    highlightValid = p.getBool('highlightValid') ?? true;
    final r = p.getString('rules');
    if (r != null) rules = HouseRules.fromJson(jsonDecode(r) as Map<String, dynamic>);
    final pr = p.getString('presets');
    if (pr != null) {
      final m = jsonDecode(pr) as Map<String, dynamic>;
      presets = {for (final e in m.entries) e.key: HouseRules.fromJson(e.value as Map<String, dynamic>)};
    }
    final t = p.getString('test');
    if (t != null) test = TestTools.fromJson(jsonDecode(t) as Map<String, dynamic>);
    final b = p.getStringList('practiceBots');
    if (b != null && b.isNotEmpty) practiceBots = b.map(BotLevel.values.byName).toList();
    final h = p.getStringList('hotSeatNames');
    if (h != null && h.length >= 2) hotSeatNames = h;
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    final p = _p;
    if (p == null) return;
    await p.setString('name', name);
    if (avatar == null) {
      await p.remove('avatar');
    } else {
      await p.setString('avatar', avatar!);
    }
    await p.setBool('haptics', haptics);
    await p.setBool('sound', sound);
    await p.setBool('highlightValid', highlightValid);
    await p.setString('rules', jsonEncode(rules.toJson()));
    await p.setString('presets', jsonEncode({for (final e in presets.entries) e.key: e.value.toJson()}));
    await p.setString('test', jsonEncode(test.toJson()));
    await p.setStringList('practiceBots', practiceBots.map((e) => e.name).toList());
    await p.setStringList('hotSeatNames', hotSeatNames);
  }
}
