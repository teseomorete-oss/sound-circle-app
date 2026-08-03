import 'package:flutter/material.dart';

/// Lightweight translations. `L.t(context, 'key')` — or the shorthand
/// `'key'.tr(context)` — returns the string for the chosen language, falling
/// back to English when a key hasn't been translated yet.
class L {
  static const supported = <String, String>{
    'en': 'English',
    'de': 'Deutsch',
    'es': 'Español',
  };

  static String lang = 'en';

  static String t(String key) {
    final table = _strings[lang];
    return table?[key] ?? _strings['en']![key] ?? key;
  }

  static const _strings = <String, Map<String, String>>{
    'en': {
      // nav + headers
      'home': 'Home', 'search': 'Search', 'library': 'Library', 'settings': 'Settings',
      'goodMorning': 'Good morning', 'goodAfternoon': 'Good afternoon', 'goodEvening': 'Good evening',
      'quickPicks': 'Quick picks', 'recentlyPlayed': 'Recently played', 'madeForYou': 'Made for you',
      'mixesRadios': 'Mixes & radios', 'yourPlaylists': 'Your playlists', 'downloaded': 'Downloaded',
      'discover': 'Discover', 'trendingNow': 'Trending now', 'newReleases': 'New releases',
      'topArtists': 'Your top artists', 'popularArtists': 'Popular artists',
      'chartsMore': 'Charts & more', 'popular': 'Popular', 'albums': 'Albums',
      'fansAlsoLike': 'Fans also like', 'about': 'About', 'songs': 'Songs', 'artists': 'Artists',
      'all': 'All', 'playlists': 'Playlists', 'following': 'Following',
      // actions
      'play': 'Play', 'shuffle': 'Shuffle', 'playNext': 'Play next', 'addToQueue': 'Add to queue',
      'like': 'Like', 'addToPlaylist': 'Add to playlist', 'startRadio': 'Start radio',
      'download': 'Download', 'share': 'Share', 'sleepTimer': 'Sleep timer',
      'goToAlbum': 'Go to album', 'goToArtist': 'Go to artist', 'follow': 'Follow', 'following2': 'Following',
      'new': 'New', 'save': 'Save', 'cancel': 'Cancel', 'clear': 'Clear', 'later': 'Later',
      'queue': 'Queue', 'nextUp': 'NEXT UP', 'nowPlaying': 'NOW PLAYING', 'lyrics': 'LYRICS',
      'cover': 'Cover', 'lyricsBtn': 'Lyrics',
      // library
      'likedSongs': 'Liked Songs', 'autoPlaylist': 'Auto playlist', 'offline': 'Offline',
      'sharedPlaylists': 'Shared playlists', 'noPlaylists': 'No playlists yet.',
      'yourListening': 'Your listening', 'importYouTube': 'Import from YouTube',
      'sound': 'Sound', 'equalizer': 'Equalizer',
      // states
      'noLyrics': 'No lyrics found for this song', 'nothingQueued': 'Nothing queued.',
      'noInternet': 'No internet connection', 'signIn': 'Sign in', 'logOut': 'Log out',
      'guest': 'Guest', 'continueGuest': 'Continue as guest', 'welcomeBack': 'Welcome back',
      'createAccount': 'Create your account', 'email': 'Email', 'password': 'Password',
      'name': 'Name', 'signUp': 'Sign up', 'logIn': 'Log in',
      'feedbackIdeas': 'Feedback & ideas', 'send': 'Send',
      'week': 'Week', 'month': 'Month', 'year': 'Year', 'allTime': 'All time',
      'songsPlayed': 'Songs played', 'timeListened': 'Time listened', 'topSongs': 'Top songs',
      'language': 'Language',
    },
    'de': {
      'home': 'Start', 'search': 'Suche', 'library': 'Bibliothek', 'settings': 'Einstellungen',
      'goodMorning': 'Guten Morgen', 'goodAfternoon': 'Guten Tag', 'goodEvening': 'Guten Abend',
      'quickPicks': 'Schnellauswahl', 'recentlyPlayed': 'Zuletzt gespielt', 'madeForYou': 'Für dich',
      'mixesRadios': 'Mixe & Radios', 'yourPlaylists': 'Deine Playlists', 'downloaded': 'Heruntergeladen',
      'discover': 'Entdecken', 'trendingNow': 'Gerade angesagt', 'newReleases': 'Neuerscheinungen',
      'topArtists': 'Deine Top-Künstler', 'popularArtists': 'Beliebte Künstler',
      'chartsMore': 'Charts & mehr', 'popular': 'Beliebt', 'albums': 'Alben',
      'fansAlsoLike': 'Fans mögen auch', 'about': 'Über', 'songs': 'Songs', 'artists': 'Künstler',
      'all': 'Alle', 'playlists': 'Playlists', 'following': 'Abonniert',
      'play': 'Abspielen', 'shuffle': 'Zufall', 'playNext': 'Als Nächstes', 'addToQueue': 'Zur Warteschlange',
      'like': 'Gefällt mir', 'addToPlaylist': 'Zu Playlist', 'startRadio': 'Radio starten',
      'download': 'Herunterladen', 'share': 'Teilen', 'sleepTimer': 'Sleeptimer',
      'goToAlbum': 'Zum Album', 'goToArtist': 'Zum Künstler', 'follow': 'Folgen', 'following2': 'Abonniert',
      'new': 'Neu', 'save': 'Speichern', 'cancel': 'Abbrechen', 'clear': 'Leeren', 'later': 'Später',
      'queue': 'Warteschlange', 'nextUp': 'ALS NÄCHSTES', 'nowPlaying': 'LÄUFT GERADE', 'lyrics': 'LIEDTEXT',
      'cover': 'Cover', 'lyricsBtn': 'Liedtext',
      'likedSongs': 'Lieblingssongs', 'autoPlaylist': 'Automatische Playlist', 'offline': 'Offline',
      'sharedPlaylists': 'Gemeinsame Playlists', 'noPlaylists': 'Noch keine Playlists.',
      'yourListening': 'Dein Hörverhalten', 'importYouTube': 'Von YouTube importieren',
      'sound': 'Klang', 'equalizer': 'Equalizer',
      'noLyrics': 'Kein Liedtext gefunden', 'nothingQueued': 'Warteschlange ist leer.',
      'noInternet': 'Keine Internetverbindung', 'signIn': 'Anmelden', 'logOut': 'Abmelden',
      'guest': 'Gast', 'continueGuest': 'Als Gast fortfahren', 'welcomeBack': 'Willkommen zurück',
      'createAccount': 'Konto erstellen', 'email': 'E-Mail', 'password': 'Passwort',
      'name': 'Name', 'signUp': 'Registrieren', 'logIn': 'Anmelden',
      'feedbackIdeas': 'Feedback & Ideen', 'send': 'Senden',
      'week': 'Woche', 'month': 'Monat', 'year': 'Jahr', 'allTime': 'Gesamt',
      'songsPlayed': 'Songs gespielt', 'timeListened': 'Hörzeit', 'topSongs': 'Top-Songs',
      'language': 'Sprache',
    },
    'es': {
      'home': 'Inicio', 'search': 'Buscar', 'library': 'Biblioteca', 'settings': 'Ajustes',
      'goodMorning': 'Buenos días', 'goodAfternoon': 'Buenas tardes', 'goodEvening': 'Buenas noches',
      'quickPicks': 'Selección rápida', 'recentlyPlayed': 'Reproducido hace poco', 'madeForYou': 'Para ti',
      'mixesRadios': 'Mixes y radios', 'yourPlaylists': 'Tus listas', 'downloaded': 'Descargadas',
      'discover': 'Descubrir', 'trendingNow': 'Tendencias', 'newReleases': 'Novedades',
      'topArtists': 'Tus artistas top', 'popularArtists': 'Artistas populares',
      'chartsMore': 'Listas y más', 'popular': 'Populares', 'albums': 'Álbumes',
      'fansAlsoLike': 'También te puede gustar', 'about': 'Acerca de', 'songs': 'Canciones', 'artists': 'Artistas',
      'all': 'Todo', 'playlists': 'Listas', 'following': 'Siguiendo',
      'play': 'Reproducir', 'shuffle': 'Aleatorio', 'playNext': 'Reproducir a continuación',
      'addToQueue': 'Añadir a la cola', 'like': 'Me gusta', 'addToPlaylist': 'Añadir a lista',
      'startRadio': 'Iniciar radio', 'download': 'Descargar', 'share': 'Compartir',
      'sleepTimer': 'Temporizador', 'goToAlbum': 'Ir al álbum', 'goToArtist': 'Ir al artista',
      'follow': 'Seguir', 'following2': 'Siguiendo',
      'new': 'Nueva', 'save': 'Guardar', 'cancel': 'Cancelar', 'clear': 'Vaciar', 'later': 'Más tarde',
      'queue': 'Cola', 'nextUp': 'A CONTINUACIÓN', 'nowPlaying': 'REPRODUCIENDO', 'lyrics': 'LETRA',
      'cover': 'Portada', 'lyricsBtn': 'Letra',
      'likedSongs': 'Canciones que te gustan', 'autoPlaylist': 'Lista automática', 'offline': 'Sin conexión',
      'sharedPlaylists': 'Listas compartidas', 'noPlaylists': 'Aún no hay listas.',
      'yourListening': 'Tus escuchas', 'importYouTube': 'Importar de YouTube',
      'sound': 'Sonido', 'equalizer': 'Ecualizador',
      'noLyrics': 'No se encontró la letra', 'nothingQueued': 'La cola está vacía.',
      'noInternet': 'Sin conexión a internet', 'signIn': 'Iniciar sesión', 'logOut': 'Cerrar sesión',
      'guest': 'Invitado', 'continueGuest': 'Continuar como invitado', 'welcomeBack': 'Bienvenido de nuevo',
      'createAccount': 'Crea tu cuenta', 'email': 'Correo', 'password': 'Contraseña',
      'name': 'Nombre', 'signUp': 'Registrarse', 'logIn': 'Iniciar sesión',
      'feedbackIdeas': 'Comentarios e ideas', 'send': 'Enviar',
      'week': 'Semana', 'month': 'Mes', 'year': 'Año', 'allTime': 'Todo el tiempo',
      'songsPlayed': 'Canciones reproducidas', 'timeListened': 'Tiempo escuchado', 'topSongs': 'Top canciones',
      'language': 'Idioma',
    },
  };
}

extension Tr on String {
  /// `'play'.tr` → the translated string.
  String get tr => L.t(this);
}

/// Locale for Flutter's own widgets (date pickers, text selection menus…).
Locale get appLocale => Locale(L.lang);
