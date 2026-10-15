# Imam Madou Koné

Application officielle de l'Imam Madou Koné : prêches, sermons, lectures du
Coran, tafsirs et enseignements, écoute en streaming.

## Fonctionnalités

- **Accueil** : catégories de contenus et dernière publication.
- **Audios** : bibliothèque audio.
- **Recherche** : recherche par titre, catégorie ou description, avec
  filtres par catégorie.
- **Lecture** : lecteur audio (just_audio) avec reprise en arrière-plan
  (just_audio_background), barre de progression, avance/retour de 10 s.
- **À propos** : informations sur l'application.

## Données des audios

Les audios sont actuellement hébergés sur un **serveur HTTP** (XAMPP par
défaut) et joués en streaming. L'URL de base est définie par la constante
`kAudioBaseUrl` dans `lib/main.dart` :

- Valeur par défaut : `http://192.168.1.63/IMMK/audios` (réseau local du
  développeur).
- Surcharge au lancement :

```bash
flutter run --dart-define=AUDIO_BASE_URL=https://votre-serveur.com/IMMK/audios
```

Si le serveur est injoignable, le lecteur tente automatiquement de jouer le
fichier localement s'il est embarqué dans `assets/` (voir `pubspec.yaml`).

## Développement

```bash
flutter pub get
flutter run            # sur un appareil/émulateur connecté
flutter analyze        # vérifications statiques
flutter test           # tests
```

Pour fonctionner sur Android, l'application doit disposer de la permission
`INTERNET` (ajoutée dans `AndroidManifest.xml`) et du trafic HTTP en clair
(`android:usesCleartextTraffic="true"`), nécessaire tant que le serveur
n'utilise pas HTTPS.