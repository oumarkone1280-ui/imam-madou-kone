import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:imam_madou_kone/main.dart';

void main() {
  testWidgets('app builds and shows the preacher selection', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ImamMadouKoneApp());

    // Les quatre prêcheurs sont proposés sur l'accueil général.
    expect(find.text('IMAM MADOU KONÉ'), findsOneWidget);
    expect(find.text('IMAM ABDOULAYE KOÏTA'), findsOneWidget);
    expect(find.text('IMAM MAHI OUATTARA'), findsOneWidget);
    expect(find.text('IMAM SIDI TOURE'), findsOneWidget);

    // Sélection de l'Imam Madou Koné : son espace personnel s'ouvre.
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMAM MADOU KONÉ'));
    await tester.pumpAndSettle();

    expect(find.text('Imam Madou Koné'), findsOneWidget);
    expect(find.text('Explorer les contenus'), findsOneWidget);

    // Le bouton rouage (Paramètres) est accessible depuis l'accueil.
    expect(find.byTooltip('Paramètres'), findsOneWidget);

    // La flèche « Retour à la sélection » ramène à l'accueil général.
    await tester.tap(find.byTooltip('Retour à la sélection'));
    await tester.pumpAndSettle();
    expect(find.text('IMAM MAHI OUATTARA'), findsOneWidget);
  });

  testWidgets('selecting Imam Mahi Ouattara shows only his own categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ImamMadouKoneApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMAM MAHI OUATTARA'));
    await tester.pumpAndSettle();

    // Identité du prêcheur clairement affichée dans son espace.
    expect(find.text('Imam Mahi Ouattara'), findsOneWidget);
    expect(find.text('2 catégories'), findsOneWidget);

    // Ses deux catégories uniquement.
    expect(find.text('Sermon'), findsOneWidget);
    expect(find.text('Tafsir'), findsOneWidget);

    // Aucune catégorie de l'Imam Madou Koné n'apparaît ici.
    expect(find.text('Furuso Duman'), findsNothing);
    expect(find.text('Sîra du Prophète ﷺ'), findsNothing);
    expect(find.text('Sermons'), findsNothing);
  });

  testWidgets('selecting Imam Sidi Toure shows his four categories', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ImamMadouKoneApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMAM SIDI TOURE'));
    await tester.pumpAndSettle();

    expect(find.text('Imam Sidi Toure'), findsOneWidget);
    expect(find.text('4 catégories'), findsOneWidget);
    expect(
      find.text('Traductions des sermons des Imams de La Mecque et de Médine'),
      findsOneWidget,
    );
    expect(find.text('Tafsir du Coran'), findsOneWidget);
    expect(find.text('Sîra du Prophète ﷺ'), findsOneWidget);
    expect(
      find.text('L\'Histoire des Khalifes du Prophète ﷺ'),
      findsOneWidget,
    );

    // Cet espace n'affiche pas les catégories Sermon/Tafsir des autres comptes.
    expect(find.text('Sermon'), findsNothing);
  });

  test('assets Sermons are declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('assets/Sermons/'));
  });

  test('the audio base URL is configured', () {
    expect(kAudioBaseUrl, isNotEmpty);
  });

  test('each category has its own unique icon and color', () {
    expect(categories.length, greaterThanOrEqualTo(6));
    expect(
      categories.map((c) => c.icon).toSet().length,
      categories.length,
      reason: 'Chaque catégorie doit avoir une icône distincte.',
    );
    expect(
      categories.map((c) => c.color).toSet().length,
      categories.length,
      reason: 'Chaque catégorie doit avoir une couleur distincte.',
    );
  });

  testWidgets('advanced search: micro button and multi-category chips', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: SearchPage(preacher: imamMadouKone)),
    );

    // Bouton micro présent (recherche vocale).
    expect(find.byTooltip('Recherche vocale'), findsOneWidget);

    // Sans filtre : tous les audios sont listés.
    final total = demoAudios.length;
    final totalLabel = '$total résultat${total > 1 ? 's' : ''}';
    expect(find.text(totalLabel), findsOneWidget);

    // Sélection d'une catégorie.
    await tester.tap(find.widgetWithText(FilterChip, 'Sermons'));
    await tester.pump();
    final sermons = demoAudios
        .where(
          (a) => '${a.title} ${a.category} ${a.description}'
              .toLowerCase()
              .contains('sermons'),
        )
        .length;
    expect(
      find.text('$sermons résultat${sermons > 1 ? 's' : ''}'),
      findsOneWidget,
    );

    // Une seconde catégorie s'ajoute aux résultats (cumul = OU logique).
    await tester.tap(find.widgetWithText(FilterChip, 'Furuso Duman'));
    await tester.pump();
    final combined = demoAudios.where((a) {
      final haystack = '${a.title} ${a.category} ${a.description}'
          .toLowerCase();
      return haystack.contains('sermons') || haystack.contains('furuso duman');
    }).length;
    expect(
      find.text('$combined résultat${combined > 1 ? 's' : ''}'),
      findsOneWidget,
    );

    // « Réinitialiser » vide la sélection des chips.
    await tester.tap(find.text('Réinitialiser'));
    await tester.pump();
    expect(find.text(totalLabel), findsOneWidget);
  });

  testWidgets('settings: gear opens the page with default values', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    await tester.pumpWidget(const ImamMadouKoneApp());

    // Va dans l'espace de l'Imam Madou Koné puis ouvre les Paramètres.
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMAM MADOU KONÉ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paramètres'));
    await tester.pumpAndSettle();

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Vitesse de lecture'), findsOneWidget);
    expect(find.text('Reprise automatique'), findsOneWidget);
    expect(find.text('Lecture en arrière-plan'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);

    // Valeurs par défaut appliquées.
    expect(SettingsStore.instance.defaultSpeed, 1.0);
    expect(SettingsStore.instance.resumeEnabled, isTrue);
    expect(SettingsStore.instance.backgroundPlayback, isTrue);
  });

  testWidgets('settings: choose default speed and disable resume', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    // Sélectionne 2× comme vitesse par défaut.
    await tester.tap(find.text('2×'));
    await tester.pump();
    expect(SettingsStore.instance.defaultSpeed, 2.0);

    // Désactive la reprise automatique.
    await tester.tap(find.text('Reprise automatique'));
    await tester.pump();
    expect(SettingsStore.instance.resumeEnabled, isFalse);

    // Rétablit les valeurs par défaut.
    await SettingsStore.instance.resetAll();
    expect(SettingsStore.instance.defaultSpeed, 1.0);
    expect(SettingsStore.instance.resumeEnabled, isTrue);
  });

  test('settings store keeps defaults and persists changes', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore.instance;
    await store.load();

    expect(store.defaultSpeed, 1.0);
    expect(store.resumeEnabled, isTrue);
    expect(store.backgroundPlayback, isTrue);
    expect(store.themeMode, 'system');
    expect(store.language, 'fr');
    expect(store.mediaNotifications, isTrue);

    await store.setDefaultSpeed(1.5);
    await store.setResumeEnabled(false);
    await store.setBackgroundPlayback(false);
    await store.setThemeMode('dark');
    await store.setLanguage('en');
    await store.setMediaNotifications(false);

    expect(store.defaultSpeed, 1.5);
    expect(store.resumeEnabled, isFalse);
    expect(store.backgroundPlayback, isFalse);
    expect(store.themeMode, 'dark');
    expect(store.language, 'en');
    expect(store.mediaNotifications, isFalse);

    // Un autre chargement restitue les valeurs persistées.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('settings_default_speed'), 1.5);
    expect(prefs.getBool('settings_resume_enabled'), isFalse);
    expect(prefs.getString('settings_theme_mode'), 'dark');
    expect(prefs.getString('settings_language'), 'en');
    expect(prefs.getBool('settings_media_notifications'), isFalse);

    await store.resetAll();
    expect(store.defaultSpeed, 1.0);
    expect(store.resumeEnabled, isTrue);
    expect(store.backgroundPlayback, isTrue);
    expect(store.themeMode, 'system');
    expect(store.language, 'fr');
    expect(store.mediaNotifications, isTrue);
  });

  testWidgets('settings: theme selector switches and persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    // Sélectionne le thème sombre.
    expect(SettingsStore.instance.themeMode, 'system');
    await tester.tap(find.text('Sombre'));
    await tester.pump();
    expect(SettingsStore.instance.themeMode, 'dark');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_theme_mode'), 'dark');

    await SettingsStore.instance.resetAll();
    expect(SettingsStore.instance.themeMode, 'system');
  });

  testWidgets('settings: language selector switches the interface', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    // Passage en anglais : la page change immédiatement.
    expect(find.text('Réglages'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(SettingsStore.instance.language, 'en');
    expect(find.text('Settings'), findsNWidgets(2)); // barre + en-tête
    expect(find.text('Theme'), findsOneWidget);

    // La préférence est persistée.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_language'), 'en');

    await SettingsStore.instance.resetAll();
  });

  testWidgets('settings: media notifications switch toggles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    expect(SettingsStore.instance.mediaNotifications, isTrue);
    await tester.tap(find.text('Contrôles sur l’écran verrouillé'));
    await tester.pump();
    expect(SettingsStore.instance.mediaNotifications, isFalse);

    await SettingsStore.instance.resetAll();
    expect(SettingsStore.instance.mediaNotifications, isTrue);
  });

  testWidgets('settings: sharing, rating and updates tiles are present', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    expect(find.text('Thème'), findsOneWidget);
    expect(find.text('Langue'), findsOneWidget);
    expect(find.text('Partager le profil'), findsOneWidget);
    expect(find.text('Noter l’application'), findsOneWidget);
    expect(find.text('Vérifier les mises à jour'), findsOneWidget);
    expect(find.text('Effacer les favoris'), findsOneWidget);
    expect(find.text('À propos'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
  });

  testWidgets('settings: update check shows up-to-date dialog', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    await tester.tap(find.text('Vérifier les mises à jour'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Dernière version : 1.0.0 —'
        '\nVous disposez déjà de la dernière version.',
      ),
      findsOneWidget,
    );
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Voir sur le Google Play'), findsOneWidget);

    // Fermer le dialog ne laisse aucune trace dans l'arbre.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Dernière version : 1.0.0 —'
        '\nVous disposez déjà de la dernière version.',
      ),
      findsNothing,
    );
  });

  testWidgets('about page shows the presentation and the weekly schedule', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    // Grand viewport : toute la page est construite (ListView paresseuse).
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: AboutPage(preacher: imamMadouKone)),
    );

    // Présentation fournie par le programme hebdomadaire.
    expect(find.text('Présentation'), findsOneWidget);
    expect(
      find.textContaining('dispensés dans différentes mosquées de Bamako'),
      findsOneWidget,
    );

    // Titre de section + 6 séances.
    expect(find.text('Programme hebdomadaire'), findsOneWidget);
    expect(find.text('Mardi — Sîra du Prophète ﷺ'), findsOneWidget);
    expect(find.text('Mercredi — Sîra du Prophète ﷺ'), findsOneWidget);
    expect(find.text('Jeudi — Sîra du Prophète ﷺ'), findsOneWidget);
    expect(find.text('Vendredi — Sermon / Khutba'), findsOneWidget);
    expect(
      find.text('Samedi — La vie des Compagnons du Prophète ﷺ'),
      findsOneWidget,
    );
    expect(find.text('Dimanche — Tafsir du Coran'), findsOneWidget);

    // Mosquées et horaires (répartis sur plusieurs lignes).
    expect(
      find.text('Entre Salat al-Maghrib et Salat al-Isha'),
      findsNWidgets(5),
    );
    expect(
      find.text('Mosquée Ar-Rahma — Badalabougou'),
      findsOneWidget,
    );
    expect(
      find.text('Mosquée Ridwane — Kalaban-Coura'),
      findsNWidgets(4),
    );
    expect(
      find.text('Mosquée Verte — Banankabougou'),
      findsOneWidget,
    );
    expect(
      find.text('Mosquée Al-Imam Malik — Daoudabougou'),
      findsOneWidget,
    );

    // Les sermons du vendredi sont « alternativement » dans deux mosquées.
    expect(find.text('Alternativement :'), findsOneWidget);

    // Section contact : numéro WhatsApp officiel.
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('+223 77 92 65 87'), findsOneWidget);
    expect(find.text('Nous contacter'), findsOneWidget);
  });
}
