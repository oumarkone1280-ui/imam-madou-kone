# Dossier assets/Sermons/

Les fichiers MP3 ne sont **pas** versionnés (trop lourds pour Git).

L'application charge tous les audios depuis le serveur défini par
`AUDIO_BASE_URL` (voir `lib/main.dart`, constante `kAudioBaseUrl`).

Ce dossier doit rester présent car il est déclaré dans `pubspec.yaml`
(section `flutter: assets:`). Ce fichier sert de garder-fichier.
