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
  'radio': 'Start radio', 'download': 'Download', 'album': 'Go to album', 'artist': 'Go to artist',
  'hide': 'Not interested', 'block': "Don't recommend artist",
};
const bigCapable = ['playNext', 'queue', 'like', 'playlist', 'radio', 'download'];

class Settings extends ChangeNotifier {
  String accent = 'purple';
  bool amoled = false;
  bool autoplay = true;
  bool dynamicTheme = true;
  bool showTrending = true;
  String displayName = '';
  List<String> menuBig = ['playNext', 'like', 'playlist'];
  List<String> menuOptions = ['queue', 'radio', 'download', 'album', 'artist', 'hide', 'block'];

  // Home feed sections
  bool showQuickPicks = true;   // 3-row cover grid (YT-Music "Kurzauswahl")
  bool showQuickPlay = true;    // 4-song scrollable row ("Schnellauswahl")
  bool showMixes = true;        // personal mixes / radios
  bool showDiscover = true;     // charts, top artists, new releases
  bool showPlaylistsHome = true;
  bool showDownloadsHome = true;

  // Now playing / player
  bool scrollingTitles = true;  // marquee long titles
  bool bigPlayerArt = true;

  // Queue sheet
  bool queueExpands = true;     // drag to contract/expand vs fixed height
  bool queueShowTitles = true;  // show song titles (vs compact art-only)

  // NEXT UP bar (on Home)
  bool queueBarShow = true;     // show the NEXT UP strip at all
  bool queueBarOpen = true;     // currently expanded (toggled by the top-bar button)
  bool queueBarShrink = true;   // contract as you scroll down
  bool queueBarArtist = true;   // show artist under the title
  String queueBarSize = 'M';    // S / M / L cover size

  // Home extras
  bool showGreeting = true;
  bool moodChips = true;
  bool quickPicksSnap = true;   // snap between 3x3 grids

  double get queueCover => queueBarSize == 'S' ? 84 : queueBarSize == 'L' ? 128 : 104;

  SharedPreferences? _prefs;

  List<Color> get accentColors => accents[accent] ?? accents['purple']!;
  Color get bg => amoled ? Colors.black : const Color(0xFF0A0A12);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString('settings');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
        accent = j['accent'] ?? accent;
        amoled = b('amoled', amoled);
        autoplay = b('autoplay', autoplay);
        dynamicTheme = b('dynamicTheme', dynamicTheme);
        showTrending = b('showTrending', showTrending);
        displayName = j['displayName'] ?? displayName;
        menuBig = ((j['menuBig'] as List?)?.cast<String>()) ?? menuBig;
        menuOptions = ((j['menuOptions'] as List?)?.cast<String>()) ?? menuOptions;
        showQuickPicks = b('showQuickPicks', showQuickPicks);
        showQuickPlay = b('showQuickPlay', showQuickPlay);
        showMixes = b('showMixes', showMixes);
        showDiscover = b('showDiscover', showDiscover);
        showPlaylistsHome = b('showPlaylistsHome', showPlaylistsHome);
        showDownloadsHome = b('showDownloadsHome', showDownloadsHome);
        scrollingTitles = b('scrollingTitles', scrollingTitles);
        bigPlayerArt = b('bigPlayerArt', bigPlayerArt);
        queueExpands = b('queueExpands', queueExpands);
        queueShowTitles = b('queueShowTitles', queueShowTitles);
        queueBarShow = b('queueBarShow', queueBarShow);
        queueBarOpen = b('queueBarOpen', queueBarOpen);
        queueBarShrink = b('queueBarShrink', queueBarShrink);
        queueBarArtist = b('queueBarArtist', queueBarArtist);
        queueBarSize = j['queueBarSize'] ?? queueBarSize;
        showGreeting = b('showGreeting', showGreeting);
        moodChips = b('moodChips', moodChips);
        quickPicksSnap = b('quickPicksSnap', quickPicksSnap);
      } catch (_) {}
    }
    notifyListeners();
  }

  void _save() {
    _prefs?.setString('settings', jsonEncode({
      'accent': accent, 'amoled': amoled, 'autoplay': autoplay, 'dynamicTheme': dynamicTheme,
      'showTrending': showTrending, 'displayName': displayName, 'menuBig': menuBig, 'menuOptions': menuOptions,
      'showQuickPicks': showQuickPicks, 'showQuickPlay': showQuickPlay, 'showMixes': showMixes,
      'showDiscover': showDiscover, 'showPlaylistsHome': showPlaylistsHome, 'showDownloadsHome': showDownloadsHome,
      'scrollingTitles': scrollingTitles, 'bigPlayerArt': bigPlayerArt,
      'queueExpands': queueExpands, 'queueShowTitles': queueShowTitles,
      'queueBarShow': queueBarShow, 'queueBarOpen': queueBarOpen, 'queueBarShrink': queueBarShrink,
      'queueBarArtist': queueBarArtist, 'queueBarSize': queueBarSize,
      'showGreeting': showGreeting, 'moodChips': moodChips, 'quickPicksSnap': quickPicksSnap,
    }));
    notifyListeners();
  }

  void update(void Function() change) { change(); _save(); }
}
