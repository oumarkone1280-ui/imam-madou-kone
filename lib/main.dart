import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import 'freemium/freemium_core.dart';
import 'freemium/freemium_ui.dart';

/// URL de base des audios hébergés sur le serveur.
///
/// Par défaut, il s'agit du serveur XAMPP local du développeur.
/// Pour pointer vers un autre serveur (par ex. en production) :
///   flutter run --dart-define=AUDIO_BASE_URL=https://votre-serveur.com/IMMK/audios
const String kAudioBaseUrl = String.fromEnvironment(
  'AUDIO_BASE_URL',
  defaultValue: 'http://192.168.1.63/IMMK/audios',
);

/// Version affichée dans l'application.
///
/// À garder alignée sur la ligne `version:` de `pubspec.yaml` (sans le numéro
/// de build après le « + »).
const String kAppVersion = '1.0.1';

/// Couleur de fond des pages : crème en mode clair, émeraude très foncé en
/// mode sombre. Les pages utilisent `pageSurface` au lieu d'un beige en dur.
Color pageSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0E1A16)
        : const Color(0xFFF5F1E8);

/// Fond des cartes : blanc en mode clair, vert foncé en mode sombre.
Color cardSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1B2E29)
        : Colors.white;

/// Texte principal posé sur les surfaces claires.
Color mainText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE9F0ED)
        : const Color(0xFF1C1F1E);

/// Texte secondaire posé sur les surfaces claires.
Color subText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9EB0A9)
        : const Color(0xFF67706D);

/// Vrai quand la langue active (arabe) impose un sens d'écriture RTL.
bool _isRTL(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

/// Début d'un dégradé diagonal : haut-droit en RTL, haut-gauche en LTR.
Alignment _gBegin(BuildContext context) =>
    _isRTL(context) ? Alignment.topRight : Alignment.topLeft;

/// Fin d'un dégradé diagonal : bas-gauche en RTL, bas-droit en LTR.
Alignment _gEnd(BuildContext context) =>
    _isRTL(context) ? Alignment.bottomLeft : Alignment.bottomRight;

/// Chevron « aller de l'avant » : pointe vers la gauche en RTL.
IconData _chevronIcon(BuildContext context) => _isRTL(context)
    ? Icons.chevron_left_rounded
    : Icons.chevron_right_rounded;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'imam_madou_kone_audio',
    androidNotificationChannelName: 'Lecteur Imam Madou Koné',
    androidNotificationOngoing: true,
  );

  // Restaure les favoris enregistrés sur l'appareil.
  await FavoritesStore.instance.load();

  // Charge les réglages personnalisés de l'utilisateur.
  await SettingsStore.instance.load();

  // Charge l'état Freemium (compte + abonnement persistés).
  await FreemiumStore.instance.load();

  // Remonte le profil + abonnement au registre du promoteur (best-effort,
  // silencieux en cas de serveur injoignable).
  FreemiumStore.instance.syncToLedger();

  runApp(const ImamMadouKoneApp());
}

/// Stockage local des favoris, persisté sur le téléphone.
///
/// Chaque audio est identifié par son chemin d'asset (`audioAsset`),
/// une clé stable quel que soit l'appareil.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();

  static final FavoritesStore instance = FavoritesStore._();

  static const String _prefsKey = 'favorite_audio_ids';

  final Set<String> _ids = <String>{};

  /// Charge les favoris depuis le stockage local.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ids
        ..clear()
        ..addAll(prefs.getStringList(_prefsKey) ?? const []);
    } catch (_) {
      // Sans plugin (mode test), on fonctionne en mémoire seulement.
    }
    notifyListeners();
  }

  /// Clé de favori propre à un prêcheur : deux comptes n'ont jamais les mêmes
  /// favoris, même pour un même chemin d'audio.
  static String _preacherKey(Preacher preacher, String audioAsset) =>
      '${preacher.id}|$audioAsset';

  bool containsFor(Preacher preacher, String audioAsset) =>
      _ids.contains(_preacherKey(preacher, audioAsset));

  /// Ajoute ou retire un audio des favoris (persistance automatique).
  Future<void> toggleFor(Preacher preacher, String audioAsset) async {
    final key = _preacherKey(preacher, audioAsset);
    if (!_ids.remove(key)) {
      _ids.add(key);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _ids.toList());
    } catch (_) {
      // La persistance peut échouer (mode test) : l'état en mémoire suffit.
    }
  }

  /// Efface tous les favoris enregistrés sur l'appareil.
  Future<void> clearAll() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _ids.toList());
    } catch (_) {
      // La persistance peut échouer (mode test) : l'état en mémoire suffit.
    }
  }

  // Compatibilité : les favoris de l'espace Imam Madou Koné (ancien compte
  // unique) continuent de fonctionner exactement comme avant.
  bool contains(String audioAsset) => containsFor(imamMadouKone, audioAsset);

  Future<void> toggle(String audioAsset) =>
      toggleFor(imamMadouKone, audioAsset);
}

/// Réglages persistés de l'application.
///
/// Les valeurs par défaut sont celles d'une écoute standard :
/// vitesse 1x, reprise automatique activée, lecture en arrière-plan activée.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();

  static final SettingsStore instance = SettingsStore._();

  static const String _keyDefaultSpeed = 'settings_default_speed';
  static const String _keyResumeEnabled = 'settings_resume_enabled';
  static const String _keyBackgroundPlayback = 'settings_background_playback';
  static const String _keyThemeMode = 'settings_theme_mode';
  static const String _keyLanguage = 'settings_language';
  static const String _keyMediaNotifications = 'settings_media_notifications';

  static const List<double> speedOptions = [1.0, 1.25, 1.5, 2.0];
  static const List<String> themeOptions = ['system', 'light', 'dark'];
  static const List<String> languageOptions = ['fr', 'en', 'ar'];

  double _defaultSpeed = 1.0;
  bool _resumeEnabled = true;
  bool _backgroundPlayback = true;
  String _themeMode = 'system';
  String _language = 'fr';
  bool _mediaNotifications = true;

  double get defaultSpeed => _defaultSpeed;
  bool get resumeEnabled => _resumeEnabled;
  bool get backgroundPlayback => _backgroundPlayback;
  String get themeMode => _themeMode;
  String get language => _language;
  bool get mediaNotifications => _mediaNotifications;

  /// Charge les réglages depuis le stockage local.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSpeed = prefs.getDouble(_keyDefaultSpeed);
      _defaultSpeed = (savedSpeed != null && speedOptions.contains(savedSpeed))
          ? savedSpeed
          : 1.0;
      _resumeEnabled = prefs.getBool(_keyResumeEnabled) ?? true;
      _backgroundPlayback = prefs.getBool(_keyBackgroundPlayback) ?? true;
      final savedTheme = prefs.getString(_keyThemeMode) ?? 'system';
      _themeMode = themeOptions.contains(savedTheme) ? savedTheme : 'system';
      final savedLanguage = prefs.getString(_keyLanguage) ?? 'fr';
      _language = languageOptions.contains(savedLanguage)
          ? savedLanguage
          : 'fr';
      _mediaNotifications = prefs.getBool(_keyMediaNotifications) ?? true;
    } catch (_) {
      // Sans plugin (mode test), on fonctionne avec les valeurs par défaut.
    }
    notifyListeners();
  }

  Future<void> setDefaultSpeed(double value) async {
    if (!speedOptions.contains(value)) return;
    _defaultSpeed = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDefaultSpeed, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  Future<void> setResumeEnabled(bool value) async {
    _resumeEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyResumeEnabled, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  Future<void> setBackgroundPlayback(bool value) async {
    _backgroundPlayback = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBackgroundPlayback, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  Future<void> setThemeMode(String value) async {
    if (!themeOptions.contains(value)) return;
    _themeMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  Future<void> setLanguage(String value) async {
    if (!languageOptions.contains(value)) return;
    _language = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLanguage, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  Future<void> setMediaNotifications(bool value) async {
    _mediaNotifications = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyMediaNotifications, value);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  /// Rétablit toutes les valeurs par défaut.
  Future<void> resetAll() async {
    _defaultSpeed = 1.0;
    _resumeEnabled = true;
    _backgroundPlayback = true;
    _themeMode = 'system';
    _language = 'fr';
    _mediaNotifications = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDefaultSpeed);
      await prefs.remove(_keyResumeEnabled);
      await prefs.remove(_keyBackgroundPlayback);
      await prefs.remove(_keyThemeMode);
      await prefs.remove(_keyLanguage);
      await prefs.remove(_keyMediaNotifications);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }
}

/// Traductions légères de l'interface (menu, réglages, titres de pages).
///
/// Le contenu des audios (titres, descriptions, catégories) n'est pas
/// traduit : ce sont des données de l'application, pas des éléments
/// d'interface.
class L10n {
  L10n._();

  static const Map<String, String> _fr = {
    'nav.home': 'Accueil',
    'nav.audios': 'Audios',
    'nav.search': 'Recherche',
    'nav.about': 'À propos',
    'search.title': 'Recherche',
    'about.title': 'À propos',
    'library.title': 'Bibliothèque audio',
    'home.greeting':
        'Assalamu alaykum. Retrouvez les rappels, lectures et cours de '
            'l’Imam Madou Koné.',
    'settings.appBar': 'Paramètres',
    'settings.heroTitle': 'Réglages',
    'settings.heroSubtitle': 'Personnalisez votre expérience d’écoute.',
    'section.appearance': 'APPARENCE',
    'section.playback': 'LECTURE',
    'section.notifications': 'NOTIFICATIONS',
    'section.sharing': 'PARTAGE & ÉVALUATION',
    'section.data': 'DONNÉES',
    'section.updates': 'MISES À JOUR',
    'section.app': 'APPLICATION',
    'settings.theme': 'Thème',
    'settings.themeSub': 'Apparence générale de l’application.',
    'theme.system': 'Système',
    'theme.light': 'Clair',
    'theme.dark': 'Sombre',
    'settings.language': 'Langue',
    'settings.languageSub': 'Langue utilisée dans l’interface.',
    'lang.fr': 'Français',
    'lang.en': 'English',
    'lang.ar': 'العربية',
    'settings.speed': 'Vitesse de lecture',
    'settings.speedSub': 'Vitesse appliquée par défaut à chaque audio.',
    'settings.resume': 'Reprise automatique',
    'settings.resumeSub': 'Reprendre la lecture là où elle s’est arrêtée.',
    'settings.background': 'Lecture en arrière-plan',
    'settings.backgroundSub': 'Continuer l’audio quand l’app est fermée.',
    'settings.mediaNotifs': 'Contrôles sur l’écran verrouillé',
    'settings.mediaNotifsSub':
        'Afficher les contrôles de lecture dans la notification.',
    'settings.share': 'Partager le profil',
    'settings.shareSub': 'Envoyer les coordonnées et le lien de l’app.',
    'settings.rate': 'Noter l’application',
    'settings.rateSub': 'Donner une note sur le Google Play.',
    'settings.clearFavorites': 'Effacer les favoris',
    'settings.clearFavoritesSub': 'Supprimer tous les audios enregistrés.',
    'settings.reset': 'Réinitialiser les réglages',
    'settings.resetSub': 'Revenir aux valeurs par défaut.',
    'settings.checkUpdates': 'Vérifier les mises à jour',
    'settings.checkUpdatesSub': 'Rechercher une nouvelle version disponible.',
    'settings.about': 'À propos',
    'settings.aboutSub': 'Informations sur l’application et l’Imam.',
    'settings.version': 'Version',
    'common.cancel': 'Annuler',
    'common.ok': 'OK',
    'updates.current': 'Dernière version',
    'updates.upToDate': 'Vous disposez déjà de la dernière version.',
    'updates.openStore': 'Voir sur le Google Play',
    'share.failed': 'Impossible d’ouvrir la feuille de partage.',
    'rate.failed': 'Impossible d’ouvrir la page de l’application.',
    'reset.dialogTitle': 'Réinitialiser les réglages ?',
    'reset.dialogBody': 'Le thème, la langue, la vitesse, la reprise et la '
        'lecture en arrière-plan reviendront à leurs valeurs par défaut.',
    'reset.confirm': 'Réinitialiser',
    'reset.done': 'Réglages réinitialisés.',
    'favorites.dialogTitle': 'Effacer les favoris ?',
    'favorites.dialogBody':
        'Tous les audios enregistrés en favoris seront supprimés.',
    'favorites.clear': 'Effacer',
    'favorites.done': 'Favoris effacés.',
    'preachers.badge': 'PLATEFORME D’ÉCOUTE ISLAMIQUE',
    'preachers.subtitle':
        'Choisissez un prêcheur pour accéder à son espace, ses catégories '
        'et ses enseignements.',
    'preachers.select': 'Sélectionnez un prêcheur',
    'common.back': 'Retour',
    'common.backToSelection': 'Retour à la sélection',
    'library.heroSub':
        'Tous les sermons, enseignements et récitations en un seul endroit.',
    'library.favorites': 'Mes favoris',
    'library.categories': 'Catégories',
    'library.tip':
        'Les contenus sont disponibles depuis la page d’accueil et les '
        'catégories ci-dessus.',
    'category.comingSoon': 'Bientôt disponible',
    'category.collection': 'Collection',
    'category.empty': 'Aucun audio publié dans cette catégorie pour le moment.',
    'home.official': 'APPLICATION OFFICIELLE',
    'home.explore': 'Explorer les contenus',
    'home.latest': 'Dernière publication',
    'home.greetingOther':
        'Assalamu alaykum. Retrouvez ici les sermons et enseignements '
        'de {name}.',
    'favorites.add': 'Ajouter aux favoris',
    'favorites.remove': 'Retirer des favoris',
    'player.loadErrorDetail': 'Impossible de charger cet audio : {error}',
    'player.playError': 'Impossible de lire cet audio : {error}',
    'player.loadError': 'Impossible de charger cet audio.',
    'player.retry': 'Réessayer',
    'search.hint': 'Rechercher un audio, un sermon ou une catégorie',
    'search.stopDictation': 'Arrêter la dictée',
    'search.voice': 'Recherche vocale',
    'search.clear': 'Effacer',
    'search.listening': 'Écoute en cours… parlez maintenant',
    'search.voiceUnavailable':
        'La reconnaissance vocale n’est pas disponible sur cet appareil.',
    'search.voiceFailed':
        'Impossible de lancer la dictée. Vérifiez le micro ou réessayez.',
    'search.categoriesHint':
        'Sélectionnez plusieurs catégories pour affiner la recherche.',
    'search.reset': 'Réinitialiser',
    'search.noResults': 'Aucun résultat',
    'search.clearAll': 'Tout effacer',
    'search.emptyTitle': 'Aucun résultat pour le moment',
    'search.emptyBody':
        'Essayez un autre mot-clé, retirez un filtre ou changez de catégorie.',
    'search.favoritesChip': 'Favoris',
    'whatsapp.failed':
        'Impossible d’ouvrir WhatsApp pour le moment.',
    'about.presentation': 'Présentation',
    'about.schedule': 'Programme hebdomadaire',
    'about.contact': 'Contact',
    'about.contactUs': 'Nous contacter',
    'about.alternatively': 'Alternativement :',
  };

  static const Map<String, String> _en = {
    'nav.home': 'Home',
    'nav.audios': 'Audios',
    'nav.search': 'Search',
    'nav.about': 'About',
    'search.title': 'Search',
    'about.title': 'About',
    'library.title': 'Audio library',
    'home.greeting':
        'Assalamu alaykum. Listen to the reminders, recitations and '
            'lessons of Imam Madou Koné.',
    'settings.appBar': 'Settings',
    'settings.heroTitle': 'Settings',
    'settings.heroSubtitle': 'Customize your listening experience.',
    'section.appearance': 'APPEARANCE',
    'section.playback': 'PLAYBACK',
    'section.notifications': 'NOTIFICATIONS',
    'section.sharing': 'SHARE & RATING',
    'section.data': 'DATA',
    'section.updates': 'UPDATES',
    'section.app': 'APP',
    'settings.theme': 'Theme',
    'settings.themeSub': 'General appearance of the app.',
    'theme.system': 'System',
    'theme.light': 'Light',
    'theme.dark': 'Dark',
    'settings.language': 'Language',
    'settings.languageSub': 'Language used in the interface.',
    'lang.fr': 'Français',
    'lang.en': 'English',
    'lang.ar': 'العربية',
    'settings.speed': 'Playback speed',
    'settings.speedSub': 'Default speed applied to every audio.',
    'settings.resume': 'Auto resume',
    'settings.resumeSub': 'Resume playback where it stopped.',
    'settings.background': 'Background playback',
    'settings.backgroundSub': 'Keep audio playing when the app is closed.',
    'settings.mediaNotifs': 'Lock screen controls',
    'settings.mediaNotifsSub': 'Show playback controls in the notification.',
    'settings.share': 'Share the profile',
    'settings.shareSub': 'Send the contact details and app link.',
    'settings.rate': 'Rate the app',
    'settings.rateSub': 'Leave a rating on Google Play.',
    'settings.clearFavorites': 'Clear favorites',
    'settings.clearFavoritesSub': 'Remove all saved audios.',
    'settings.reset': 'Reset settings',
    'settings.resetSub': 'Restore the default values.',
    'settings.checkUpdates': 'Check for updates',
    'settings.checkUpdatesSub': 'Look for a new available version.',
    'settings.about': 'About',
    'settings.aboutSub': 'Information about the app and the Imam.',
    'settings.version': 'Version',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'updates.current': 'Latest version',
    'updates.upToDate': 'You already have the latest version.',
    'updates.openStore': 'Open Google Play',
    'share.failed': 'Could not open the share sheet.',
    'rate.failed': 'Could not open the app page.',
    'reset.dialogTitle': 'Reset settings?',
    'reset.dialogBody': 'Theme, language, speed, auto resume and background '
        'playback will return to their default values.',
    'reset.confirm': 'Reset',
    'reset.done': 'Settings reset.',
    'favorites.dialogTitle': 'Clear favorites?',
    'favorites.dialogBody': 'All saved favorites will be removed.',
    'favorites.clear': 'Clear',
    'favorites.done': 'Favorites cleared.',
    'preachers.badge': 'ISLAMIC LISTENING PLATFORM',
    'preachers.subtitle':
        'Choose a preacher to access his space, his categories and his '
        'teachings.',
    'preachers.select': 'Select a preacher',
    'common.back': 'Back',
    'common.backToSelection': 'Back to selection',
    'library.heroSub':
        'All the sermons, teachings and recitations in one place.',
    'library.favorites': 'My favorites',
    'library.categories': 'Categories',
    'library.tip':
        'Content is available from the home page and the categories above.',
    'category.comingSoon': 'Coming soon',
    'category.collection': 'Collection',
    'category.empty': 'No audio has been published in this category yet.',
    'home.official': 'OFFICIAL APP',
    'home.explore': 'Explore the content',
    'home.latest': 'Latest publication',
    'home.greetingOther':
        'Assalamu alaykum. Find here the sermons and teachings '
        'of {name}.',
    'favorites.add': 'Add to favorites',
    'favorites.remove': 'Remove from favorites',
    'player.loadErrorDetail': 'Unable to load this audio: {error}',
    'player.playError': 'Unable to play this audio: {error}',
    'player.loadError': 'Unable to load this audio.',
    'player.retry': 'Retry',
    'search.hint': 'Search an audio, a sermon or a category',
    'search.stopDictation': 'Stop dictation',
    'search.voice': 'Voice search',
    'search.clear': 'Clear',
    'search.listening': 'Listening… speak now',
    'search.voiceUnavailable':
        'Speech recognition is not available on this device.',
    'search.voiceFailed':
        'Unable to start dictation. Check the microphone or try again.',
    'search.categoriesHint':
        'Select several categories to refine the search.',
    'search.reset': 'Reset',
    'search.noResults': 'No results',
    'search.clearAll': 'Clear all',
    'search.emptyTitle': 'No results for now',
    'search.emptyBody':
        'Try another keyword, remove a filter or change category.',
    'search.favoritesChip': 'Favorites',
    'whatsapp.failed': 'Unable to open WhatsApp for now.',
    'about.presentation': 'Presentation',
    'about.schedule': 'Weekly schedule',
    'about.contact': 'Contact',
    'about.contactUs': 'Contact us',
    'about.alternatively': 'Alternatively:',
  };

  static const Map<String, String> _ar = {
    'nav.home': 'الرئيسية',
    'nav.audios': 'المحتوى',
    'nav.search': 'بحث',
    'nav.about': 'حول',
    'search.title': 'بحث',
    'about.title': 'حول',
    'library.title': 'المكتبة الصوتية',
    'home.greeting':
        'السلام عليكم. استمع إلى تذكيرات ودروس الإمام مادو كوني.',
    'settings.appBar': 'الإعدادات',
    'settings.heroTitle': 'الإعدادات',
    'settings.heroSubtitle': 'خصص تجربة الاستماع الخاصة بك.',
    'section.appearance': 'المظهر',
    'section.playback': 'التشغيل',
    'section.notifications': 'الإشعارات',
    'section.sharing': 'المشاركة والتقييم',
    'section.data': 'البيانات',
    'section.updates': 'التحديثات',
    'section.app': 'التطبيق',
    'settings.theme': 'المظهر',
    'settings.themeSub': 'المظهر العام للتطبيق.',
    'theme.system': 'النظام',
    'theme.light': 'فاتح',
    'theme.dark': 'داكن',
    'settings.language': 'اللغة',
    'settings.languageSub': 'اللغة المستخدمة في الواجهة.',
    'lang.fr': 'Français',
    'lang.en': 'English',
    'lang.ar': 'العربية',
    'settings.speed': 'سرعة التشغيل',
    'settings.speedSub': 'السرعة الافتراضية المطبقة على كل تسجيل.',
    'settings.resume': 'استئناف تلقائي',
    'settings.resumeSub': 'استئناف التشغيل من حيث توقف.',
    'settings.background': 'التشغيل في الخلفية',
    'settings.backgroundSub': 'متابعة الصوت عند إغلاق التطبيق.',
    'settings.mediaNotifs': 'أزرار شاشة القفل',
    'settings.mediaNotifsSub': 'إظهار أزرار التشغيل في الإشعار.',
    'settings.share': 'مشاركة التعريف',
    'settings.shareSub': 'إرسال معلومات التواصل ورابط التطبيق.',
    'settings.rate': 'تقييم التطبيق',
    'settings.rateSub': 'إعطاء تقييم على Google Play.',
    'settings.clearFavorites': 'مسح المفضلة',
    'settings.clearFavoritesSub': 'حذف جميع التسجيلات المحفوظة.',
    'settings.reset': 'إعادة تعيين الإعدادات',
    'settings.resetSub': 'العودة إلى القيم الافتراضية.',
    'settings.checkUpdates': 'التحقق من التحديثات',
    'settings.checkUpdatesSub': 'البحث عن إصدار جديد متاح.',
    'settings.about': 'حول',
    'settings.aboutSub': 'معلومات حول التطبيق والإمام.',
    'settings.version': 'الإصدار',
    'common.cancel': 'إلغاء',
    'common.ok': 'حسناً',
    'updates.current': 'أحدث إصدار',
    'updates.upToDate': 'لديك بالفعل أحدث إصدار.',
    'updates.openStore': 'فتح Google Play',
    'share.failed': 'تعذر فتح نافذة المشاركة.',
    'rate.failed': 'تعذر فتح صفحة التطبيق.',
    'reset.dialogTitle': 'إعادة تعيين الإعدادات؟',
    'reset.dialogBody': 'ستعود المظهر واللغة والسرعة والاستئناف والتشغيل في '
        'الخلفية إلى القيم الافتراضية.',
    'reset.confirm': 'إعادة تعيين',
    'reset.done': 'تمت إعادة تعيين الإعدادات.',
    'favorites.dialogTitle': 'مسح المفضلة؟',
    'favorites.dialogBody': 'سيتم حذف جميع التسجيلات المفضلة المحفوظة.',
    'favorites.clear': 'مسح',
    'favorites.done': 'تم مسح المفضلة.',
    'preachers.badge': 'منصة الاستماع الإسلامية',
    'preachers.subtitle':
        'اختر داعية للوصول إلى فضائه وفئاته ودروسه.',
    'preachers.select': 'اختر داعية',
    'common.back': 'رجوع',
    'common.backToSelection': 'العودة إلى الاختيار',
    'library.heroSub': 'جميع الخطب والدروس والتلاوات في مكان واحد.',
    'library.favorites': 'المفضلة',
    'library.categories': 'الفئات',
    'library.tip': 'المحتوى متاح من الصفحة الرئيسية والفئات أعلاه.',
    'category.comingSoon': 'قريباً',
    'category.collection': 'المجموعة',
    'category.empty': 'لا توجد تسجيلات منشورة في هذه الفئة حالياً.',
    'home.official': 'التطبيق الرسمي',
    'home.explore': 'استكشف المحتوى',
    'home.latest': 'أحدث منشور',
    'home.greetingOther':
        'السلام عليكم. ستجدون هنا خطب ودروس {name}.',
    'favorites.add': 'إضافة إلى المفضلة',
    'favorites.remove': 'إزالة من المفضلة',
    'player.loadErrorDetail': 'تعذر تحميل هذا التسجيل: {error}',
    'player.playError': 'تعذر تشغيل هذا التسجيل: {error}',
    'player.loadError': 'تعذر تحميل هذا التسجيل.',
    'player.retry': 'إعادة المحاولة',
    'search.hint': 'ابحث عن تسجيل أو خطبة أو فئة',
    'search.stopDictation': 'إيقاف الإملاء',
    'search.voice': 'البحث الصوتي',
    'search.clear': 'مسح',
    'search.listening': 'جارٍ الاستماع… تحدث الآن',
    'search.voiceUnavailable': 'التعرف على الصوت غير متوفر على هذا الجهاز.',
    'search.voiceFailed': 'تعذر بدء الإملاء. تحقق من الميكروفون أو أعد المحاولة.',
    'search.categoriesHint': 'حدد عدة فئات لتحسين البحث.',
    'search.reset': 'إعادة تعيين',
    'search.noResults': 'لا توجد نتائج',
    'search.clearAll': 'مسح الكل',
    'search.emptyTitle': 'لا توجد نتائج حالياً',
    'search.emptyBody': 'جرّب كلمة أخرى، أو أزل مرشحاً، أو غيّر الفئة.',
    'search.favoritesChip': 'المفضلة',
    'whatsapp.failed': 'تعذر فتح WhatsApp حالياً.',
    'about.presentation': 'تقديم',
    'about.schedule': 'البرنامج الأسبوعي',
    'about.contact': 'تواصل',
    'about.contactUs': 'تواصل معنا',
    'about.alternatively': 'بدلاً من ذلك:',
  };

  static Map<String, String> get _map => switch (SettingsStore.instance.language) {
        'en' => _en,
        'ar' => _ar,
        _ => _fr,
      };

  /// Traduit une clé dans la langue active (repli sur le français).
  static String t(String key) => _map[key] ?? _fr[key] ?? key;

  /// Locale correspondant à la langue active (gère aussi le sens RTL).
  static Locale get locale => switch (SettingsStore.instance.language) {
        'en' => const Locale('en'),
        'ar' => const Locale('ar'),
        _ => const Locale('fr'),
      };

  // -------------------------------------------------------------------------
  // Traduction du contenu (données internes conservées en français, traduites
  // à l'affichage dans la langue active).
  // -------------------------------------------------------------------------

  /// Dictionnaire FR→EN des contenus : catégories, sous-titres, prêcheurs,
  /// programme hebdomadaire et titres d'audios uniques.
  static const Map<String, String> _contentEn = {
    // Libellés courts des chips de recherche (doivent matcher le texte du
    // haystack localisé pour que le filtre fonctionne dans chaque langue).
    'Sîra': 'Seerah',
    'Coran': 'Quran',
    'Compagnons': 'Companions',
    // Catégories Imam Madou Koné (titres + sous-titres).
    'Sermons': 'Sermons',
    'Khutbas et rappels': 'Sermons and reminders',
    'Lecture du Coran': 'Quran recitation',
    'Sourates et récitations': 'Surahs and recitations',
    'Tafsir du Coran': 'Quran tafsir',
    'Explications des versets': 'Explanations of the verses',
    'Sîra du Prophète ﷺ': 'Seerah of the Prophet ﷺ',
    'Vie et enseignements': 'Life and teachings',
    'La vie des Compagnons du Prophète ﷺ':
        'The life of the Companions of the Prophet ﷺ',
    'Furuso Duman': 'Furuso Duman',
    // Catégories Koïta / Ouattara.
    'Sermon': 'Sermon',
    'Sermons et prêches': 'Sermons and talks',
    'Tafsir': 'Tafsir',
    'Explications et enseignements du Coran':
        'Explanations and teachings of the Quran',
    // Catégories Sidi Toure.
    'Traductions des sermons des Imams de La Mecque et de Médine':
        'Translations of the sermons of the Imams of Mecca and Medina',
    'Traductions des sermons': 'Translations of the sermons',
    "L'Histoire des Khalifes du Prophète ﷺ":
        'The History of the Caliphs of the Prophet ﷺ',
    'Histoire des Khalifes': 'History of the Caliphs',
    // Thème du programme.
    'Sermon / Khutba': 'Sermon / Khutbah',
    // Taglines des prêcheurs.
    'Prêches, Coran et enseignements': 'Sermons, Quran and teachings',
    'Sermons et tafsir du Coran': 'Sermons and tafsir of the Quran',
    'Traductions, tafsir, sîra et histoire des Khalifes':
        'Translations, tafsir, seerah and history of the Caliphs',
    // Jours du programme hebdomadaire.
    'Mardi': 'Tuesday',
    'Mercredi': 'Wednesday',
    'Jeudi': 'Thursday',
    'Vendredi': 'Friday',
    'Samedi': 'Saturday',
    'Dimanche': 'Sunday',
    // Horaires et lieux.
    'Entre Salat al-Maghrib et Salat al-Isha':
        'Between the Maghrib and Isha prayers',
    'Mosquée Ar-Rahma — Badalabougou': 'Ar-Rahma Mosque — Badalabougou',
    'Mosquée Ridwane — Kalaban-Coura': 'Ridwane Mosque — Kalaban-Coura',
    'Mosquée Verte — Banankabougou': 'Green Mosque — Banankabougou',
    'Mosquée Al-Imam Malik — Daoudabougou':
        'Al-Imam Malik Mosque — Daoudabougou',
    // Titres d'audios uniques (sermons).
    "La Grandeur d'Allah à travers sa création":
        'The Greatness of Allah through His creation',
    "L'education de l'enfant": 'The education of the child',
    'Les bienfaiteurs': 'The benefactors',
    "Le bienfait d'Allah": 'The blessing of Allah',
    'Apres_la_mort': 'After death',
    'Notre_Environnement': 'Our environment',
    'Famille_musulmane': 'Muslim family',
    'Le_droit_chemin': 'The right path',
    'Bientôt la rentree scolaire': 'Soon, the school year',
    // Sujets de la série Sira (parties 1 à 14).
    "l'enfance du Prophète ﷺ": 'the childhood of the Prophet ﷺ',
    "L'adolescence du Prophète ﷺ": 'The adolescence of the Prophet ﷺ',
    'La connaissance entre leProphète ﷺ et khadija رضي الله عنها':
        'The acquaintance between the Prophet ﷺ and Khadija رضي الله عنها',
    'Mariage du Prophète ﷺ et khadija رضي الله عنها':
        'Marriage of the Prophet ﷺ and Khadija رضي الله عنها',
    'Mariage du Prophète ﷺ et Khadija رضي الله عنها':
        'Marriage of the Prophet ﷺ and Khadija رضي الله عنها',
    'La participation du Prophète ﷺ à la reconstruction de la Kaaba avant la révélation':
        'The participation of the Prophet ﷺ in the reconstruction of the Kaaba before the revelation',
    'Le debut de la mission du Prophète ﷺ':
        'The beginning of the mission of the Prophet ﷺ',
    'le debut de la mission du Prophète ﷺ':
        'the beginning of the mission of the Prophet ﷺ',
    'Le debut de la revélation du Prophète ﷺ':
        'The beginning of the Revelation to the Prophet ﷺ',
    'Les périodes de la révélation': 'The periods of the Revelation',
    'Les différentes formes de la descente de la Révélation sur le Prophète ﷺ':
        'The different forms of the descent of the Revelation upon the Prophet ﷺ',
    "Les innovations dans la religion de l'Islam":
        'Innovations in the religion of Islam',
    "L'adulte du Prophète ﷺ": 'The adulthood of the Prophet ﷺ',
    // Titres d'audios Sidi Touré — traductions des sermons des Imams.
    'Sermon du vendredi — Cheikh Saoud Ibn Ibrahim Ash-Shuraim (traduit par Sidi Touré, session Ramadan)':
        'Friday sermon — Sheikh Saud Ibn Ibrahim Ash-Shuraim (translated by Sidi Touré, Ramadan session)',
    'Khoutba de Cheikh Abdrahman As-Soudais — Mawlid du Prophète ﷺ (traduit par Imam Sidi Aboubacar Touré)':
        'Khutbah of Sheikh Abdrahman As-Soudais — Mawlid of the Prophet ﷺ (translated by Imam Sidi Aboubacar Touré)',
    'Koutba de Cheikh KISHK — Traduction en Bamanakan par Sidi Touré (2)':
        'Khutbah of Sheikh KISHK — Translation into Bamanakan by Sidi Touré (2)',
    'Koutba de Cheikh KISHK — Les fitnah de nos jours (traduit par Sidi Touré)':
        'Khutbah of Sheikh KISHK — The trials (fitnah) of our time (translated by Sidi Touré)',
    'La mort en bambara — Partie 1 (Sidi Touré)':
        'Death in Bambara — Part 1 (Sidi Touré)',
    // Descriptions des prêcheurs.
    'Les enseignements de l’Imam Madou Koné sont dispensés dans différentes mosquées de Bamako selon le programme hebdomadaire. L’application IMMK permet de retrouver et d’écouter les différents enseignements : Sîra du Prophète ﷺ, Tafsir du Coran, vie des Compagnons du Prophète ﷺ et sermons.':
        'The teachings of Imam Madou Koné are given in different mosques of Bamako according to the weekly program. The IMMK app lets you find and listen to the various teachings: Seerah of the Prophet ﷺ, Quran tafsir, the life of the Companions of the Prophet ﷺ and sermons.',
    'Retrouvez ici les sermons et les enseignements de tafsir de l’Imam Abdoulaye Koïta.':
        'Find here the sermons and the tafsir teachings of Imam Abdoulaye Koïta.',
    'Retrouvez ici les sermons et les enseignements de tafsir de l’Imam Mahi Ouattara.':
        'Find here the sermons and the tafsir teachings of Imam Mahi Ouattara.',
    'Retrouvez ici les traductions des sermons des Imams de La Mecque et de Médine, le tafsir du Coran, la sîra du Prophète ﷺ et l’histoire des Khalifes.':
        'Find here the translations of the sermons of the Imams of Mecca and Medina, the tafsir of the Quran, the seerah of the Prophet ﷺ and the history of the Caliphs.',
  };

  /// Dictionnaire FR→AR des contenus.
  static const Map<String, String> _contentAr = {
    // Libellés courts des chips de recherche (doivent matcher le texte du
    // haystack localisé pour que le filtre fonctionne dans chaque langue).
    'Sîra': 'سيرة',
    'Coran': 'قرآن',
    'Compagnons': 'صحابة',
    // Catégories Imam Madou Koné.
    'Sermons': 'الخطب',
    'Khutbas et rappels': 'خطب وتذكيرات',
    'Lecture du Coran': 'قراءة القرآن',
    'Sourates et récitations': 'سور وتلاوات',
    'Tafsir du Coran': 'تفسير القرآن',
    'Explications des versets': 'تفسير الآيات',
    'Sîra du Prophète ﷺ': 'سيرة النبي ﷺ',
    'Vie et enseignements': 'السيرة والتعاليم',
    'La vie des Compagnons du Prophète ﷺ': 'حياة صحابة النبي ﷺ',
    'Furuso Duman': 'فوروسو دومان',
    // Catégories Koïta / Ouattara. « Tafsir » sans al- : forme courte qui
    // reste une sous-chaîne de « تفسير القرآن » pour le matching des chips.
    'Sermon': 'خطبة',
    'Sermons et prêches': 'خطب ومواعظ',
    'Tafsir': 'تفسير',
    'Explications et enseignements du Coran': 'تفاسير وتعاليم القرآن',
    // Catégories Sidi Toure.
    'Traductions des sermons des Imams de La Mecque et de Médine':
        'ترجمات خطب أئمة مكة والمدينة',
    'Traductions des sermons': 'ترجمات الخطب',
    "L'Histoire des Khalifes du Prophète ﷺ": 'تاريخ خلفاء النبي ﷺ',
    'Histoire des Khalifes': 'تاريخ الخلفاء',
    // Thème du programme.
    'Sermon / Khutba': 'خطبة',
    // Taglines des prêcheurs.
    'Prêches, Coran et enseignements': 'مواعظ وقرآن ودروس',
    'Sermons et tafsir du Coran': 'خطب وتفسير القرآن',
    'Traductions, tafsir, sîra et histoire des Khalifes':
        'ترجمات وتفسير وسيرة وتاريخ الخلفاء',
    // Jours du programme hebdomadaire.
    'Mardi': 'الثلاثاء',
    'Mercredi': 'الأربعاء',
    'Jeudi': 'الخميس',
    'Vendredi': 'الجمعة',
    'Samedi': 'السبت',
    'Dimanche': 'الأحد',
    // Horaires et lieux.
    'Entre Salat al-Maghrib et Salat al-Isha':
        'بين صلاة المغرب وصلاة العشاء',
    'Mosquée Ar-Rahma — Badalabougou': 'مسجد الرحمة — بادالابوغو',
    'Mosquée Ridwane — Kalaban-Coura': 'مسجد رضوان — كالابان كورا',
    'Mosquée Verte — Banankabougou': 'المسجد الأخضر — بانانكابوغو',
    'Mosquée Al-Imam Malik — Daoudabougou': 'مسجد الإمام مالك — داودابوغو',
    // Titres d'audios uniques (sermons).
    "La Grandeur d'Allah à travers sa création": 'عظمة الله في خلقه',
    "L'education de l'enfant": 'تربية الطفل',
    'Les bienfaiteurs': 'المحسنون',
    "Le bienfait d'Allah": 'نعمة الله',
    'Apres_la_mort': 'بعد الموت',
    'Notre_Environnement': 'بيئتنا',
    'Famille_musulmane': 'الأسرة المسلمة',
    'Le_droit_chemin': 'الصراط المستقيم',
    'Bientôt la rentree scolaire': 'قريباً موعد العودة إلى المدرسة',
    // Sujets de la série Sira (parties 1 à 14).
    "l'enfance du Prophète ﷺ": 'طفولة النبي ﷺ',
    "L'adolescence du Prophète ﷺ": 'مراهقة النبي ﷺ',
    'La connaissance entre leProphète ﷺ et khadija رضي الله عنها':
        'التعارف بين النبي ﷺ وخديجة رضي الله عنها',
    'Mariage du Prophète ﷺ et khadija رضي الله عنها':
        'زواج النبي ﷺ وخديجة رضي الله عنها',
    'Mariage du Prophète ﷺ et Khadija رضي الله عنها':
        'زواج النبي ﷺ وخديجة رضي الله عنها',
    'La participation du Prophète ﷺ à la reconstruction de la Kaaba avant la révélation':
        'مشاركة النبي ﷺ في إعادة بناء الكعبة قبل الوحي',
    'Le debut de la mission du Prophète ﷺ': 'بداية بعثة النبي ﷺ',
    'le debut de la mission du Prophète ﷺ': 'بداية بعثة النبي ﷺ',
    'Le debut de la revélation du Prophète ﷺ': 'بداية نزول الوحي على النبي ﷺ',
    'Les périodes de la révélation': 'فترات الوحي',
    'Les différentes formes de la descente de la Révélation sur le Prophète ﷺ':
        'الأشكال المختلفة لنزول الوحي على النبي ﷺ',
    "Les innovations dans la religion de l'Islam": 'البدع في دين الإسلام',
    "L'adulte du Prophète ﷺ": 'بلوغ النبي ﷺ',
    // Titres d'audios Sidi Touré — traductions des sermons des Imams.
    'Sermon du vendredi — Cheikh Saoud Ibn Ibrahim Ash-Shuraim (traduit par Sidi Touré, session Ramadan)':
        'خطبة الجمعة — الشيخ سعود بن إبراهيم الشريم (ترجمة سيدي توري، جلسة رمضان)',
    'Khoutba de Cheikh Abdrahman As-Soudais — Mawlid du Prophète ﷺ (traduit par Imam Sidi Aboubacar Touré)':
        'خطبة الشيخ عبد الرحمن السديس — المولد النبوي ﷺ (ترجمة الإمام سيدي أبو بكر توري)',
    'Koutba de Cheikh KISHK — Traduction en Bamanakan par Sidi Touré (2)':
        'خطبة الشيخ كشك — ترجمة إلى البامانكان بواسطة سيدي توري (٢)',
    'Koutba de Cheikh KISHK — Les fitnah de nos jours (traduit par Sidi Touré)':
        'خطبة الشيخ كشك — فتن زماننا (ترجمة سيدي توري)',
    'La mort en bambara — Partie 1 (Sidi Touré)':
        'الموت بالبمبارا — الجزء الأول (سيدي توري)',
    // Descriptions des prêcheurs.
    'Les enseignements de l’Imam Madou Koné sont dispensés dans différentes mosquées de Bamako selon le programme hebdomadaire. L’application IMMK permet de retrouver et d’écouter les différents enseignements : Sîra du Prophète ﷺ, Tafsir du Coran, vie des Compagnons du Prophète ﷺ et sermons.':
        'تُقدَّم دروس الإمام مادو كوني في مساجد مختلفة من باماكو وفق البرنامج الأسبوعي. يتيح تطبيق IMMK العثور على الدروس المختلفة والاستماع إليها: سيرة النبي ﷺ، تفسير القرآن، حياة صحابة النبي ﷺ والخطب.',
    'Retrouvez ici les sermons et les enseignements de tafsir de l’Imam Abdoulaye Koïta.':
        'ستجدون هنا خطب ودروس التفسير للإمام عبد الله كويتا.',
    'Retrouvez ici les sermons et les enseignements de tafsir de l’Imam Mahi Ouattara.':
        'ستجدون هنا خطب ودروس التفسير للإمام ماهي واتارا.',
    'Retrouvez ici les traductions des sermons des Imams de La Mecque et de Médine, le tafsir du Coran, la sîra du Prophète ﷺ et l’histoire des Khalifes.':
        'ستجدون هنا ترجمات خطب أئمة مكة والمدينة، وتفسير القرآن، وسيرة النبي ﷺ، وتاريخ الخلفاء.',
  };

  /// Mois français → anglais (pour les dates affichées).
  static const Map<String, String> _monthsEn = {
    'janvier': 'January',
    'février': 'February',
    'mars': 'March',
    'avril': 'April',
    'mai': 'May',
    'juin': 'June',
    'juillet': 'July',
    'août': 'August',
    'septembre': 'September',
    'octobre': 'October',
    'novembre': 'November',
    'décembre': 'December',
  };

  /// Mois français → arabe.
  static const Map<String, String> _monthsAr = {
    'janvier': 'يناير',
    'février': 'فبراير',
    'mars': 'مارس',
    'avril': 'أبريل',
    'mai': 'مايو',
    'juin': 'يونيو',
    'juillet': 'يوليو',
    'août': 'أغسطس',
    'septembre': 'سبتمبر',
    'octobre': 'أكتوبر',
    'novembre': 'نوفمبر',
    'décembre': 'ديسمبر',
  };

  static String get _lang => SettingsStore.instance.language;

  /// Traduit une chaîne de contenu stockée en français dans la langue active.
  /// En français, renvoie la chaîne d'origine (comportement inchangé).
  /// Gère les titres de séries numérotées (Sira, Compagnons, Furuso Duman)
  /// par motifs plutôt que par dictionnaire exhaustif.
  static String content(String fr) {
    if (fr.isEmpty) return fr;
    switch (_lang) {
      case 'en':
        return _contentEn[fr] ?? _seriesEn(fr) ?? fr;
      case 'ar':
        return _contentAr[fr] ?? _seriesAr(fr) ?? fr;
      default:
        return fr;
    }
  }

  static String? _seriesEn(String fr) => _translateSeries(fr, en: true);
  static String? _seriesAr(String fr) => _translateSeries(fr, en: false);

  /// Moteur de traduction par motifs pour les séries numérotées.
  static String? _translateSeries(String fr, {required bool en}) {
    final map = en ? _contentEn : _contentAr;

    // Sira Partie N : topic — ex. « Sira Partie 1 : l'enfance du Prophète ﷺ »,
    // « Sira Partie 133 suite: L'adulte du Prophète ﷺ ».
    final sira = RegExp(
      r'^Sira Partie\s+(\d+)\s*(suite)?\s*:?\s*(.*)$',
    ).firstMatch(fr);
    if (sira != null) {
      final n = sira.group(1)!;
      final suite = (sira.group(2) ?? '').trim().isNotEmpty;
      final rawTopic = sira.group(3)!.trim();
      final topic = rawTopic.isEmpty ? '' : (map[rawTopic] ?? rawTopic);
      final prefix = en ? 'Sira Part' : 'السيرة الجزء';
      final suffix = suite ? (en ? ' (continued)' : ' (تابع)') : '';
      return topic.isEmpty
          ? '$prefix $n$suffix'
          : '$prefix $n$suffix: $topic';
    }

    // Histoire des Khalifes du Prophète ﷺ Partie N : …
    final khalifes = RegExp(
      r'^Histoire des Khalifes\s+Partie\s+(\d+)\s*:?\s*(.*)$',
    ).firstMatch(fr);
    if (khalifes != null) {
      final n = khalifes.group(1)!;
      final rawTopic = khalifes.group(2)!.trim();
      final topic = rawTopic.isEmpty ? '' : (map[rawTopic] ?? rawTopic);
      final prefix = en
          ? 'History of the Caliphs Part'
          : 'تاريخ الخلفاء — الجزء';
      return topic.isEmpty
          ? '$prefix $n'
          : '$prefix $n: $topic';
    }

    // La vie des Compagnons du Prophète ﷺ Partie NN : …
    final comp = RegExp(
      r'^La vie des Compagnons du Prophète ﷺ\s+Partie\s+(\d+)\s*:?\s*(.*)$',
    ).firstMatch(fr);
    if (comp != null) {
      final n = comp.group(1)!;
      final rawTopic = comp.group(2)!.trim();
      final topic = rawTopic.isEmpty ? '' : (map[rawTopic] ?? rawTopic);
      final prefix = en
          ? 'The life of the Companions of the Prophet ﷺ Part'
          : 'حياة صحابة النبي ﷺ — الجزء';
      return topic.isEmpty
          ? '$prefix $n'
          : '$prefix $n: $topic';
    }

    // Furuso Duman partie NN : …
    final furuso = RegExp(
      r'^Furuso Duman\s+(?:partie|Partie)\s+(\d+)\s*:?\s*(.*)$',
    ).firstMatch(fr);
    if (furuso != null) {
      final n = furuso.group(1)!;
      final rawTopic = furuso.group(2)!.trim();
      final topic = rawTopic.isEmpty ? '' : (map[rawTopic] ?? rawTopic);
      final prefix = en ? 'Furuso Duman Part' : 'فوروسو دومان — الجزء';
      return topic.isEmpty
          ? '$prefix $n'
          : '$prefix $n: $topic';
    }

    return null;
  }

  /// Localise un mois seul (« août » → « August » / « أغسطس »).
  static String month(String fr) {
    final map = switch (_lang) {
      'en' => _monthsEn,
      'ar' => _monthsAr,
      _ => const <String, String>{},
    };
    return map[fr] ?? fr;
  }

  /// Traduit une date au format « 19 août 2026 » dans la langue active.
  static String date(String frDate) {
    if (frDate.isEmpty) return frDate;
    final parts = frDate.trim().split(RegExp(r'\s+'));
    if (parts.length != 3) return frDate;
    return '${parts[0]} ${month(parts[1])} ${parts[2]}';
  }

  /// Message d'accueil du prêcheur (tous sauf Imam Madou Koné).
  static String greetingFor(String name) =>
      t('home.greetingOther').replaceFirst('{name}', name);

  /// Libellé affiché d'un chip de recherche. La clé logique reste le texte
  /// français (catégorie ou « Favoris »), seule l'étiquette est traduite.
  static String chipLabel(String chip) => chip == 'Favoris'
      ? t('search.favoritesChip')
      : content(chip);

  /// Clé avec insertion d'un paramètre ({error}, {name}…).
  static String tArg(String key, String name, String value) =>
      t(key).replaceFirst('{$name}', value);

  /// Locale passée au moteur de dictée vocale.
  static String get speechLocale => switch (_lang) {
        'en' => 'en_US',
        'ar' => 'ar_SA',
        _ => 'fr_FR',
      };

  // -------------------------------------------------------------------------
  // Pluriels localisés (les données restent en français, le libellé se
  // construit dans la langue active). En français, le rendu est strictement
  // identique à l'existant.
  // -------------------------------------------------------------------------

  /// « 2 audios » / « 1 audio ».
  static String audioCount(int n) {
    switch (_lang) {
      case 'en':
        return n > 1 ? '$n audios' : '$n audio';
      case 'ar':
        return n > 1 ? '$n تسجيلات' : '$n تسجيل';
      default:
        return n > 1 ? '$n audios' : '$n audio';
    }
  }

  /// « 2 audios enregistrés » / « 1 audio enregistré ».
  static String audioRegistered(int n) {
    switch (_lang) {
      case 'en':
        return n > 1 ? '$n audios saved' : '$n audio saved';
      case 'ar':
        return n > 1 ? '$n تسجيلات محفوظة' : '$n تسجيل محفوظ';
      default:
        return n > 1 ? '$n audios enregistrés' : '$n audio enregistré';
    }
  }

  /// « 262 résultats » / « 1 résultat ».
  static String resultCount(int n) {
    switch (_lang) {
      case 'en':
        return n > 1 ? '$n results' : '$n result';
      case 'ar':
        return n > 1 ? '$n نتائج' : '$n نتيجة';
      default:
        return n > 1 ? '$n résultats' : '$n résultat';
    }
  }

  /// « 2 catégories » / « 1 catégorie ».
  static String categoryCount(int n) {
    switch (_lang) {
      case 'en':
        return n > 1 ? '$n categories' : '$n category';
      case 'ar':
        return n > 1 ? '$n فئات' : '$n فئة';
      default:
        return n > 1 ? '$n catégories' : '$n catégorie';
    }
  }
}

class ImamMadouKoneApp extends StatelessWidget {
  const ImamMadouKoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'Imam Madou Koné',
        debugShowCheckedModeBanner: false,
        themeMode: switch (SettingsStore.instance.themeMode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F1E8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F5F4D),
          primary: const Color(0xFF0F5F4D),
          secondary: const Color(0xFFDBB15F),
          tertiary: const Color(0xFFE7F0EC),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F5F4D),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F5F4D),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F5F4D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E1D6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E1D6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF0F5F4D), width: 1.5),
          ),
          hintStyle: const TextStyle(color: Color(0xFF7E857F)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFFEAF4F1),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C1F1E),
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C1F1E),
          ),
          titleMedium: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1C1F1E),
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1C1F1E),
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1C1F1E),
          ),
          bodyLarge: TextStyle(color: Color(0xFF3A423E), height: 1.5),
          bodyMedium: TextStyle(color: Color(0xFF3A423E), height: 1.45),
          bodySmall: TextStyle(color: Color(0xFF67706D), height: 1.3),
          labelLarge: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F5F4D),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFF0F5F4D),
          labelStyle: const TextStyle(
            color: Color(0xFF1C1F1E),
            fontWeight: FontWeight.w600,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          side: const BorderSide(color: Color(0xFFE5E1D6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C2E29),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0F5F4D),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E1A16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F5F4D),
          brightness: Brightness.dark,
          primary: const Color(0xFF57B6A0),
          secondary: const Color(0xFFDBB15F),
          tertiary: const Color(0xFF274139),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A332C),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Color(0xFF1B2E29),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF14251F),
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFF274139),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1B2E29),
          hintStyle: const TextStyle(color: Color(0xFF9EB0A9)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2E443C)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF2E443C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF57B6A0), width: 1.5),
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFFE9F0ED),
          ),
          headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFFE9F0ED),
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFFE9F0ED),
          ),
          titleMedium: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE9F0ED),
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFFE9F0ED),
          ),
          bodyLarge: TextStyle(color: Color(0xFFC9D6D1), height: 1.5),
          bodyMedium: TextStyle(color: Color(0xFFC9D6D1), height: 1.45),
          bodySmall: TextStyle(color: Color(0xFF9EB0A9), height: 1.3),
          labelLarge: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF57B6A0),
          ),
        ),
      ),
      locale: L10n.locale,
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PreacherSelectPage(),
    ),
  );
  }
}

class Category {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Image d'arrière-plan propre à cette catégorie (sinon dégradé par défaut).
  final String? backgroundAsset;

  const Category({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.backgroundAsset,
  });
}

class AudioItem {
  final String title;
  final String category;
  final String date;
  final String duration;
  final String description;
  final String audioAsset;

  const AudioItem({
    required this.title,
    required this.category,
    required this.date,
    required this.duration,
    required this.description,
    required this.audioAsset,
  });
}

const categories = [
  Category(
    title: 'Sermons',
    subtitle: 'Khutbas et rappels',
    icon: Icons.mic_rounded,
    color: Color(0xFFE7F2EE),
  ),
  Category(
    title: 'Lecture du Coran',
    subtitle: 'Sourates et récitations',
    icon: Icons.menu_book_rounded,
    color: Color(0xFFFFF2D9),
  ),
  Category(
    title: 'Tafsir du Coran',
    subtitle: 'Explications des versets',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFFEEEAF9),
  ),
  Category(
    title: 'Sîra du Prophète ﷺ',
    subtitle: 'Vie et enseignements',
    icon: Icons.mosque_rounded,
    color: Color(0xFFF8E8E8),
  ),
  Category(
    title: 'La vie des Compagnons du Prophète ﷺ',
    subtitle: 'Vie et enseignements',
    icon: Icons.groups_rounded,
    color: Color(0xFFDFF0F5),
  ),
  Category(
    title: 'Furuso Duman',
    subtitle: 'Vie et enseignements',
    icon: Icons.library_music_rounded,
    color: Color(0xFFFFE8D6),
  ),
];

const demoAudios = [
  AudioItem(
    title: 'Sira Partie 1 : l\'enfance du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '19 août 2026',
    duration: '42 min',
    description: '',
    audioAsset: 'Sira/01.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 2 : L\'adolescence du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '19 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/02.mp3',
  ),
  AudioItem(
    title:
        'Sira Partie 3 : La connaissance entre leProphète ﷺ et khadija رضي الله عنها',
    category: 'Sîra du Prophète ﷺ',
    date: '5 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/03.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 4 : Mariage du Prophète ﷺ et khadija رضي الله عنها',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/04.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 5 : Mariage du Prophète ﷺ et Khadija رضي الله عنها',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/05.mp3',
  ),
  AudioItem(
    title:
        'Sira Partie 6 : La participation du Prophète ﷺ à la reconstruction de la Kaaba avant la révélation',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/06.mp3',
  ),
  AudioItem(
    title:
        'Sira Partie 7 : La participation du Prophète ﷺ à la reconstruction de la Kaaba avant la révélation',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/07.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 8 : Le debut de la mission du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/08.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 9 : le debut de la mission du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/09.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 10 : Le debut de la revélation du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52 min',
    description: '',
    audioAsset: 'Sira/10.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 11 : Le debut de la revélation du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/11.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 12 : Les périodes de la révélation',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/12.mp3',
  ),
  AudioItem(
    title:
        'Sira Partie 13 : Les différentes formes de la descente de la Révélation sur le Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '32 min',
    description: '',
    audioAsset: 'Sira/13.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 14: Les innovations dans la religion de l\'Islam',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '57 min',
    description: '',
    audioAsset: 'Sira/14.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 15: L\'appel de la famille du Prophète ﷺ à l\'Islam',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/15.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 16: L\'appel de la famille du Prophète ﷺ à l\'Islam',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/16.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 17: La conversion de Abu Bakr رضي الله عنه à l\'Islam',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/17.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 18: La conversion de Abu Bakr رضي الله عنه à l\'Islam',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/18.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 19: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/19.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 20: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '44 min',
    description: '',
    audioAsset: 'Sira/20.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 21: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/21.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 22: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/22.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 23: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/23.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 24: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/24.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 25: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/25.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 26: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '60 min',
    description: '',
    audioAsset: 'Sira/26.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 27: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/27.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 28: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56 min',
    description: '',
    audioAsset: 'Sira/28.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 29: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/29.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 30: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/30.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 31: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54 min',
    description: '',
    audioAsset: 'Sira/31.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 32: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/32.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 33: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/33.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 34: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/34.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 35: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54 min',
    description: '',
    audioAsset: 'Sira/35.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 36: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/36.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 37: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/37.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 38: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/38.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 39: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/39.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 40: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '34 min',
    description: '',
    audioAsset: 'Sira/40.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 41: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/41.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 42: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/42.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 43: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/43.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 44: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52 min',
    description: '',
    audioAsset: 'Sira/44.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 45: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56 min',
    description: '',
    audioAsset: 'Sira/45.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 46: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/46.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 47: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '57 min',
    description: '',
    audioAsset: 'Sira/47.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 48: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54 min',
    description: '',
    audioAsset: 'Sira/48.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 49: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55 min',
    description: '',
    audioAsset: 'Sira/49.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 50: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/50.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 51: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52 min',
    description: '',
    audioAsset: 'Sira/51.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 52: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/52.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 53: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/53.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 54: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/54.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 55: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/55.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 56: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/56.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 57: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/57.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 58: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/58.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 59: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/59.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 60: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/60.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 61: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/61.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 62: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/62.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 63: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/63.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 64: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/64.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 65: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/65.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 66: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/66.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 67: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '21 min',
    description: '',
    audioAsset: 'Sira/67.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 68: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/68.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 69: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/69.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 70: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/70.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 71: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45 min',
    description: '',
    audioAsset: 'Sira/71.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 72: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52 min',
    description: '',
    audioAsset: 'Sira/72.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 73: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/73.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 74: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/74.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 75: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56 min',
    description: '',
    audioAsset: 'Sira/75.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 76: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '28 min',
    description: '',
    audioAsset: 'Sira/76.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 77: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/77.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 78: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/78.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 79: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/79.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 80: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/80.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 81: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48 min',
    description: '',
    audioAsset: 'Sira/81.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 82: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/82.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 83: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/83.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 84: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/84.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 85: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '53 min',
    description: '',
    audioAsset: 'Sira/85.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 86: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54 min',
    description: '',
    audioAsset: 'Sira/86.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 87: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '57 min',
    description: '',
    audioAsset: 'Sira/87.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 88: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/88.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 89: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55 min',
    description: '',
    audioAsset: 'Sira/89.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 90: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sira/90.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 91: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/91.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 92: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/92.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 93: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55 min',
    description: '',
    audioAsset: 'Sira/93.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 94: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47 min',
    description: '',
    audioAsset: 'Sira/94.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 95: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '49 min',
    description: '',
    audioAsset: 'Sira/95.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 96: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '46 min',
    description: '',
    audioAsset: 'Sira/96.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 97: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50 min',
    description: '',
    audioAsset: 'Sira/97.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 98: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '44 min',
    description: '',
    audioAsset: 'Sira/98.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 99: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51 min',
    description: '',
    audioAsset: 'Sira/99.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 100: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50min',
    description: '',
    audioAsset: 'Sira/100.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 101: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48min',
    description: '',
    audioAsset: 'Sira/101.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 102: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/102.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 103: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/103.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 104: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55min',
    description: '',
    audioAsset: 'Sira/104.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 105: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '58min',
    description: '',
    audioAsset: 'Sira/105.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 106: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sira/106.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 107: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54min',
    description: '',
    audioAsset: 'Sira/107.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 108: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56min',
    description: '',
    audioAsset: 'Sira/108.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 109: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/109.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 110: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56min',
    description: '',
    audioAsset: 'Sira/110.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 111: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51min',
    description: '',
    audioAsset: 'Sira/111.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 112: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '58min',
    description: '',
    audioAsset: 'Sira/112.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 113: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/113.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 114: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '58min',
    description: '',
    audioAsset: 'Sira/114.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 115: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '56min',
    description: '',
    audioAsset: 'Sira/115.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 116: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54min',
    description: '',
    audioAsset: 'Sira/116.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 117: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '51min',
    description: '',
    audioAsset: 'Sira/117.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 118: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '60min',
    description: '',
    audioAsset: 'Sira/118.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 119: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '54min',
    description: '',
    audioAsset: 'Sira/119.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 120: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '37min  ',
    description: '',
    audioAsset: 'Sira/120.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 121: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55min',
    description: '',
    audioAsset: 'Sira/121.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 122: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50min',
    description: '',
    audioAsset: 'Sira/122.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 123: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '57min',
    description: '',
    audioAsset: 'Sira/123.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 124: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48min',
    description: '',
    audioAsset: 'Sira/124.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 125: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '48min',
    description: '',
    audioAsset: 'Sira/125.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 126: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/126.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 127: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sira/127.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 128: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sira/128.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 129: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sira/129.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 130: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '44min',
    description: '',
    audioAsset: 'Sira/130.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 131: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '50min',
    description: '',
    audioAsset: 'Sira/131.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 132: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '59min',
    description: '',
    audioAsset: 'Sira/132.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 133: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '12min',
    description: '',
    audioAsset: 'Sira/133.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 133 suite: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '37min',
    description: '',
    audioAsset: 'Sira/f133.mp3',
  ),
AudioItem(
    title: 'Sira Partie 134: L\'adulte du Prophète ﷺ',
    category: 'Sîra du Prophète ﷺ',
    date: '12 août 2026',
    duration: '47min',
    description: '',
    audioAsset: 'Sira/134.mp3',
  ),
  // Les audios du categorie "la vie des compagnons du Prophète ﷺ"
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 01 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '55min',
    description: '',
    audioAsset: 'VCP/01.mp3',
  ),
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 02 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '59min',
    description: '',
    audioAsset: 'VCP/02.mp3',
  ),
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 03 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '60min',
    description: '',
    audioAsset: 'VCP/03.mp3',
  ),
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 04 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '58min',
    description: '',
    audioAsset: 'VCP/04.mp3',
  ),
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 05 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '60min',
    description: '',
    audioAsset: 'VCP/05.mp3',
  ),
  AudioItem(
    title: 'La vie des Compagnons du Prophète ﷺ Partie 06 :',
    category: 'La vie des Compagnons du Prophète ﷺ',
    date: '12 août 2026',
    duration: '60min',
    description: '',
    audioAsset: 'VCP/06.mp3',
  ),

  // Les audios du categorie "Sermons"
  AudioItem(
    title: "La Grandeur d'Allah à travers sa création",
    category: 'Sermons',
    date: '12 août 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sermons/grandeur_allah.mp3',
  ),
  AudioItem(
    title: "L'education de l'enfant",
    category: 'Sermons',
    date: '12 août 2026',
    duration: '46min',
    description: '',
    audioAsset: 'Sermons/education_enfant.mp3',
  ),
  AudioItem(
    title: 'Les bienfaiteurs',
    category: 'Sermons',
    date: '12 août 2026',
    duration: '59min',
    description: '',
    audioAsset: 'Sermons/bienfaiteurs.mp3',
  ),
  AudioItem(
    title: "Le bienfait d'Allah",
    category: 'Sermons',
    date: '12 août 2026',
    duration: '57min',
    description: '',
    audioAsset: 'Sermons/Le bienfait d\'Allah.mp3',
  ),
  AudioItem(
    title: "Apres_la_mort",
    category: 'Sermons',
    date: '17 septembre 2026',
    duration: '44min',
    description: '',
    audioAsset: 'Sermons/Apres_la_mort.mp3',
  ),
  AudioItem(
    title: "Notre_Environnement",
    category: 'Sermons',
    date: '17 septembre 2026',
    duration: '52min',
    description: '',
    audioAsset: 'Sermons/Notre_Environnement.mp3',
  ),
  AudioItem(
    title: "Famille_musulmane",
    category: 'Sermons',
    date: '17 septembre 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sermons/Famille_musulmane.mp3',
  ),
  AudioItem(
    title: "Le_droit_chemin",
    category: 'Sermons',
    date: '17 septembre 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sermons/Le_droit_chemin.mp3',
  ),
  AudioItem(
    title: "Bientôt la rentree scolaire",
    category: 'Sermons',
    date: '17 septembre 2026',
    duration: '45min',
    description: '',
    audioAsset: 'Sermons/Bientôt_la_rentrée_scolaire.mp3',
  ),
  AudioItem(
    title: 'Craignons Allah',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '44min',
    description: '',
    audioAsset: 'Sermons/Craignons Allah .mp3',
  ),
  AudioItem(
    title: 'La Palestine',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '40min',
    description: '',
    audioAsset: 'Sermons/La Palestine .mp3',
  ),
  AudioItem(
    title: 'Le bon accomplissement du Hadj',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '53min',
    description: '',
    audioAsset: 'Sermons/le bon accomplissement du Hadj .mp3',
  ),
  AudioItem(
    title: 'Le pèlerinage',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '41min',
    description: '',
    audioAsset: 'Sermons/Le pèlerinage .mp3',
  ),
  AudioItem(
    title: 'Le Ramadan est presque fini',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '53min',
    description: '',
    audioAsset: 'Sermons/Le Ramadan est presque fini .mp3',
  ),
  AudioItem(
    title: 'Le repentir',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '47min',
    description: '',
    audioAsset: 'Sermons/Le repentir .mp3',
  ),
  AudioItem(
    title: 'Les 10 derniers jours de Ramadan',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Sermons/Les 10 derniers jours de Ramadan .mp3',
  ),
  AudioItem(
    title: 'Les droits du voisinage',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '51min',
    description: '',
    audioAsset: 'Sermons/Les droits du voisinage .mp3',
  ),
  AudioItem(
    title: 'Signes de la fin des temps',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '28min',
    description: '',
    audioAsset: 'Sermons/Signes de la fin des temps .mp3',
  ),
  AudioItem(
    title: 'Toujours avoir bon espoir',
    category: 'Sermons',
    date: '4 octobre 2026',
    duration: '48min',
    description: '',
    audioAsset: 'Sermons/Toujours avoir bon espoir .mp3',
  ),
  // Les audios du categorie "Furuso Duman"

  AudioItem(
    title: 'Furuso Duman partie 01 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/01 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 02 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/02 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 03 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/03 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 04 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/04 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 05 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/05 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 06 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/06 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 07 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/07 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 08 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/08 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 09 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/09 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman Partie 10:',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/10 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 11 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/11 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 12 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/12 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 13 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/13 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 14 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/14 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 15 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/15 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 16 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/16 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 17 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/17 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 18 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/18 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 19 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/19 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 20 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/20 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 21 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/21 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 22 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/22 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 23 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/23 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 24 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/24 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 25 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/25 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 26 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/26 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 27 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/27 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 28 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/28 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 29 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/29 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 30 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/30 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 31 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/31 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 32 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/32 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 33 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/33 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 34 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/34 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 35 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/35 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 36 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/36 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 37 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/37 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 38 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/38 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 39 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/39 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 40 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/40 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 41 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/41 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 42 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/42 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 43 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/43 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 44 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/44 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 45 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/45 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 46 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/46 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 47 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/47 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 48 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/48 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 49 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/49 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 50 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/50 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 51 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/51 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 52 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/52 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 53 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/53 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 54 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/54 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 55 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/55 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 56 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/56 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 57 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/57 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 58 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/58 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 59 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/59 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 60 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/60 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 61 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/61 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 62 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/62 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 63 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/63 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 64 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/64 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 65 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/65 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 66 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/66 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 67 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/67 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 68 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/68 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 69 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/69 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 70 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/70 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 71 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/71 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 72 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/72 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 73 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/73 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 74 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/74 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 75 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/75 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 76 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/76 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 77 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/77 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 78 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/78 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 79 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/79 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 80 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/80 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 81 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/81 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 82 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/82 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 83 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/83 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 84 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/84 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 85 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/85 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 86 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/86 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 87 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/87 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 88 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/88 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 89 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/89 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 90 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/90 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 91 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/91 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 92 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/92 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 93 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/93 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 94 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/94 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 95 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/95 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 96 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/96 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 97 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/97 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 98 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/98 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 99 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/99 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 100 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/100 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 101 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/101 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 102  :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/102 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 103 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/103 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 104 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/104 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 105 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/105 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 106 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/106 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 107 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/107 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 108 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/108 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 109 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/109 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 110 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/110 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 111:',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/111 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 112 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/112 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 113 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/113 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 114 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/114 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 115 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/115 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 116 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/116 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 117 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/117 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 119 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/119 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 120 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/120 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 121 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/121 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 122 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/122 FD.mp3',
  ),
  AudioItem(
    title: 'Furuso Duman partie 125 :',
    category: 'Furuso Duman',
    date: '12 août 2026',
    duration: '30min',
    description: '',
    audioAsset: 'Furuso Duman/125 FD.mp3',
  ),
];

// ---------------------------------------------------------------------------
// Plateforme multi-prêcheurs
// ---------------------------------------------------------------------------

/// Profil d'un prêcheur de la plateforme.
///
/// Chaque compte possède ses propres catégories, audios, description, image
/// et coordonnées : les données ne sont jamais partagées entre prêcheurs.
/// Ajouter un nouveau prêcheur = ajouter une entrée dans la liste `preachers`.
class Preacher {
  final String id;
  final String name;
  final String tagline;
  final String description;
  final String? photoAsset;
  final List<Category> categories;
  final List<AudioItem> audios;
  final List<String>? searchChips;
  final String? whatsapp;

  /// Programme hebdomadaire (présent uniquement pour l'espace Imam Madou
  /// Koné pour l'instant).
  final List<ScheduleDay>? schedule;

  const Preacher({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.categories,
    required this.audios,
    this.photoAsset,
    this.searchChips,
    this.whatsapp,
    this.schedule,
  });
}

/// Compte historique de l'application : aucune donnée n'est perdue.
const imamMadouKone = Preacher(
  id: 'imam_madou_kone',
  name: 'Imam Madou Koné',
  tagline: 'Prêches, Coran et enseignements',
  description: 'Les enseignements de l’Imam Madou Koné sont dispensés dans '
      'différentes mosquées de Bamako selon le programme hebdomadaire. '
      'L’application IMMK permet de retrouver et d’écouter les différents '
      'enseignements : Sîra du Prophète ﷺ, Tafsir du Coran, vie des '
      'Compagnons du Prophète ﷺ et sermons.',
  photoAsset: 'assets/IMG/IMK_profil.png',
  categories: categories,
  audios: demoAudios,
  searchChips: [
    'Sermons',
    'Sîra',
    'Coran',
    'Tafsir',
    'Compagnons',
    'Furuso Duman',
    'Favoris',
  ],
  whatsapp: '+223 77 92 65 87',
  schedule: weekSchedule,
);

/// Espace indépendant : uniquement Sermon et Tafsir.
const aboulayeKoita = Preacher(
  id: 'imam_abdoulaye_koita',
  name: 'Imam Abdoulaye Koïta',
  tagline: 'Sermons et tafsir du Coran',
  description: 'Retrouvez ici les sermons et les enseignements de tafsir de '
      'l’Imam Abdoulaye Koïta.',
  photoAsset: 'assets/IMG/IAK.png',
  categories: [
    Category(
      title: 'Sermon',
      subtitle: 'Sermons et prêches',
      icon: Icons.mic_rounded,
      color: Color(0xFFE7F2EE),
      backgroundAsset: 'assets/IMG/IAK S.png',
    ),
    Category(
      title: 'Tafsir',
      subtitle: 'Explications et enseignements du Coran',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFEEEAF9),
      backgroundAsset: 'assets/IMG/IAK T.png',
    ),
  ],
  audios: [],
);

/// Espace indépendant : uniquement Sermon et Tafsir.
const mahiOuattara = Preacher(
  id: 'imam_mahi_ouattara',
  name: 'Imam Mahi Ouattara',
  tagline: 'Sermons et tafsir du Coran',
  description: 'Retrouvez ici les sermons et les enseignements de tafsir de '
      'l’Imam Mahi Ouattara.',
  photoAsset: 'assets/IMG/IMO.png',
  categories: [
    Category(
      title: 'Sermon',
      subtitle: 'Sermons et prêches',
      icon: Icons.mic_rounded,
      color: Color(0xFFE7F2EE),
      backgroundAsset: 'assets/IMG/IMO S.png',
    ),
    Category(
      title: 'Tafsir',
      subtitle: 'Explications et enseignements du Coran',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFEEEAF9),
      backgroundAsset: 'assets/IMG/IMO T.png',
    ),
  ],
  audios: [],
);

/// Série « Sîra du Prophète ﷺ » - Imam Sidi Touré (694 épisodes 001 à 694).
///
/// Fichiers servis depuis le serveur XAMPP (dossier Audios\IST Sira\) :
/// AUDIO_BASE_URL + IST Sira/0NN.mp3.
const sidiToureSiraAudios = <AudioItem>[
  AudioItem(
    title: 'Sira Partie 1',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/001.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 2',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/002.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 3',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/003.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 4',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/004.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 5',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/005.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 6',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/006.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 7',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/007.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 8',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/008.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 9',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/009.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 10',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/010.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 11',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/011.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 12',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/012.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 13',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/013.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 14',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/014.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 15',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/015.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 16',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/016.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 17',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/017.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 18',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/018.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 19',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/019.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 20',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/020.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 21',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/021.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 22',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/022.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 23',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/023.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 24',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/024.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 25',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/025.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 26',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/026.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 27',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/027.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 28',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/028.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 29',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/029.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 30',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/030.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 31',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/031.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 32',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/032.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 33',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/033.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 34',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/034.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 35',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/035.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 36',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/036.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 37',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/037.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 38',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/038.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 39',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/039.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 40',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/040.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 41',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/041.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 42',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/042.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 43',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/043.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 44',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/044.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 45',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/045.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 46',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/046.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 47',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/047.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 48',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/048.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 49',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/049.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 50',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/050.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 51',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/051.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 52',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/052.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 53',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/053.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 54',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/054.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 55',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/055.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 56',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/056.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 57',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/057.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 58',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/058.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 59',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/059.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 60',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/060.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 61',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/061.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 62',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/062.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 63',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/063.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 64',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/064.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 65',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/065.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 66',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/066.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 67',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/067.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 68',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/068.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 69',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/069.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 70',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/070.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 71',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/071.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 72',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/072.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 73',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/073.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 74',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/074.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 75',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/075.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 76',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/076.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 77',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/077.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 78',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/078.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 79',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/079.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 80',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/080.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 81',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/081.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 82',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/082.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 83',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/083.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 84',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/084.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 85',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/085.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 86',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/086.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 87',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/087.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 88',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/088.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 89',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/089.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 90',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/090.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 91',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/091.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 92',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/092.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 93',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/093.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 94',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/094.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 95',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/095.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 96',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/096.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 97',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/097.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 98',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/098.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 99',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/099.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 100',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/100.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 101',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/101.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 102',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/102.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 103',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/103.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 104',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/104.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 105',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/105.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 106',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/106.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 107',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/107.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 108',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/108.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 109',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/109.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 110',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/110.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 111',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/111.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 112',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/112.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 113',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/113.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 114',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/114.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 115',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/115.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 116',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/116.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 117',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/117.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 118',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/118.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 119',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/119.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 120',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/120.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 121',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/121.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 122',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/122.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 123',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/123.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 124',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/124.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 125',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/125.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 126',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/126.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 127',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/127.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 128',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/128.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 129',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/129.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 130',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/130.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 131',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/131.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 132',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/132.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 133',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/133.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 134',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/134.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 135',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/135.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 136',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/136.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 137',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/137.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 138',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/138.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 139',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/139.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 140',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/140.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 141',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/141.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 142',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/142.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 143',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/143.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 144',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/144.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 145',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/145.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 146',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/146.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 147',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/147.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 148',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/148.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 149',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/149.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 150',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/150.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 151',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/151.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 152',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/152.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 153',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/153.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 154',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/154.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 155',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/155.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 156',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/156.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 157',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/157.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 158',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/158.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 159',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/159.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 160',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/160.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 161',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/161.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 162',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/162.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 163',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/163.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 164',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/164.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 165',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/165.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 166',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/166.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 167',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/167.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 168',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/168.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 169',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/169.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 170',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/170.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 171',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/171.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 172',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/172.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 173',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/173.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 174',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/174.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 175',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/175.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 176',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/176.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 177',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/177.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 178',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/178.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 179',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/179.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 180',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/180.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 181',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/181.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 182',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/182.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 183',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/183.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 184',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/184.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 185',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/185.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 186',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/186.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 187',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/187.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 188',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/188.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 189',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/189.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 190',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/190.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 191',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/191.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 192',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/192.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 193',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/193.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 194',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/194.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 195',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/195.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 196',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/196.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 197',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/197.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 198',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/198.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 199',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/199.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 200',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/200.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 201',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/201.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 202',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/202.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 203',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/203.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 204',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/204.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 205',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/205.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 206',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/206.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 207',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/207.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 208',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/208.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 209',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/209.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 210',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/210.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 211',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/211.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 212',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/212.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 213',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/213.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 214',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/214.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 215',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/215.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 216',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/216.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 217',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/217.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 218',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/218.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 219',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/219.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 220',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/220.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 221',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/221.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 222',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/222.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 223',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/223.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 224',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/224.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 225',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/225.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 226',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/226.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 227',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/227.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 228',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/228.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 229',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/229.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 230',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/230.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 231',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/231.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 232',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/232.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 233',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/233.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 234',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/234.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 235',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/235.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 236',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/236.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 237',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/237.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 238',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/238.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 239',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/239.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 240',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/240.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 241',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/241.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 242',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/242.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 243',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/243.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 244',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/244.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 245',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/245.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 246',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/246.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 247',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/247.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 248',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/248.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 249',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/249.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 250',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/250.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 251',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/251.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 252',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/252.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 253',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/253.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 254',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/254.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 255',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/255.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 256',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/256.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 257',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/257.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 258',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/258.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 259',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/259.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 260',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/260.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 261',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/261.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 262',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/262.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 263',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/263.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 264',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/264.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 265',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/265.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 266',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/266.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 267',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/267.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 268',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/268.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 269',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/269.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 270',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/270.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 271',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/271.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 272',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/272.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 273',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/273.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 274',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/274.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 275',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/275.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 276',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/276.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 277',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/277.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 278',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/278.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 279',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/279.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 280',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/280.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 281',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/281.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 282',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/282.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 283',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/283.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 284',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/284.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 285',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/285.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 286',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/286.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 287',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/287.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 288',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/288.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 289',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/289.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 290',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/290.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 291',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/291.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 292',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/292.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 293',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/293.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 294',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/294.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 295',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/295.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 296',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/296.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 297',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/297.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 298',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/298.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 299',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/299.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 300',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/300.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 301',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/301.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 302',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/302.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 303',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/303.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 304',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/304.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 305',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/305.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 306',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/306.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 307',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/307.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 308',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/308.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 309',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/309.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 310',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/310.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 311',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/311.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 312',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/312.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 313',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/313.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 314',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/314.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 315',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/315.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 316',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/316.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 317',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/317.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 318',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/318.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 319',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/319.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 320',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/320.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 321',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/321.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 322',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/322.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 323',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/323.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 324',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/324.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 325',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/325.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 326',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/326.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 327',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/327.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 328',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/328.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 329',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/329.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 330',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/330.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 331',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/331.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 332',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/332.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 333',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/333.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 334',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/334.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 335',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/335.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 336',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/336.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 337',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/337.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 338',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/338.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 339',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/339.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 340',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/340.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 341',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/341.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 342',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/342.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 343',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/343.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 344',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/344.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 345',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/345.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 346',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/346.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 347',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/347.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 348',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/348.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 349',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/349.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 350',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/350.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 351',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/351.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 352',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/352.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 353',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/353.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 354',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/354.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 355',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/355.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 356',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/356.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 357',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/357.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 358',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/358.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 359',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/359.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 360',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/360.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 361',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/361.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 362',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/362.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 363',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/363.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 364',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/364.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 365',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/365.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 366',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/366.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 367',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/367.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 368',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/368.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 369',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/369.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 370',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/370.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 371',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/371.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 372',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/372.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 373',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/373.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 374',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/374.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 375',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/375.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 376',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/376.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 377',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/377.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 378',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/378.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 379',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/379.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 380',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/380.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 381',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/381.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 382',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/382.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 383',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/383.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 384',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/384.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 385',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/385.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 386',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/386.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 387',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/387.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 388',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/388.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 389',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/389.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 390',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/390.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 391',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/391.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 392',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/392.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 393',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/393.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 394',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/394.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 395',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/395.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 396',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/396.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 397',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/397.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 398',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/398.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 399',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/399.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 400',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/400.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 401',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/401.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 402',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/402.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 403',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/403.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 404',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/404.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 405',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/405.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 406',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/406.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 407',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/407.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 408',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/408.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 409',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/409.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 410',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/410.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 411',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/411.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 412',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/412.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 413',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/413.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 414',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/414.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 415',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/415.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 416',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/416.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 417',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/417.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 418',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/418.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 419',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/419.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 420',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/420.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 421',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/421.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 422',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/422.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 423',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/423.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 424',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/424.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 425',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/425.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 426',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/426.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 427',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/427.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 428',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/428.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 429',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/429.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 430',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/430.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 431',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/431.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 432',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/432.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 433',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/433.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 434',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/434.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 435',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/435.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 436',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/436.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 437',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/437.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 438',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/438.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 439',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/439.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 440',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/440.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 441',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/441.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 442',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/442.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 443',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/443.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 444',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/444.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 445',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/445.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 446',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/446.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 447',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/447.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 448',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/448.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 449',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/449.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 450',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/450.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 451',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/451.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 452',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/452.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 453',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/453.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 454',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/454.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 455',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/455.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 456',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/456.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 457',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/457.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 458',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/458.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 459',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/459.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 460',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/460.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 461',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/461.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 462',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/462.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 463',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/463.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 464',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/464.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 465',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/465.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 466',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/466.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 467',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/467.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 468',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/468.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 469',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/469.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 470',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/470.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 471',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/471.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 472',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/472.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 473',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/473.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 474',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/474.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 475',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/475.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 476',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/476.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 477',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/477.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 478',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/478.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 479',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/479.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 480',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/480.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 481',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/481.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 482',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/482.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 483',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/483.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 484',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/484.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 485',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/485.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 486',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/486.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 487',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/487.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 488',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/488.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 489',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/489.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 490',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/490.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 491',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/491.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 492',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/492.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 493',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/493.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 494',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/494.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 495',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/495.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 496',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/496.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 497',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/497.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 498',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/498.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 499',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/499.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 500',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/500.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 501',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/501.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 502',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/502.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 503',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/503.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 504',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/504.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 505',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/505.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 506',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/506.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 507',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/507.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 508',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/508.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 509',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/509.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 510',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/510.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 511',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/511.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 512',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/512.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 513',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/513.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 514',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/514.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 515',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/515.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 516',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/516.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 517',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/517.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 518',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/518.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 519',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/519.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 520',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/520.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 521',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/521.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 522',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/522.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 523',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/523.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 524',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/524.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 525',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/525.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 526',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/526.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 527',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/527.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 528',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/528.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 529',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/529.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 530',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/530.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 531',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/531.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 532',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/532.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 533',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/533.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 534',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/534.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 535',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/535.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 536',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/536.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 537',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/537.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 538',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/538.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 539',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/539.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 540',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/540.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 541',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/541.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 542',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/542.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 543',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/543.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 544',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/544.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 545',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/545.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 546',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/546.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 547',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/547.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 548',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/548.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 549',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/549.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 550',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/550.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 551',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/551.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 552',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/552.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 553',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/553.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 554',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/554.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 555',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/555.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 556',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/556.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 557',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/557.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 558',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/558.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 559',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/559.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 560',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/560.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 561',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/561.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 562',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/562.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 563',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/563.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 564',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/564.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 565',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/565.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 566',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/566.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 567',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/567.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 568',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/568.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 569',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/569.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 570',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/570.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 571',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/571.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 572',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/572.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 573',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/573.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 574',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/574.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 575',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/575.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 576',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/576.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 577',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/577.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 578',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/578.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 579',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/579.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 580',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/580.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 581',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/581.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 582',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/582.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 583',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/583.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 584',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/584.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 585',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/585.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 586',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/586.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 587',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/587.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 588',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/588.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 589',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/589.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 590',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/590.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 591',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/591.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 592',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/592.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 593',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/593.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 594',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/594.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 595',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/595.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 596',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/596.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 597',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/597.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 598',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/598.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 599',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/599.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 600',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/600.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 601',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/601.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 602',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/602.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 603',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/603.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 604',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/604.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 605',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/605.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 606',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/606.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 607',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/607.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 608',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/608.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 609',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/609.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 610',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/610.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 611',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/611.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 612',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/612.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 613',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/613.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 614',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/614.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 615',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/615.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 616',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/616.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 617',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/617.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 618',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/618.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 619',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/619.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 620',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/620.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 621',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/621.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 622',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/622.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 623',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/623.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 624',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/624.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 625',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/625.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 626',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/626.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 627',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/627.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 628',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/628.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 629',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/629.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 630',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/630.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 631',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/631.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 632',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/632.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 633',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/633.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 634',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/634.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 635',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/635.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 636',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/636.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 637',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/637.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 638',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/638.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 639',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/639.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 640',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/640.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 641',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/641.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 642',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/642.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 643',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/643.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 644',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/644.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 645',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/645.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 646',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/646.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 647',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/647.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 648',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/648.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 649',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/649.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 650',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/650.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 651',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/651.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 652',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/652.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 653',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/653.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 654',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/654.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 655',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/655.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 656',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/656.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 657',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/657.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 658',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/658.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 659',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/659.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 660',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/660.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 661',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/661.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 662',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/662.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 663',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/663.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 664',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/664.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 665',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/665.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 666',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/666.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 667',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/667.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 668',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/668.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 669',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/669.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 670',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/670.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 671',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/671.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 672',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/672.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 673',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/673.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 674',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/674.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 675',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/675.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 676',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/676.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 677',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/677.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 678',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/678.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 679',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/679.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 680',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/680.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 681',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/681.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 682',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/682.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 683',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/683.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 684',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/684.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 685',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/685.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 686',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/686.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 687',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/687.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 688',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/688.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 689',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/689.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 690',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/690.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 691',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/691.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 692',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/692.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 693',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/693.mp3',
  ),
  AudioItem(
    title: 'Sira Partie 694',
    category: 'Sîra du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Sira/694.mp3',
  ),
];

/// Série « Histoire des Khalifes du Prophète ﷺ » - Imam Sidi Touré (180 épisodes 001 à 180).
const sidiToureKhalifesAudios = [
  AudioItem(
    title: 'Histoire des Khalifes Partie 1',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/001.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 2',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/002.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 3',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/003.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 4',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/004.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 5',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/005.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 6',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/006.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 7',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/007.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 8',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/008.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 9',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/009.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 10',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/010.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 11',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/011.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 12',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/012.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 13',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/013.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 14',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/014.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 15',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/015.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 16',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/016.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 17',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/017.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 18',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/018.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 19',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/019.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 20',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/020.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 21',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/021.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 22',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/022.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 23',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/023.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 24',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/024.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 25',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/025.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 26',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/026.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 27',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/027.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 28',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/028.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 29',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/029.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 30',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/030.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 31',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/031.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 32',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/032.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 33',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/033.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 34',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/034.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 35',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/035.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 36',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/036.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 37',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/037.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 38',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/038.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 39',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/039.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 40',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/040.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 41',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/041.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 42',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/042.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 43',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/043.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 44',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/044.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 45',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/045.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 46',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/046.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 47',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/047.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 48',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/048.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 49',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/049.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 50',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/050.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 51',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/051.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 52',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/052.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 53',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/053.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 54',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/054.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 55',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/055.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 56',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/056.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 57',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/057.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 58',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/058.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 59',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/059.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 60',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/060.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 61',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/061.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 62',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/062.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 63',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/063.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 64',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/064.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 65',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/065.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 66',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/066.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 67',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/067.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 68',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/068.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 69',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/069.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 70',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/070.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 71',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/071.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 72',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/072.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 73',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/073.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 74',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/074.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 75',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/075.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 76',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/076.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 77',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/077.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 78',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/078.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 79',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/079.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 80',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/080.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 81',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/081.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 82',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/082.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 83',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/083.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 84',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/084.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 85',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/085.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 86',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/086.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 87',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/087.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 88',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/088.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 89',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/089.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 90',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/090.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 91',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/091.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 92',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/092.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 93',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/093.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 94',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/094.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 95',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/095.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 96',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/096.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 97',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/097.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 98',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/098.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 99',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/099.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 100',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/100.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 101',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/101.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 102',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/102.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 103',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/103.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 104',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/104.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 105',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/105.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 106',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/106.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 107',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/107.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 108',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/108.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 109',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/109.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 110',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/110.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 111',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/111.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 112',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/112.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 113',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/113.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 114',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/114.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 115',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/115.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 116',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/116.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 117',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/117.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 118',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/118.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 119',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/119.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 120',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/120.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 121',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/121.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 122',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/122.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 123',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/123.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 124',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/124.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 125',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/125.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 126',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/126.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 127',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/127.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 128',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/128.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 129',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/129.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 130',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/130.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 131',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/131.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 132',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/132.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 133',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/133.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 134',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/134.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 135',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/135.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 136',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/136.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 137',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/137.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 138',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/138.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 139',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/139.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 140',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/140.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 141',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/141.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 142',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/142.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 143',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/143.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 144',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/144.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 145',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/145.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 146',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/146.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 147',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/147.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 148',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/148.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 149',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/149.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 150',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/150.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 151',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/151.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 152',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/152.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 153',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/153.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 154',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/154.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 155',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/155.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 156',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/156.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 157',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/157.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 158',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/158.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 159',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/159.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 160',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/160.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 161',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/161.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 162',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/162.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 163',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/163.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 164',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/164.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 165',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/165.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 166',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/166.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 167',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/167.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 168',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/168.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 169',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/169.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 170',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/170.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 171',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/171.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 172',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/172.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 173',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/173.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 174',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/174.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 175',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/175.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 176',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/176.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 177',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/177.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 178',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/178.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 179',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/179.mp3',
  ),
  AudioItem(
    title: 'Histoire des Khalifes Partie 180',
    category: 'L\'Histoire des Khalifes du Prophète ﷺ',
    date: '',
    duration: '',
    description: '',
    audioAsset: 'IST Khalifes/180.mp3',
  ),
];

/// Traductions des sermons des Imams de La Mecque et de Médine - Imam Sidi
/// Touré (les fichiers sont hébergés dans le dossier `TST` du serveur).
const sidiToureTraductionsAudios = [
  AudioItem(
    title: 'Sermon du vendredi — Cheikh Saoud Ibn Ibrahim Ash-Shuraim '
        '(traduit par Sidi Touré, session Ramadan)',
    category: 'Traductions des sermons des Imams de La Mecque et de Médine',
    date: '10 octobre 2026',
    duration: '53 min',
    description: '',
    audioAsset:
        'TST/cheikh saoud Ibn Ibrahim shuraim sermon du vendredi traduit par sidi Touré ramadan session.mp3',
  ),
  AudioItem(
    title: 'Khoutba de Cheikh Abdrahman As-Soudais — Mawlid du Prophète ﷺ '
        '(traduit par Imam Sidi Aboubacar Touré)',
    category: 'Traductions des sermons des Imams de La Mecque et de Médine',
    date: '10 octobre 2026',
    duration: '8 min',
    description: '',
    audioAsset:
        'TST/Khoutba de Sheykh Abdrahman As Soudais traduit par Imam Sidi Aboubacar Touré  Mawlid du Prophète.mp3',
  ),
  AudioItem(
    title: 'Koutba de Cheikh KISHK — Traduction en Bamanakan par Sidi Touré (2)',
    category: 'Traductions des sermons des Imams de La Mecque et de Médine',
    date: '10 octobre 2026',
    duration: '2 h 03 min',
    description: '',
    audioAsset:
        'TST/Koutouba de KISHK traduction en Bamanakan par SIDI TOURE 2.mp3',
  ),
  AudioItem(
    title: 'Koutba de Cheikh KISHK — Les fitnah de nos jours '
        '(traduit par Sidi Touré)',
    category: 'Traductions des sermons des Imams de La Mecque et de Médine',
    date: '10 octobre 2026',
    duration: '22 min',
    description: '',
    audioAsset:
        'TST/Kutba KISHK traduit par SIDI TOURE- les fitnah de nos jours.mp3',
  ),
  AudioItem(
    title: 'La mort en bambara — Partie 1 (Sidi Touré)',
    category: 'Traductions des sermons des Imams de La Mecque et de Médine',
    date: '10 octobre 2026',
    duration: '1 h 01 min',
    description: '',
    audioAsset: 'TST/sidy toure la mort en bambara part 1.mp3',
  ),
];

/// Quatre catégories qui lui sont propres.
const sidiToure = Preacher(
  id: 'imam_sidi_toure',
  name: 'Imam Sidi Toure',
  tagline: 'Traductions, tafsir, sîra et histoire des Khalifes',
  description: 'Retrouvez ici les traductions des sermons des Imams de La '
      'Mecque et de Médine, le tafsir du Coran, la sîra du Prophète ﷺ et '
      'l’histoire des Khalifes.',
  photoAsset: 'assets/IMG/IST.png',
  categories: [
    Category(
      title: 'Traductions des sermons des Imams de La Mecque et de Médine',
      subtitle: 'Traductions des sermons',
      icon: Icons.mic_rounded,
      color: Color(0xFFE7F2EE),
      backgroundAsset: 'assets/IMG/IST S.png',
    ),
    Category(
      title: 'Tafsir du Coran',
      subtitle: 'Explications et enseignements du Coran',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFEEEAF9),
      backgroundAsset: 'assets/IMG/IST T.png',
    ),
    Category(
      title: 'Sîra du Prophète ﷺ',
      subtitle: 'Vie et enseignements',
      icon: Icons.mosque_rounded,
      color: Color(0xFFF8E8E8),
      backgroundAsset: 'assets/IMG/IST SR.png',
    ),
    Category(
      title: 'L\'Histoire des Khalifes du Prophète ﷺ',
      subtitle: 'Histoire des Khalifes',
      icon: Icons.account_balance_rounded,
      color: Color(0xFFFFE8D6),
      backgroundAsset: 'assets/IMG/IST C.png',
    ),
  ],
  audios: [
    ...sidiToureTraductionsAudios,
    ...sidiToureSiraAudios,
    ...sidiToureKhalifesAudios,
  ],
);

/// Tous les prêcheurs disponibles sur la plateforme.
const preachers = [imamMadouKone, aboulayeKoita, mahiOuattara, sidiToure];

/// Page « Accueil Général » : sélection du prêcheur à écouter.
class PreacherSelectPage extends StatelessWidget {
  const PreacherSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(isWide ? 26 : 18),
          children: [
            FadeSlideIn(
              child: Container(
                padding: EdgeInsets.all(isWide ? 28 : 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [
                      Color(0xFF072F2B),
                      Color(0xFF0F5F4D),
                      Color(0xFF1C7A68),
                    ],
                    begin: _gBegin(context),
                    end: _gEnd(context),
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.auto_stories_rounded,
                      color: Color(0xFFDBB15F),
                      size: 46,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      L10n.t('preachers.badge'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t('preachers.subtitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              delayMs: 80,
              child: Text(
                L10n.t('preachers.select'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: mainText(context),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ...preachers.indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  delayMs: 140 + entry.$1 * 70,
                  offset: const Offset(0, 12),
                  child: PressScale(
                    child: _PreacherProfileCard(preacher: entry.$2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de profil d'un prêcheur sur la page de sélection.
class _PreacherProfileCard extends StatelessWidget {
  final Preacher preacher;

  const _PreacherProfileCard({required this.preacher});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        splashColor: const Color(0x0D0F5F4D),
        highlightColor: const Color(0x080F5F4D),
        onTap: () {
          Navigator.push(
            context,
            animatedPageRoute<void>(MainShell(preacher: preacher)),
          );
        },
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardSurface(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8E2D8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F5F4D),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _PreacherAvatar(preacher: preacher, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preacher.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.content(preacher.tagline),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: subText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _isRTL(context)
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: const Color(0xFF95A09B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar d'un prêcheur : photo de profil si disponible, sinon médaillon
/// doré avec les initiales du nom.
class _PreacherAvatar extends StatelessWidget {
  final Preacher preacher;
  final double size;

  const _PreacherAvatar({required this.preacher, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final photo = preacher.photoAsset;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFDBB15F),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: photo != null
            ? Image.asset(photo, fit: BoxFit.cover)
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF0F5F4D), Color(0xFF1C7A68)],
                    begin: _gBegin(context),
                    end: _gEnd(context),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(preacher.name),
                  style: TextStyle(
                    color: const Color(0xFFF5E9CE),
                    fontSize: size * 0.32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
      ),
    );
  }

  /// Initiales du prêcheur (ex. « Imam Mahi Ouattara » → MO).
  static String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String firstOf(String w) => w.substring(0, 1).toUpperCase();
    if (words.length == 1) return firstOf(words.first);
    if (words.length == 2) return '${firstOf(words[0])}${firstOf(words[1])}';
    // « Imam Madou Koné » → MK : on saute le titre « Imam ».
    return '${firstOf(words[1])}${firstOf(words.last)}';
  }
}

/// Bouton retour : ramène d'un espace personnel à la sélection du prêcheur
/// (ou d'une page imbriquée à l'écran précédent).
class _BackArrowButton extends StatelessWidget {
  final String? tooltip;

  const _BackArrowButton({this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: Icon(
        _isRTL(context)
            ? Icons.arrow_forward_rounded
            : Icons.arrow_back_rounded,
      ),
      color: Colors.white,
      tooltip: tooltip ?? L10n.t('common.back'),
    );
  }
}

// ---------------------------------------------------------------------------
// Animations et transitions partagées
// ---------------------------------------------------------------------------

/// Route d'application : fondu + léger glissement vers le haut.
///
/// Remplace `MaterialPageRoute` pour donner une transition cohérente et douce
/// à toutes les pages poussées (lecteur, catégories, paramètres, à propos).
/// ⏸️ COMMUTATEUR TEMPORAIRE DE TEST — ANIMATIONS DE L'INTERFACE.
///
/// Mis à `false` pour naviguer instantanément dans les listes (notamment les
/// 400 épisodes de la Sîra de l'Imam Sidi Touré) : plus de fondu/glissement
/// en cascade, plus de zoom à la pression, transitions de page immédiates.
/// Remettre à `true` pour réactiver le système d'animations.
const bool kAnimationsEnabled = false;

Route<T> animatedPageRoute<T>(Widget page) {
  if (!kAnimationsEnabled) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.045),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Entrée en fondu + glissement, une seule fois au montage.
///
/// Sert aux blocs visuels (bannières, titres, cartes) : chaque instance ne
/// joue son animation qu'à son insertion, sans redémarrage lors des
/// reconstructions du parent (changement de thème, de langue…).
/// Le délai est appliqué par courbe `Interval` (aucun `Timer`, compatible
/// avec les tests) pour produire un effet en cascade.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.duration = const Duration(milliseconds: 480),
    this.offset = const Offset(0, 16),
  });

  final Widget child;
  final int delayMs;
  final Duration duration;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  Animation<Offset>? _slide;

  @override
  void initState() {
    super.initState();
    if (!kAnimationsEnabled) return;
    final total =
        widget.duration + Duration(milliseconds: widget.delayMs);
    _controller = AnimationController(vsync: this, duration: total);
    final start = (widget.delayMs / total.inMilliseconds).clamp(0.0, 0.92);
    final curve = CurvedAnimation(
      parent: _controller!,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
    _slide =
        Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(curve);
    _controller!.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return FadeTransition(
      opacity: _opacity!,
      child: SlideTransition(position: _slide!, child: widget.child),
    );
  }
}

/// Léger zoom de pression sur n'importe quelle carte interactive.
///
/// Posé autour d'un `InkWell` via un `Listener` (qui n'entre pas en
/// concurrence avec la gestuelle), il donne un retour tactile immédiat sans
/// toucher à l'opacité : les éléments restent visibles et testables à tout
/// moment.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.975,
  });

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!kAnimationsEnabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.preacher});

  final Preacher preacher;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  Widget _pageFor(int index) {
    return switch (index) {
      0 => HomePage(preacher: widget.preacher),
      1 => AudioLibraryPage(preacher: widget.preacher),
      2 => SearchPage(preacher: widget.preacher),
      _ => AboutPage(preacher: widget.preacher),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _pageFor(_selectedIndex),
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: SettingsStore.instance,
        builder: (context, _) => NavigationBar(
          height: 74,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: L10n.t('nav.home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.headphones_outlined),
              selectedIcon: const Icon(Icons.headphones_rounded),
              label: L10n.t('nav.audios'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.search_rounded),
              label: L10n.t('nav.search'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.info_outline_rounded),
              selectedIcon: const Icon(Icons.info_rounded),
              label: L10n.t('nav.about'),
            ),
          ],
        ),
      ),
    );
  }
}

class AudioLibraryPage extends StatelessWidget {
  const AudioLibraryPage({super.key, required this.preacher});

  final Preacher preacher;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final audio in preacher.audios) {
      counts[audio.category] = (counts[audio.category] ?? 0) + 1;
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF0E4C42), Color(0xFF1C7A68)],
                    begin: _gBegin(context),
                    end: _gEnd(context),
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BackArrowButton(tooltip: L10n.t('common.backToSelection')),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.headphones_rounded,
                      color: Color(0xFFDBB15F),
                      size: 34,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t('library.title'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            L10n.t('library.heroSub'),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ListenableBuilder(
              listenable: FavoritesStore.instance,
              builder: (context, _) {
                final favorites = preacher.audios
                    .where(
                      (a) => FavoritesStore.instance.containsFor(
                        preacher,
                        a.audioAsset,
                      ),
                    )
                    .toList();

                if (favorites.isEmpty) {
                  return const SizedBox.shrink();
                }

                return FadeSlideIn(
                  delayMs: 60,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.t('library.favorites'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: mainText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.audioRegistered(favorites.length),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF66736D),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...favorites.map(
                        (audio) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AudioTile(
                            audio: audio,
                            preacher: preacher,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              delayMs: 100,
              child: Text(
                L10n.t('library.categories'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: mainText(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...preacher.categories.indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  delayMs: 140 + entry.$1 * 60,
                  offset: const Offset(0, 12),
                  child: _CategoryListItem(
                    category: entry.$2,
                    count: counts[entry.$2.title] ?? 0,
                    preacher: preacher,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            FadeSlideIn(
              delayMs: 200,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardSurface(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE7E0D4)),
                ),
                child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: Color(0xFFDBB15F),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      L10n.t('library.tip'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1F241F),
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryListItem extends StatelessWidget {
  final Category category;
  final int count;
  final Preacher preacher;

  const _CategoryListItem({
    required this.category,
    required this.count,
    required this.preacher,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              animatedPageRoute<void>(
                CategoryPage(
                  categoryName: category.title,
                  preacher: preacher,
                ),
              ),
            );
          },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E0D4)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(category.icon, color: const Color(0xFF0F5F4D)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.content(category.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? L10n.t('category.comingSoon')
                          : L10n.audioCount(count),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF66736D),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _isRTL(context)
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: const Color(0xFF95A09B),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.preacher});

  final Preacher preacher;

  @override
  Widget build(BuildContext context) {
    final latestAudio = preacher.audios.isEmpty ? null : preacher.audios.first;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000 ? 3 : 2;

            return SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 36 : 20,
                      20,
                      isWide ? 36 : 20,
                      30,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: const [
                          Color(0xFF072F2B),
                          Color(0xFF0F5F4D),
                          Color(0xFF1C7A68),
                        ],
                        begin: _gBegin(context),
                        end: _gEnd(context),
                      ),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _BackArrowButton(
                              tooltip: L10n.t('common.backToSelection'),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                L10n.t('home.official'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            _SettingsButton(preacher: preacher),
                          ],
                        ),
                        const SizedBox(height: 24),
                        FadeSlideIn(
                          child: Row(
                            children: [
                              _PreacherAvatar(
                                preacher: preacher,
                                size: isWide ? 84 : 72,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preacher.name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isWide ? 28 : 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      L10n.content(preacher.tagline),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delayMs: 90,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              preacher == imamMadouKone
                                  ? L10n.t('home.greeting')
                                  : L10n.greetingFor(preacher.name),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(isWide ? 24 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeSlideIn(
                          delayMs: 120,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                L10n.t('home.explore'),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: mainText(context),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF6F3),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  L10n.categoryCount(preacher.categories.length),
                                  style: TextStyle(
                                    color: Color(0xFF0F5F4D),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: preacher.categories.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 1.05,
                              ),
                          itemBuilder: (context, index) {
                            final category = preacher.categories[index];

                            return FadeSlideIn(
                              delayMs: 180 + index * 60,
                              offset: const Offset(0, 12),
                              child: PressScale(
                                child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                splashColor: const Color(0x0D0F5F4D),
                                highlightColor: const Color(0x080F5F4D),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    animatedPageRoute<void>(
                                      CategoryPage(
                                        categoryName: category.title,
                                        preacher: preacher,
                                      ),
                                    ),
                                  );
                                },
                                child: Ink(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cardSurface(context),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: const Color(0xFFE8E2D8),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x1A0F5F4D),
                                        blurRadius: 10,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          color: category.color,
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          category.icon,
                                          size: 25,
                                          color: const Color(0xFF0F5F4D),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        L10n.content(category.title),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          height: 1.25,
                                          fontWeight: FontWeight.w700,
                                          color: mainText(context),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        L10n.content(category.subtitle),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.3,
                                          color: subText(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                          },
                        ),
                        const SizedBox(height: 26),
                        if (latestAudio != null) ...[
                          FadeSlideIn(
                            delayMs: 160,
                            child: Text(
                              L10n.t('home.latest'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: mainText(context),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delayMs: 220,
                            offset: const Offset(0, 12),
                            child: PressScale(
                              child: AudioTile(
                                audio: latestAudio,
                                preacher: preacher,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class CategoryPage extends StatelessWidget {
  final String categoryName;
  final Preacher preacher;

  const CategoryPage({
    super.key,
    required this.categoryName,
    required this.preacher,
  });

  @override
  Widget build(BuildContext context) {
    final audios = preacher.audios
        .where((audio) => audio.category == categoryName)
        .toList();

    Category? category;
    for (final c in preacher.categories) {
      if (c.title == categoryName) {
        category = c;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: const _BackArrowButton(),
        title: Text(L10n.content(categoryName)),
        actions: [_SettingsButton(preacher: preacher)],
      ),
      body: Container(
        color: pageSurface(context),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: category?.backgroundAsset != null
                      ? null
                      : LinearGradient(
                          colors: const [Color(0xFF0E4C42), Color(0xFF176D5E)],
                          begin: _gBegin(context),
                          end: _gEnd(context),
                        ),
                  image: category?.backgroundAsset != null
                      ? DecorationImage(
                          image: AssetImage(category!.backgroundAsset!),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.black.withValues(alpha: 0.35),
                            BlendMode.darken,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        category?.icon ?? Icons.library_music_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t('category.collection'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            L10n.content(categoryName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${L10n.audioCount(audios.length)}'
                            '${category != null ? ' · ${L10n.content(category.subtitle)}' : ''}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (audios.isEmpty)
              FadeSlideIn(
                delayMs: 140,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 48,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: category?.color ?? const Color(0xFFE7F2EE),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          category?.icon ?? Icons.audio_file_rounded,
                          size: 38,
                          color: const Color(0xFF0F5F4D),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        L10n.t('category.empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: subText(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...audios.indexed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FadeSlideIn(
                    delayMs: 140 + entry.$1 * 60,
                    offset: const Offset(0, 12),
                    child: AudioTile(
                      audio: entry.$2,
                      preacher: preacher,
                      locked: isAudioLockedForUser(
                        category: categoryName,
                        positionInCategory: entry.$1,
                      ),
                      positionInCategory: entry.$1 + 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Image d'arrière-plan d'une catégorie : on privilégie le fond propre
/// défini sur la catégorie du prêcheur, sinon le mapping historique.
String getCategoryBackgroundAsset(Preacher preacher, String category) {
  for (final c in preacher.categories) {
    final bg = c.backgroundAsset;
    if (bg != null && c.title == category) return bg;
  }
  switch (category) {
    case 'Sîra du Prophète ﷺ':
      return 'assets/IMG/Sira Imqge.png';
    case 'Tafsir du Coran':
      return 'assets/IMG/Tafsir.png';
    case 'La vie des Compagnons du Prophète ﷺ':
      return 'assets/IMG/La vie des compagnos du prophête   .png';
    case 'Sermons':
      return 'assets/IMG/Khutbas du vendredi.png';
    default:
      return 'assets/IMG/Khutbas du vendredi.png';
  }
}

class AudioTile extends StatelessWidget {
  final AudioItem audio;
  final Preacher preacher;
  final bool locked;
  final int positionInCategory;

  const AudioTile({
    super.key,
    required this.audio,
    required this.preacher,
    this.locked = false,
    this.positionInCategory = 0,
  });

  Color _categoryColor() {
    for (final c in preacher.categories) {
      if (c.title == audio.category) return c.color;
    }
    return const Color(0xFFE7F2EE);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor();

    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (locked) {
              showLockedDialog(context);
              return;
            }
            Navigator.push(
              context,
              animatedPageRoute<void>(
                AudioPlayerPage(audio: audio, preacher: preacher),
              ),
            );
          },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardSurface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E0D4)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F5F4D),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF0F5F4D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.content(audio.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (audio.date.trim().isNotEmpty)
                      Text(
                        '${L10n.content(audio.category)} · '
                            '${L10n.date(audio.date)}',
                        style: const TextStyle(
                          color: Color(0xFF66736D),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (audio.duration.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2EEE6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    audio.duration,
                    style: const TextStyle(
                      color: Color(0xFF55625C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: FavoritesStore.instance,
                builder: (context, _) {
                  final isFavorite = FavoritesStore.instance.containsFor(
                    preacher,
                    audio.audioAsset,
                  );
                  return SizedBox(
                    width: 38,
                    height: 38,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: isFavorite
                          ? L10n.t('favorites.remove')
                          : L10n.t('favorites.add'),
                      onPressed: () => FavoritesStore.instance.toggleFor(
                        preacher,
                        audio.audioAsset,
                      ),
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFavorite
                            ? const Color(0xFFD9534F)
                            : const Color(0xFF93A09A),
                        size: 21,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: isFavorite
                            ? const Color(0xFFFFECE9)
                            : const Color(0xFFF2EEE6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0F5F4D),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class AudioPlayerPage extends StatefulWidget {
  final AudioItem audio;
  final Preacher preacher;

  const AudioPlayerPage({
    super.key,
    required this.audio,
    required this.preacher,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = true;
  bool _isBuffering = false;
  String? _errorMessage;
  late double _speed;

  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    // Vitesse par défaut choisie dans les réglages de l'application.
    _speed = SettingsStore.instance.defaultSpeed;
    WidgetsBinding.instance.addObserver(this);
    _prepareAudio();

    _player.durationStream.listen((duration) {
      if (mounted && duration != null) {
        setState(() => _duration = duration);
      }
    });

    _player.positionStream.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isBuffering = state.processingState == ProcessingState.buffering;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // « Lecture en arrière-plan » désactivée dans les réglages :
    // on met en pause dès que l'application n'est plus au premier plan.
    if (!SettingsStore.instance.backgroundPlayback &&
        state != AppLifecycleState.resumed) {
      _player.pause();
    }
  }

  Future<void> _prepareAudio() async {
    // Les contrôles média (notification d'écran verrouillé) ne sont ajoutés
    // que si l'utilisateur les a activés dans les réglages.
    final showMediaControls = SettingsStore.instance.mediaNotifications;
    try {
      final xamppBaseUrl = kAudioBaseUrl;

      final relativePath = widget.audio.audioAsset
          .trim()
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');

      // Encode chaque partie du chemin séparément.
      // Exemple :
      // Furuso Duman/01 FD.mp3
      // devient :
      // Furuso%20Duman/01%20FD.mp3
      final encodedPath = relativePath
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');

      final audioUrl = '$xamppBaseUrl/$encodedPath';

      debugPrint('🎵 Audio URL : $audioUrl');

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(audioUrl),
          tag: showMediaControls
              ? MediaItem(
                  id: audioUrl,
                  album: L10n.content(widget.audio.category),
                  title: L10n.content(widget.audio.title),
                  artist: widget.preacher.name,
                )
              : null,
        ),
      );

      if (!mounted) return;

      // Applique la vitesse par défaut choisie dans les réglages.
      try {
        await _player.setSpeed(_speed);
      } catch (error) {
        debugPrint('⚠️ Vitesse par défaut non appliquée : $error');
      }

      // Reprise automatique là où l'écoute s'était arrêtée
      // (activée dans les réglages par défaut).
      if (SettingsStore.instance.resumeEnabled) {
        try {
          final saved = await _savedPosition(widget.audio.audioAsset);
          if (saved != null && saved > Duration.zero) {
            await _player.seek(saved);
          }
        } catch (_) {
          // La reprise est un bonus : une erreur ici ne bloque pas la lecture.
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (networkError) {
      debugPrint('❌ Erreur réseau (URL) : $networkError');
      // Repli : si le fichier audio est embarqué dans les assets
      // (lecture hors ligne), on le joue localement au lieu d'échouer.
      try {
        final assetPath =
            'assets/${widget.audio.audioAsset.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')}';

        debugPrint('🎵 Repli sur l’asset local : $assetPath');

        await _player.setAudioSource(
          AudioSource.asset(
            assetPath,
            tag: showMediaControls
                ? MediaItem(
                    id: assetPath,
                    album: L10n.content(widget.audio.category),
                    title: L10n.content(widget.audio.title),
                    artist: widget.preacher.name,
                  )
                : null,
          ),
        );

        if (!mounted) return;

        try {
          await _player.setSpeed(_speed);
        } catch (error) {
          debugPrint('⚠️ Vitesse par défaut non appliquée : $error');
        }

        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      } catch (_) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _errorMessage = L10n.tArg(
            'player.loadErrorDetail',
            'error',
            networkError.toString(),
          );
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Future<void> _seekRelative(int seconds) async {
    final newPosition = _position + Duration(seconds: seconds);

    if (newPosition < Duration.zero) {
      await _player.seek(Duration.zero);
    } else if (newPosition > _duration) {
      await _player.seek(_duration);
    } else {
      await _player.seek(newPosition);
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = L10n.tArg(
            'player.playError',
            'error',
            error.toString(),
          );
        });
      }
    }
  }

  Future<void> _restart() async {
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> _cycleSpeed() async {
    final index = _speedOptions.indexOf(_speed);
    final next = _speedOptions[(index + 1) % _speedOptions.length];
    setState(() => _speed = next);
    try {
      await _player.setSpeed(next);
    } catch (error) {
      debugPrint('⚠️ Changement de vitesse impossible : $error');
    }
  }

  String get _speedLabel => _speed == 1.0 ? '1×' : '$_speed×';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Mémorise la position de lecture pour pouvoir reprendre plus tard
    // (uniquement si l'audio a réellement été écouté un minimum et que
    // la reprise automatique est activée dans les réglages).
    if (SettingsStore.instance.resumeEnabled &&
        _position > const Duration(seconds: 10)) {
      _savePosition(widget.audio.audioAsset, _position);
    }
    _player.dispose();
    super.dispose();
  }

  static String _resumeKey(String asset) => 'resume_pos_$asset';

  Future<Duration?> _savedPosition(String asset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_resumeKey(asset));
      if (ms == null || ms <= 0) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePosition(String asset, Duration position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_resumeKey(asset), position.inMilliseconds);
    } catch (_) {
      // La persistance peut échouer (mode test) : sans conséquence.
    }
  }

  // ------------------------------------------------------------------------
  // Construction de la vue (responsive portrait / paysage)
  // ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isPlaying = _player.playing;
    final maximum = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final current = _position.inMilliseconds
        .clamp(0, maximum.toInt())
        .toDouble();
    final backgroundAsset =
        getCategoryBackgroundAsset(widget.preacher, widget.audio.category);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1A18),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              backgroundAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [Color(0xFF0F5F4D), Color(0xFF072F2B)],
                    begin: _gBegin(context),
                    end: _gEnd(context),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const BackButton(color: Colors.white),
                      ),
                      _buildFavoriteButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (isLandscape && constraints.maxWidth >= 620) {
                        return _buildLandscape(
                          context,
                          constraints,
                          isPlaying: isPlaying,
                          current: current,
                          maximum: maximum,
                          coverAsset: backgroundAsset,
                        );
                      }
                      return _buildPortrait(
                        context,
                        constraints,
                        isPlaying: isPlaying,
                        current: current,
                        maximum: maximum,
                        coverAsset: backgroundAsset,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortrait(
    BuildContext context,
    BoxConstraints constraints, {
    required bool isPlaying,
    required double current,
    required double maximum,
    required String coverAsset,
  }) {
    final cover = (constraints.maxWidth - 56).clamp(170.0, 330.0).toDouble();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCover(cover, coverAsset),
            const SizedBox(height: 26),
            _buildCenterPanel(
              context,
              isPlaying: isPlaying,
              current: current,
              maximum: maximum,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscape(
    BuildContext context,
    BoxConstraints constraints, {
    required bool isPlaying,
    required double current,
    required double maximum,
    required String coverAsset,
  }) {
    final cover = (constraints.maxHeight - 180).clamp(150.0, 320.0).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Center(child: _buildCover(cover, coverAsset)),
          ),
          const SizedBox(width: 30),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                child: _buildCenterPanel(
                  context,
                  isPlaying: isPlaying,
                  current: current,
                  maximum: maximum,
                  alignLeft: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(double size, String asset) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [Color(0xFF176D5E), Color(0xFF072F2B)],
                  begin: _gBegin(context),
                  end: _gEnd(context),
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.mosque_rounded,
                  size: 56,
                  color: Colors.white38,
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFD4AF37),
                  strokeWidth: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel(
    BuildContext context, {
    required bool isPlaying,
    required double current,
    required double maximum,
    bool alignLeft = false,
  }) {
    final cross = alignLeft
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = alignLeft ? TextAlign.start : TextAlign.center;
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (alignLeft ? width * 0.042 : width * 0.055)
        .clamp(22.0, 30.0)
        .toDouble();

    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.55),
            ),
          ),
          child: Text(
            L10n.content(widget.audio.category).toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFF5E9CE),
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          L10n.content(widget.audio.title),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: titleSize,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFBF7EE),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${L10n.content(widget.audio.category)} · ${widget.preacher.name}',
          textAlign: textAlign,
          style: const TextStyle(
            color: Color(0xFFE4DACC),
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 26),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _isLoading
              ? const KeyedSubtree(
                  key: ValueKey<String>('player-loading'),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(
                      color: Color(0xFFD4AF37),
                      strokeWidth: 3,
                    ),
                  ),
                )
              : _errorMessage != null
                  ? KeyedSubtree(
                      key: const ValueKey<String>('player-error'),
                      child: _buildErrorCard(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('player-controls'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildProgressBox(
                            maximum: maximum,
                            current: current,
                          ),
                          const SizedBox(height: 22),
                          _buildControls(isPlaying: isPlaying),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildProgressBox({required double maximum, required double current}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFD4AF37),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
              thumbColor: Colors.white,
              overlayColor: const Color(0xFFD4AF37).withValues(alpha: 0.18),
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: current,
              min: 0,
              max: maximum,
              onChanged: (value) {
                _player.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(
                  color: Color(0xFFFBF7EE),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isBuffering)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: Color(0xFFD4AF37),
                      strokeWidth: 2,
                    ),
                  ),
                ),
              const Spacer(),
              _buildSpeedPill(),
              const SizedBox(width: 10),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  color: Color(0xFFFBF7EE),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls({required bool isPlaying}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _controlButton(Icons.replay_10_rounded, () => _seekRelative(-10)),
          const SizedBox(width: 8),
          _controlButton(
            Icons.skip_previous_rounded,
            () => _player.seek(Duration.zero),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _togglePlay,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: const Color(0xFF1C1F1E),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(22),
              elevation: 0,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey<bool>(isPlaying),
                size: 38,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _controlButton(Icons.skip_next_rounded, _restart),
          const SizedBox(width: 8),
          _controlButton(Icons.forward_10_rounded, () => _seekRelative(10)),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      iconSize: 28,
      onPressed: onPressed,
      icon: Icon(icon, color: const Color(0xFFFBF7EE)),
      splashRadius: 20,
    );
  }

  /// Bouton favori du lecteur (haut à droite).
  Widget _buildFavoriteButton() {
    return ListenableBuilder(
      listenable: FavoritesStore.instance,
      builder: (context, _) {
        final isFavorite = FavoritesStore.instance.containsFor(
          widget.preacher,
          widget.audio.audioAsset,
        );
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: isFavorite
                ? L10n.t('favorites.remove')
                : L10n.t('favorites.add'),
            onPressed: () => FavoritesStore.instance.toggleFor(
              widget.preacher,
              widget.audio.audioAsset,
            ),
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? const Color(0xFFFF8A80) : Colors.white,
              size: 26,
            ),
          ),
        );
      },
    );
  }

  /// Petite pastille de vitesse de lecture (1× → 1,25× → 1,5× → 2×).
  Widget _buildSpeedPill() {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _cycleSpeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed_rounded, size: 13, color: Color(0xFFD4AF37)),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                _speedLabel,
                key: ValueKey<String>(_speedLabel),
                style: const TextStyle(
                  color: Color(0xFFF5E9CE),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF8A80).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFFB4AA),
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? L10n.t('player.loadError'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFDAD6),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _prepareAudio();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(L10n.t('player.retry')),
          ),
        ],
      ),
    );
  }
}

/// Page de recherche avancée.
///
/// La recherche combine la saisie au clavier, le micro (recherche vocale)
/// et des filtres multi-catégories activables ensemble (chips).
class SearchPage extends StatelessWidget {
  const SearchPage({super.key, required this.preacher});

  final Preacher preacher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _BackArrowButton(tooltip: L10n.t('common.backToSelection')),
        title: Text(L10n.t('search.title')),
        actions: [_SettingsButton(preacher: preacher)],
      ),
      body: AdvancedSearchWidget(preacher: preacher),
    );
  }
}

/// Widget de recherche avancée réutilisable.
///
/// - Saisie vocale : bouton micro (plugin `speech_to_text`)
/// - Recherche textuelle : titre, catégorie, description
/// - Filtres multi-catégories : plusieurs chips sélectionnables à la fois
class AdvancedSearchWidget extends StatefulWidget {
  const AdvancedSearchWidget({super.key, required this.preacher});

  final Preacher preacher;

  @override
  State<AdvancedSearchWidget> createState() => _AdvancedSearchWidgetState();
}

class _AdvancedSearchWidgetState extends State<AdvancedSearchWidget> {
  /// Chips de filtres : propres à chaque prêcheur (ses catégories + Favoris),
  /// ou liste personnalisée définie sur son profil.
  late final List<String> _chips;

  final TextEditingController _controller = TextEditingController();
  String _query = '';
  final Set<String> _selectedChips = <String>{};

  SpeechToText? _speech;
  bool _isListening = false;
  bool _isSpeechAvailable = true;
  bool _speechError = false;

  @override
  void initState() {
    super.initState();
    _chips = widget.preacher.searchChips ??
        [
          ...widget.preacher.categories.map((c) => c.title),
          'Favoris',
        ];
    FavoritesStore.instance.addListener(_onFavoritesChanged);
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FavoritesStore.instance.removeListener(_onFavoritesChanged);
    _speech?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Démarre ou arrête la saisie vocale.
  Future<void> _toggleVoiceSearch() async {
    final speech = _speech ??= SpeechToText();

    if (_isListening) {
      await speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    try {
      final available = await speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _isListening = status == 'listening');
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _speechError = true;
          });
        },
      );

      if (!available) {
        if (!mounted) return;
        setState(() {
          _isSpeechAvailable = false;
          _speechError = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _isSpeechAvailable = true;
        _speechError = false;
        _isListening = true;
      });

      await speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final text = result.recognizedWords;
          setState(() {
            _query = text;
            _controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          });
        },
        listenOptions: SpeechListenOptions(
          localeId: L10n.speechLocale,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _speechError = true;
      });
    }
  }

  void _clearAll() {
    _controller.clear();
    setState(() {
      _query = '';
      _selectedChips.clear();
    });
  }

  List<AudioItem> get _results {
    final query = _query.trim().toLowerCase();

    return widget.preacher.audios.where((audio) {
      // Haystack localisé : la recherche matche le texte affiché dans la
      // langue active (en français, rendu strictement identique).
      final haystack =
          '${L10n.content(audio.title)} ${L10n.content(audio.category)} '
              '${L10n.content(audio.description)}'
          .toLowerCase();

      final matchesQuery = query.isEmpty || haystack.contains(query);

      bool matchesChips = true;
      if (_selectedChips.isNotEmpty) {
        final wantsFavorites = _selectedChips.contains('Favoris');
        final categoryChips = _selectedChips.where((c) => c != 'Favoris');
        // Un audio correspond si : il est en favoris (chip « Favoris »)
        // OU si sa catégorie correspond à l'un des filtres cochés.
        matchesChips =
            (wantsFavorites &&
                FavoritesStore.instance.containsFor(
                  widget.preacher,
                  audio.audioAsset,
                )) ||
            categoryChips.any(
              (c) => haystack.contains(L10n.content(c).toLowerCase()),
            );
      }

      return matchesQuery && matchesChips;
    }).toList();
  }

  bool get _hasFilters => _query.isNotEmpty || _selectedChips.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final results = _results;

    return Container(
      color: pageSurface(context),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: L10n.t('search.hint'),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF0F5F4D),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _isListening
                        ? L10n.t('search.stopDictation')
                        : L10n.t('search.voice'),
                    onPressed: _toggleVoiceSearch,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                      child: Icon(
                        _isListening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        key: ValueKey<bool>(_isListening),
                        color: _isListening
                            ? const Color(0xFFD9534F)
                            : const Color(0xFF0F5F4D),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: L10n.t('search.clear'),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
                ],
              ),
            ),
          ),
          if (_isListening) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFD9534F),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  L10n.t('search.listening'),
                  style: TextStyle(color: subText(context), fontSize: 12.5),
                ),
              ],
            ),
          ] else if (!_isSpeechAvailable) ...[
            const SizedBox(height: 10),
            Text(
              L10n.t('search.voiceUnavailable'),
              style: const TextStyle(
                color: Color(0xFF9A4C4C),
                fontSize: 12.5,
              ),
            ),
          ] else if (_speechError) ...[
            const SizedBox(height: 10),
            Text(
              L10n.t('search.voiceFailed'),
              style: const TextStyle(
                color: Color(0xFF9A4C4C),
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                L10n.t('library.categories'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: mainText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  L10n.t('search.categoriesHint'),
                  style: TextStyle(fontSize: 12, color: subText(context)),
                ),
              ),
              if (_selectedChips.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedChips.clear()),
                  child: Text(L10n.t('search.reset')),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _chips.map((chip) {
              final isSelected = _selectedChips.contains(chip);

              return FilterChip(
                label: Text(L10n.chipLabel(chip)),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedChips.add(chip);
                    } else {
                      _selectedChips.remove(chip);
                    }
                  });
                },
                showCheckmark: false,
                backgroundColor: Colors.white,
                selectedColor: const Color(0xFF0F5F4D),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF0F5F4D)
                      : const Color(0xFFD9D4C8),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF55625C),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                results.isEmpty
                    ? L10n.t('search.noResults')
                    : L10n.resultCount(results.length),
                style: TextStyle(
                  color: subText(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_hasFilters)
                TextButton(
                  onPressed: _clearAll,
                  child: Text(L10n.t('search.clearAll')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: results.isEmpty
                  ? const KeyedSubtree(
                      key: ValueKey<String>('search-empty'),
                      child: _SearchEmptyState(),
                    )
                  : ListView.separated(
                      key: ValueKey<String>(
                        '${_query.trim().toLowerCase()}|'
                        '${(_selectedChips.toList()..sort()).join(',')}',
                      ),
                      padding: EdgeInsets.zero,
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => AudioTile(
                        audio: results[index],
                        preacher: widget.preacher,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// État vide de la recherche (aucun résultat avec les filtres actuels).
class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              color: Color(0xFFE7F2EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 42,
              color: Color(0xFF0F5F4D),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            L10n.t('search.emptyTitle'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: mainText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.t('search.emptyBody'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: subText(context)),
          ),
        ],
      ),
    );
  }
}

/// Ouvre une conversation WhatsApp avec le contact officiel de l'application.
///
/// Repli SnackBar si WhatsApp (ou un navigateur) n'est pas disponible.
Future<void> _openWhatsApp(Preacher preacher, BuildContext context) async {
  final number = (preacher.whatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final uri = Uri.parse('https://wa.me/$number');
  bool opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t('whatsapp.failed')),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.preacher});

  final Preacher preacher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _BackArrowButton(tooltip: L10n.t('common.backToSelection')),
        title: Text(L10n.t('about.title')),
        actions: [_SettingsButton(preacher: preacher)],
      ),
      body: Container(
        color: pageSurface(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const [
                      Color(0xFF072F2B),
                      Color(0xFF0F5F4D),
                      Color(0xFF1C7A68),
                    ],
                    begin: _gBegin(context),
                    end: _gEnd(context),
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    _PreacherAvatar(preacher: preacher, size: 96),
                    const SizedBox(height: 16),
                    Text(
                      preacher.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      L10n.content(preacher.tagline),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeSlideIn(
              delayMs: 110,
              child: _AboutSectionTitle(L10n.t('about.presentation')),
            ),
            const SizedBox(height: 10),
            FadeSlideIn(
              delayMs: 140,
              offset: const Offset(0, 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardSurface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7E0D4)),
                ),
                child: Text(
                  L10n.content(preacher.description),
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: subText(context),
                  ),
                ),
              ),
            ),
            if ((preacher.schedule ?? const []).isNotEmpty) ...[
              const SizedBox(height: 26),
              FadeSlideIn(
                delayMs: 180,
                child: _AboutSectionTitle(L10n.t('about.schedule')),
              ),
              const SizedBox(height: 12),
              ...preacher.schedule!.indexed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FadeSlideIn(
                    delayMs: 210 + entry.$1 * 55,
                    offset: const Offset(0, 12),
                    child: ScheduleDayTile(day: entry.$2),
                  ),
                ),
              ),
            ],
            if (preacher.whatsapp != null) ...[
              const SizedBox(height: 8),
              FadeSlideIn(
                delayMs: 620,
                child: _AboutSectionTitle(L10n.t('about.contact')),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delayMs: 660,
                offset: const Offset(0, 12),
                child: PressScale(
                  child: GestureDetector(
                    onTap: () => _openWhatsApp(preacher, context),
                    child: _InfoTile(
                      icon: Icons.phone_rounded,
                      title: 'WhatsApp',
                      subtitle: preacher.whatsapp!,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delayMs: 700,
                offset: const Offset(0, 12),
                child: PressScale(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWhatsApp(preacher, context),
                      icon: const Icon(Icons.chat_rounded, size: 20),
                      label: Text(L10n.t('about.contactUs')),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            FadeSlideIn(
              delayMs: 740,
              child: Center(
                child: Text(
                  '${L10n.t('settings.version')} $kAppVersion',
                  style: TextStyle(fontSize: 12, color: subText(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Donnée d'une séance du programme hebdomadaire.
class ScheduleDay {
  final String day;
  final String theme;
  final IconData icon;
  final Color color;
  final String? time;
  final List<String> locations;
  final bool alternative;

  const ScheduleDay({
    required this.day,
    required this.theme,
    required this.icon,
    required this.color,
    this.time,
    required this.locations,
    this.alternative = false,
  });
}

/// Programme hebdomadaire des enseignements.
const weekSchedule = [
  ScheduleDay(
    day: 'Mardi',
    theme: 'Sîra du Prophète ﷺ',
    icon: Icons.mosque_rounded,
    color: Color(0xFFF8E8E8),
    time: 'Entre Salat al-Maghrib et Salat al-Isha',
    locations: ['Mosquée Ar-Rahma — Badalabougou'],
  ),
  ScheduleDay(
    day: 'Mercredi',
    theme: 'Sîra du Prophète ﷺ',
    icon: Icons.mosque_rounded,
    color: Color(0xFFF8E8E8),
    time: 'Entre Salat al-Maghrib et Salat al-Isha',
    locations: ['Mosquée Ridwane — Kalaban-Coura'],
  ),
  ScheduleDay(
    day: 'Jeudi',
    theme: 'Sîra du Prophète ﷺ',
    icon: Icons.mosque_rounded,
    color: Color(0xFFF8E8E8),
    time: 'Entre Salat al-Maghrib et Salat al-Isha',
    locations: ['Mosquée Ridwane — Kalaban-Coura'],
  ),
  ScheduleDay(
    day: 'Vendredi',
    theme: 'Sermon / Khutba',
    icon: Icons.mic_rounded,
    color: Color(0xFFE7F2EE),
    locations: [
      'Mosquée Ridwane — Kalaban-Coura',
      'Mosquée Verte — Banankabougou',
    ],
    alternative: true,
  ),
  ScheduleDay(
    day: 'Samedi',
    theme: 'La vie des Compagnons du Prophète ﷺ',
    icon: Icons.groups_rounded,
    color: Color(0xFFDFF0F5),
    time: 'Entre Salat al-Maghrib et Salat al-Isha',
    locations: ['Mosquée Al-Imam Malik — Daoudabougou'],
  ),
  ScheduleDay(
    day: 'Dimanche',
    theme: 'Tafsir du Coran',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFFEEEAF9),
    time: 'Entre Salat al-Maghrib et Salat al-Isha',
    locations: ['Mosquée Ridwane — Kalaban-Coura'],
  ),
];

/// Titre de section de la page « À propos ».
class _AboutSectionTitle extends StatelessWidget {
  final String title;

  const _AboutSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: subText(context),
      ),
    );
  }
}

/// Carte d'une séance : jour, thème, horaire et mosquée(s).
class ScheduleDayTile extends StatelessWidget {
  final ScheduleDay day;

  const ScheduleDayTile({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E0D4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: day.color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(day.icon, color: const Color(0xFF0F5F4D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${L10n.content(day.day)} — ${L10n.content(day.theme)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: mainText(context),
                  ),
                ),
                if (day.time != null) ...[
                  const SizedBox(height: 6),
                  _scheduleMetaLine(
                    context,
                    Icons.schedule_rounded,
                    L10n.content(day.time!),
                  ),
                ],
                if (day.alternative) ...[
                  const SizedBox(height: 4),
                  Text(
                    L10n.t('about.alternatively'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: subText(context),
                    ),
                  ),
                ],
                for (final location in day.locations) ...[
                  const SizedBox(height: 4),
                  _scheduleMetaLine(
                    context,
                    Icons.location_on_rounded,
                    L10n.content(location),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleMetaLine(BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: const Color(0xFF0F5F4D)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: subText(context),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E0D4)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF0F5F4D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: mainText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: subText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton rouage : ouvre la page des paramètres depuis les pages principales.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({this.preacher = imamMadouKone});

  final Preacher preacher;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        Navigator.push(
          context,
          animatedPageRoute<void>(SettingsPage(preacher: preacher)),
        );
      },
      icon: const Icon(Icons.settings_rounded),
      color: Colors.white,
      tooltip: L10n.t('settings.appBar'),
    );
  }
}

/// Page des paramètres de l'application.
///
/// Réglages par défaut : vitesse de lecture 1×, reprise automatique activée,
/// lecture en arrière-plan activée. Tous les choix sont persistés localement.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.preacher});

  /// Prêcheur dont l'espace a ouvert les réglages (null → réglages globaux).
  final Preacher? preacher;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.instance,
      builder: (context, _) {
        final settings = SettingsStore.instance;
        return Scaffold(
          appBar: AppBar(title: Text(L10n.t('settings.appBar'))),
          body: Container(
            color: pageSurface(context),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                FadeSlideIn(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: const [Color(0xFF072F2B), Color(0xFF1C7A68)],
                          begin: _gBegin(context),
                          end: _gEnd(context),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFDBB15F),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/IMG/logo_app.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.t('settings.heroTitle'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  L10n.t('settings.heroSubtitle'),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                _SectionLabel('section.appearance'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _ThemeTile(),
                    _SettingsDivider(),
                    _LanguageTile(),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.playback'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _SpeedTile(),
                    _SettingsDivider(),
                    _SwitchTile(
                      icon: Icons.refresh_rounded,
                      title: L10n.t('settings.resume'),
                      subtitle: L10n.t('settings.resumeSub'),
                      value: settings.resumeEnabled,
                      onChanged: settings.setResumeEnabled,
                    ),
                    _SettingsDivider(),
                    _SwitchTile(
                      icon: Icons.headset_rounded,
                      title: L10n.t('settings.background'),
                      subtitle: L10n.t('settings.backgroundSub'),
                      value: settings.backgroundPlayback,
                      onChanged: settings.setBackgroundPlayback,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.notifications'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _SwitchTile(
                      icon: Icons.notifications_active_outlined,
                      title: L10n.t('settings.mediaNotifs'),
                      subtitle: L10n.t('settings.mediaNotifsSub'),
                      value: settings.mediaNotifications,
                      onChanged: settings.setMediaNotifications,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.sharing'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.share_rounded,
                      title: L10n.t('settings.share'),
                      subtitle: L10n.t('settings.shareSub'),
                      onTap: () => _shareProfile(context),
                    ),
                    _SettingsDivider(),
                    _ActionTile(
                      icon: Icons.star_rounded,
                      title: L10n.t('settings.rate'),
                      subtitle: L10n.t('settings.rateSub'),
                      onTap: () => _rateApp(context),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Compte & abonnement',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F5F4D))),
                ),
                const SizedBox(height: 4),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.workspace_premium_rounded,
                      title: 'Mon abonnement',
                      subtitle: 'Formules · jours restants · paiement',
                      onTap: () {
                        Navigator.push(
                          context,
                          animatedPageRoute<void>(const FreemiumHubPage()),
                        );
                      },
                    ),
                    _SettingsDivider(),
                    _ActionTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Mon compte',
                      subtitle: 'Connexion / inscription',
                      onTap: () {
                        Navigator.push(
                          context,
                          animatedPageRoute<void>(const AuthPage()),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.data'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.favorite_border_rounded,
                      title: L10n.t('settings.clearFavorites'),
                      subtitle: L10n.t('settings.clearFavoritesSub'),
                      onTap: () => _confirmClearFavorites(context),
                    ),
                    _SettingsDivider(),
                    _ActionTile(
                      icon: Icons.restart_alt_rounded,
                      title: L10n.t('settings.reset'),
                      subtitle: L10n.t('settings.resetSub'),
                      onTap: () => _confirmResetSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.updates'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.system_update_alt_rounded,
                      title: L10n.t('settings.checkUpdates'),
                      subtitle: L10n.t('settings.checkUpdatesSub'),
                      onTap: () => _checkUpdates(context),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionLabel('section.app'),
                const SizedBox(height: 10),
                _SettingsCard(
                  children: [
                    _ActionTile(
                      icon: Icons.info_outline_rounded,
                      title: L10n.t('settings.about'),
                      subtitle: L10n.t('settings.aboutSub'),
                      onTap: () {
                        Navigator.push(
                          context,
                          animatedPageRoute<void>(
                            AboutPage(preacher: preacher ?? imamMadouKone),
                          ),
                        );
                      },
                    ),
                    _SettingsDivider(),
                    _InfoRow(
                      icon: Icons.verified_rounded,
                      title: L10n.t('settings.version'),
                      subtitle: kAppVersion,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Envoie le profil (coordonnées + lien) via la feuille de partage système.
  Future<void> _shareProfile(BuildContext context) async {
    final name = preacher?.name ?? 'Imam Madou Koné';
    final message = '$name\n'
        '${L10n.t('home.greeting')}\n'
        'https://play.google.com/store/apps/details'
        '?id=com.imammadoukone.app';
    try {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: name),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L10n.t('share.failed'))));
      }
    }
  }

  /// Ouvre la fiche Google Play de l'application pour la noter.
  Future<void> _rateApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details'
      '?id=com.imammadoukone.app',
    );
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t('rate.failed'))));
    }
  }

  /// État des mises à jour : aucun serveur de déploiement n'est configuré,
  /// l'app signale qu'elle est à jour et propose la fiche Google Play.
  Future<void> _checkUpdates(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t('settings.checkUpdates')),
        content: Text(
          '${L10n.t('updates.current')} : $kAppVersion —'
          '\n${L10n.t('updates.upToDate')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.t('common.ok')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _rateApp(context);
            },
            child: Text(L10n.t('updates.openStore')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearFavorites(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t('favorites.dialogTitle')),
        content: Text(L10n.t('favorites.dialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.t('favorites.clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FavoritesStore.instance.clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t('favorites.done'))));
    }
  }

  Future<void> _confirmResetSettings(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.t('reset.dialogTitle')),
        content: Text(L10n.t('reset.dialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.t('reset.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SettingsStore.instance.resetAll();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.t('reset.done'))));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String textKey;

  const _SectionLabel(this.textKey);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Text(
        L10n.t(textKey),
        style: TextStyle(
          color: isDark ? const Color(0xFF57B6A0) : const Color(0xFF0F5F4D),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    // Un Material (et non un DecoratedBox) sert de surface blanche aux
    // ListTile : l'encre et le fond sont correctement dessinés dessus.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: cardSurface(context),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF2E443C) : const Color(0xFFE7E0D4),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 72,
      endIndent: 14,
      color: isDark ? const Color(0xFF2E443C) : const Color(0xFFEDE7DC),
    );
  }
}

class _TileIcon extends StatelessWidget {
  final IconData icon;

  const _TileIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF274139) : const Color(0xFFEAF4F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: isDark ? const Color(0xFF57B6A0) : const Color(0xFF0F5F4D),
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile();

  static String _label(double speed) {
    if (speed == 1.0) return '1×';
    return '${speed.toString().replaceAll(RegExp(r'\.0$'), '')}×';
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TileIcon(icon: Icons.speed_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t('settings.speed'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.t('settings.speedSub'),
                      style: TextStyle(fontSize: 12, color: subText(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<double>(
              segments: [
                for (final speed in SettingsStore.speedOptions)
                  ButtonSegment<double>(
                    value: speed,
                    label: Text(_label(speed)),
                  ),
              ],
              selected: {settings.defaultSpeed},
              onSelectionChanged: (selection) =>
                  settings.setDefaultSpeed(selection.first),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TileIcon(icon: Icons.palette_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t('settings.theme'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.t('settings.themeSub'),
                      style: TextStyle(fontSize: 12, color: subText(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                for (final option in SettingsStore.themeOptions)
                  ButtonSegment<String>(
                    value: option,
                    label: Text(
                      switch (option) {
                        'light' => L10n.t('theme.light'),
                        'dark' => L10n.t('theme.dark'),
                        _ => L10n.t('theme.system'),
                      },
                    ),
                  ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) =>
                  settings.setThemeMode(selection.first),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TileIcon(icon: Icons.language_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t('settings.language'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: mainText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.t('settings.languageSub'),
                      style: TextStyle(fontSize: 12, color: subText(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                for (final option in SettingsStore.languageOptions)
                  ButtonSegment<String>(
                    value: option,
                    label: Text(
                      switch (option) {
                        'en' => L10n.t('lang.en'),
                        'ar' => L10n.t('lang.ar'),
                        _ => L10n.t('lang.fr'),
                      },
                    ),
                  ),
              ],
              selected: {settings.language},
              onSelectionChanged: (selection) =>
                  settings.setLanguage(selection.first),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        secondary: _TileIcon(icon: icon),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: mainText(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: subText(context)),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: _TileIcon(icon: icon),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: mainText(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: subText(context)),
        ),
        trailing: Icon(_chevronIcon(context), color: subText(context)),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: _TileIcon(icon: icon),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: mainText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subText(context)),
      ),
    );
  }
}
