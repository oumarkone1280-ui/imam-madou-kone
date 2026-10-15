# Hébergement des audios sur Internet — Domaine + Cloudflare R2

**Objectif** : rendre les audios accessibles partout (pas seulement chez vous) via :

```
https://audio.imammadoukone.com/IMMK/audios/...
```

**Coût total** : ~10 $/an (domaine) + ~0,50 $/mois (stockage) = **≈ 16 $/an**.
**Téléchargements : gratuits et illimités.**

---

## ✅ CHECKLIST

- [ ] **Étape 1** — Acheter le domaine `imammadoukone.com`
- [ ] **Étape 2** — Créer le bucket R2 `imam-audios`
- [ ] **Étape 3** — Créer un jeton d'accès (Access Key / Secret Key)
- [ ] **Étape 4** — Installer rclone
- [ ] **Étape 5** — Envoyer les 34 Go (script `rclone-upload.ps1`)
- [ ] **Étape 6** — Brancher le sous-domaine `audio.imammadoukone.com`
- [ ] **Étape 7** — Reconstruire l'application vers l'adresse HTTPS

---

## Étape 1 — Acheter le domaine (≈ 10 min)

Le plus simple : **Cloudflare Registrar** (prix coûtant, sans marge, WHOIS privé gratuit).

1. Créez un compte : https://dash.cloudflare.com/sign-up
2. Menu **Domain Registration** → **Register Domains**.
3. Cherchez **imammadoukone.com**, ajoutez au panier, payez.
4. Le domaine est automatiquement géré par le DNS Cloudflare → parfait pour la suite.

> Si le nom n'est finalement plus disponible, alternatives : `imam-madou-kone.com`, `imammadoukone.org`, `immadoukone.com`.

*(À ce stade, aucune autre action sur le domaine n'est nécessaire.)*

---

## Étape 2 — Créer le bucket R2

1. Tableau de bord Cloudflare → **R2** → **Create bucket**.
2. Nom : `imam-audios`
3. Région : **Automatic**.
4. Créez.

---

## Étape 3 — Créer un jeton d'accès

1. R2 → **Manage API tokens** → **Create API token**.
2. Permission : **Object Read & Write**.
3. Portée : bucket `imam-audios`.
4. Notez les 3 valeurs (gardez-les secrètes) :
   - **Access Key ID**
   - **Secret Access Key**
   - **Account ID** (affiché dans R2 / l'URL du tableau de bord)

---

## Étape 4 — Installer rclone

1. Téléchargez : https://rclone.org/downloads/  (version Windows, .zip)
2. Décompressez et placez `rclone.exe` dans `C:\rclone\`
3. Vérifiez dans PowerShell : `C:\rclone\rclone.exe version`

---

## Étape 5 — Envoyer les 34 Go

1. Ouvrez `play_store\hebergement\rclone-upload.ps1`.
2. Renseignez **AccountId**, **AccessKey**, **SecretKey** en haut du fichier.
3. Lancez :
   ```powershell
   powershell -ExecutionPolicy Bypass -File "D:\imam_madou_kone\play_store\hebergement\rclone-upload.ps1"
   ```

> ⏱️ Plusieurs heures selon votre débit montant. Le script **reprend** : relancez-le autant de fois que nécessaire, il ne renvoie pas ce qui existe déjà.

Arborescence créée dans le bucket (identique) :
```
IMMK/audios/Sira/01.mp3
IMMK/audios/IST Sira/001.mp3
IMMK/audios/IST Khalifes/001.mp3
IMMK/audios/Sermons/....mp3
IMMK/audios/Furuso Duman/01 FD.mp3
IMMK/audios/VCP/01.mp3
IMMK/audios/TST/....mp3
```

---

## Étape 6 — Brancher `audio.imammadoukone.com` (HTTPS)

1. R2 → bucket `imam-audios` → **Settings** → **Public access** → **Custom Domains** → **Connect Domain**.
2. Saisissez : `audio.imammadoukone.com`
3. Cloudflare crée automatiquement le DNS + le certificat HTTPS.
4. Testez ensuite dans un navigateur :
   ```
   https://audio.imammadoukone.com/IMMK/audios/Sira/01.mp3
   ```
   → le fichier doit se lire/se télécharger.

---

## Étape 7 — Reconstruire l'application

Une fois le test de l'étape 6 concluant :

```powershell
flutter build apk --release --dart-define=AUDIO_BASE_URL=https://audio.imammadoukone.com/IMMK/audios
flutter build appbundle --release --dart-define=AUDIO_BASE_URL=https://audio.imammadoukone.com/IMMK/audios
```

Réinstaller sur le téléphone :
```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

> ⚠️ Après cette compilation, l'application ne lit plus les audios depuis votre PC
> mais depuis le serveur Internet. C'est le comportement voulu pour la version Play Store.

---

## Notes techniques

- **Casse des dossiers** : corrigée dans le code (`Sira`, majuscule). R2 est sensible à la casse.
- **Espaces et accents** : gérés automatiquement (URLs encodées par l'app).
- Ne pas activer de règle de réécriture d'URL dans Cloudflare.
- Les fichiers restent en sauvegarde sur votre PC (`D:\XAMP\htdocs\IMMK\Audios`).

## Option alternative — VPS classique

Si préféré plus tard (ex. Hetzner ~4-5 €/mois) : Ubuntu + nginx + certbot (HTTPS Let's Encrypt),
audios dans `/var/www/IMMK/audios`, puis même `AUDIO_BASE_URL=https://imammadoukone.com/IMMK/audios`.
Sur R2 la sortie est gratuite ; un VPS a une limite de trafic mensuelle — R2 reste plus avantageux ici.
