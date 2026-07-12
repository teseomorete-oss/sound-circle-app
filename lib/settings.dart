import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const accents = <String, List<Color>>{
  'purple': [Color(0xFFA855F7), Color(0xFFEC4899)],
  'blue': [Color(0xFF3B82F6), Color(0xFF06B6D4)],
  'green': [Color(0xFF22C55E), Color(0xFF14B8A6)],
  'sunset': [Color(0xFFF97316), Color(0xFFF43F5E)],
  'crimson': [Color(0xFFEF4444), Color(0xFFA855F7)],
};

const allMenuActions = <String, String>{
  'playNext': 'Play next', 'queue': 'Add to queue', 'like': 'Like', 'playlist': 'Add to playlist',
  'radio': 'Start radio', 'album': 'Go to album', 'artist': 'Go to artist',
  'hide': 'Not interested', 'block': "Don't recommend artist",
};
const bigCapable = ['playNext', 'queue', 'like', 'playlist', 'radio'];

class Settings extends ChangeNotifier {
  String accent = 'purple';
  bool amoled = false;
  bool autoplay = true;
  bool dynamicTheme = true;
  bool showTrending = true;
  String displayName = '';
  List<String> menuBig = ['playNext', 'like', 'playlist'];
  List<String> menuOptions = ['queue', 'radio', 'album', 'artist', 'hide', 'block'];

  SharedPreferences? _prefs;

  List<Color> get accentColors => accents[accent] ?? accents['purple']!;
  Color get bg => amoled ? Colors.black : const Color(0xFF0A0A12);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString('settings');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        accent = j['accent'] ?? accent;
        amoled = j['amoled'] ?? amoled;
        autoplay = j['autoplay'] ?? autoplay;
        dynamicTheme = j['dynamicTheme'] ?? dynamicTheme;
        showTrending = j['showTrending'] ?? showTrending;
        displayName = j['displayName'] ?? displayName;
        menuBig = ((j['menuBig'] as List?)?.cast<String>()) ?? menuBig;
        menuOptions = ((j['menuOptions'] as List?)?.cast<String>()) ?? menuOptions;
      } catch (_) {}
    }
    notifyListeners();
  }

  void _save() {
    _prefs?.setString('settings', jsonEncode({
      'accent': accent, 'amoled': amoled, 'autoplay': autoplay, 'dynamicTheme': dynamicTheme,
      'showTrending': showTrending, 'displayName': displayName, 'menuBig': menuBig, 'menuOptions': menuOptions,
    }));
    notifyListeners();
  }

  void update(void Function() change) { change(); _save(); }
}
