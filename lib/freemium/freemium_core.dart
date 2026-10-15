import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as cryptolib;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_api.dart';

/// ---------------------------------------------------------------------------
/// Cœur du système Freemium de l'application — **unique et canonique**.
///
/// Contenu exclusif de tout le Freemium dans `lib/` : formules d'abonnement,
/// moyens de paiement (Orange Money, Wave), comptes utilisateurs locaux,
/// abonnements actifs, transactions et persistance locale. Aucune autre
/// classe Freemium ne doit être déclarée ailleurs dans `lib/`.
/// ---------------------------------------------------------------------------

/// Formule d'abonnement proposée à l'utilisateur.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.code,
    required this.label,
    required this.durationDays,
    required this.priceFcfa,
    required this.tagline,
  });

  /// Identifiant stable et court (ex. `1m`, `3m`, `1y`).
  final String code;

  /// Étiquette courte affichée (ex. « 1 mois »).
  final String label;

  /// Durée en jours de l'abonnement.
  final int durationDays;

  /// Prix en Francs CFA.
  final int priceFcfa;

  /// Phrase d'accroche courte (ex. « 30 jours d'accès illimité »).
  final String tagline;

  static const List<SubscriptionPlan> all = [
    SubscriptionPlan(
      code: '1m',
      label: '1 mois',
      durationDays: 30,
      priceFcfa: 1500,
      tagline: '30 jours d\'accès illimité',
    ),
    SubscriptionPlan(
      code: '3m',
      label: '3 mois',
      durationDays: 90,
      priceFcfa: 3500,
      tagline: '90 jours d\'accès illimité',
    ),
    SubscriptionPlan(
      code: '1y',
      label: '1 an',
      durationDays: 365,
      priceFcfa: 10000,
      tagline: '365 jours d\'accès illimité',
    ),
  ];

  static SubscriptionPlan byCode(String code) => all.firstWhere(
        (p) => p.code == code,
        orElse: () => all.first,
      );

  /// Prix formaté en français (ex. « 3 500 F CFA »).
  String get priceLabel => '${_formatThousands(priceFcfa)} F CFA';

  static String _formatThousands(int value) =>
      value.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+$)'),
            (m) => '${m[1]} ',
          );
}

/// Moyen de paiement supporté par l'application.
///
/// L'interface `PaymentGateway` permet d'ajouter facilement d'autres moyens
/// de paiement (Orange Money, Wave) plus tard, sans toucher au reste du code.
abstract class PaymentGateway {
  const PaymentGateway();

  /// Nom lisible du moyen de paiement (ex. « Orange Money »).
  String get name;

  /// Numéro sur lequel l'utilisateur envoie l'argent.
  String get accountNumber;

  /// Étiquette courte affichée (ex. « OM »).
  String get shortLabel;

  /// Vérifie réellement la preuve de paiement.
  ///
  /// Retourne `true` seulement si le paiement a été confirmé. En version
  /// locale simulée, on valide le code de confirmation saisi dans l'app.
  /// **Jamais** de déblocage sur simple clic « Payer ».
  Future<bool> verifyPayment({
    required String proof,
    required SubscriptionPlan plan,
    required String phone,
  });
}

/// Orange Money : premier moyen de paiement.
class OrangeMoneyGateway implements PaymentGateway {
  const OrangeMoneyGateway();

  @override
  String get name => 'Orange Money';

  @override
  String get accountNumber => '77 92 65 87';

  @override
  String get shortLabel => 'OM';

  @override
  Future<bool> verifyPayment({
    required String proof,
    required SubscriptionPlan plan,
    required String phone,
  }) =>
      const _LocalCodeVerifier().verify(proof: proof);
}

/// Wave : second moyen de paiement.
class WaveGateway implements PaymentGateway {
  const WaveGateway();

  @override
  String get name => 'Wave';

  @override
  String get accountNumber => '77 92 65 87';

  @override
  String get shortLabel => 'WA';

  @override
  Future<bool> verifyPayment({
    required String proof,
    required SubscriptionPlan plan,
    required String phone,
  }) =>
      const _LocalCodeVerifier().verify(proof: proof);
}

/// Vérificateur local de code de confirmation (simulé).
///
/// ⚠️ À remplacer par un appel API serveur réel dès que le backend existera.
/// En attendant, on accepte les codes au format `IMMK-XXXX` (4 caractères)
/// pour permettre les tests — jamais de simple clic « Payer » qui
/// débloquerait quoi que ce soit.
class _LocalCodeVerifier {
  const _LocalCodeVerifier();

  Future<bool> verify({required String proof}) async {
    final code = proof.trim();
    if (code.isEmpty) return false;
    return RegExp(r'^IMMK-\d{4}$', caseSensitive: false).hasMatch(code);
  }
}

/// Compte utilisateur local.
class UserAccount {
  const UserAccount({
    required this.phone,
    required this.passwordHash,
    this.displayName,
  });

  /// Numéro de téléphone servant d'identifiant.
  final String phone;

  /// Empreinte SHA-256 du mot de passe (jamais le mot de passe en clair).
  final String passwordHash;

  /// Nom / prénom facultatif affiché sur le profil.
  final String? displayName;
}

/// Abonnement actif lié à un compte.
///
/// Toutes les dates sont en UTC. Le compteur de jours est **calculé** à
/// partir de la date d'expiration (jamais décrété ou modifiable localement) :
/// `daysRemaining` décrémente donc naturellement chaque jour.
class ActiveSubscription {
  const ActiveSubscription({
    required this.planCode,
    required this.planLabel,
    required this.startedAtUtc,
    required this.expiresAtUtc,
    required this.transactionRef,
    required this.gatewayId,
  });

  final String planCode;
  final String planLabel;

  /// Date de début (UTC).
  final DateTime startedAtUtc;

  /// Date d'expiration (UTC).
  final DateTime expiresAtUtc;

  /// Référence de la transaction de paiement.
  final String transactionRef;

  /// Identifiant du moyen de paiement (ex. `orange_money`, `wave`).
  final String gatewayId;

  bool get isActive => DateTime.now().toUtc().isBefore(expiresAtUtc);

  /// Jours restants calculés depuis la date d'expiration (arrondi supérieur).
  int get daysRemaining {
    final now = DateTime.now().toUtc();
    if (!isActive) return 0;
    final diff = expiresAtUtc.difference(now);
    return (diff.inMinutes / (24 * 60)).ceil();
  }
}

/// Transaction de paiement enregistrée (pour le suivi).
class PaymentTransaction {
  const PaymentTransaction({
    required this.gatewayId,
    required this.planCode,
    required this.amountFcfa,
    required this.ref,
    required this.atUtc,
    this.status = 'pending',
  });

  final String gatewayId;
  final String planCode;
  final int amountFcfa;
  final String ref;
  final DateTime atUtc;
  final String status;
}

/// Code d'accès offert généré par le promoteur.
///
/// Distribution indépendante des comptes : le promoteur partage ces codes
/// (famille, proches), chaque bénéficiaire l'active une fois dans son app.
class GiftCode {
  const GiftCode({
    required this.code,
    required this.atUtc,
    this.note,
  });

  final String code;
  final DateTime atUtc;

  /// Remarque libre du promoteur (ex. le nom du bénéficiaire).
  final String? note;

  Map<String, dynamic> toJson() => {
        'code': code,
        'atUtc': atUtc.toIso8601String(),
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory GiftCode.fromJson(Map<String, dynamic> json) => GiftCode(
        code: json['code'] as String,
        atUtc: DateTime.parse(json['atUtc'] as String),
        note: json['note'] as String?,
      );
}

/// 🔑 PIN du compte promoteur — **à modifier ici, un seul endroit**.
///
/// L'espace promoteur permet de générer des codes d'accès offert (famille,
/// proches) ; les autres utilisateurs doivent payer via OM / Wave.
/// Exemple : remplacez par un code de 6 chiffres à vous avant distribution.
const String kPromoterPin = '770325';

/// Préfixe des codes offerts (format : `IMMKG-XXXX-XXXX-XXXX`).
const String kGiftCodePrefix = 'IMMKG';

/// Verrouillage des abonnements — valeur utilisée au **premier lancement**.
///
/// ⚠️ C'est CETTE valeur qui s'applique sur chaque téléphone qui installe
/// l'APK (ex. envoyé par Xender) : mettez-la à `true` pour la distribution
/// finale — le verrou est alors **actif par défaut partout** (3 gratuits par
/// catégorie pour les non-abonnés). Le promoteur peut ensuite activer /
/// désactiver le verrou à tout moment depuis son panneau (Espace promoteur),
/// sans recompiler ; cet état est enregistré **sur chaque appareil**.
const bool kDefaultAudioLockEnabled = true;

/// Magasin central Freemium : comptes + abonnement + audios gratuits.
///
/// Persiste tout dans `SharedPreferences`. Fournit la logique « 3 audios
/// gratuits par catégorie » (positionnels), la gestion de compte et
/// l'abonnement avec compteur de jours calculé depuis l'expiration.
class FreemiumStore extends ChangeNotifier {
  FreemiumStore._();

  static final FreemiumStore instance = FreemiumStore._();

  static const String _kPrefsPhone = 'freemium_phone';
  static const String _kPrefsPasswordHash = 'freemium_password_hash';
  static const String _kPrefsDisplayName = 'freemium_display_name';
  static const String _kPrefsPlanCode = 'freemium_plan_code';
  static const String _kPrefsPlanLabel = 'freemium_plan_label';
  static const String _kPrefsStartedAt = 'freemium_started_at';
  static const String _kPrefsExpiresAt = 'freemium_expires_at';
  static const String _kPrefsTxnRef = 'freemium_txn_ref';
  static const String _kPrefsGatewayId = 'freemium_gateway_id';
  static const String _kPrefsFreeLimit = 'freemium_free_limit'; // jours gratuits par catégorie
  static const String _kPrefsGiftCodes = 'promoter_gift_codes';
  static const String _kPrefsRedeemedCodes = 'gifted_redeemed_codes';
  static const String _kPrefsLockEnabled = 'promoter_lock_enabled';

  /// Nombre d'audios gratuits par catégorie (les 3 premiers).
  static const int freeAudiosPerCategory = 3;

  UserAccount? _account;
  ActiveSubscription? _subscription;
  final List<PaymentTransaction> _transactions = [];
  final List<GiftCode> _giftCodes = [];
  final List<String> _redeemedCodes = [];
  bool _lockEnabled = kDefaultAudioLockEnabled;

  UserAccount? get account => _account;
  ActiveSubscription? get subscription => _subscription;
  List<PaymentTransaction> get transactions => List.unmodifiable(_transactions);
  bool get isLoggedIn => _account != null;
  bool get isPremium => _subscription?.isActive ?? false;

  /// Jours restants (0 si expiré / non abonné).
  int get daysRemaining =>
      _subscription?.isActive ?? false ? _subscription!.daysRemaining : 0;

  /// Codes offerts générés par le promoteur (plus récents en premier).
  List<GiftCode> get giftCodes => List.unmodifiable(_giftCodes);

  /// Verrouillage des abonnements — piloté par le promoteur.
  bool get lockEnabled => _lockEnabled;

  /// Charge l'état depuis le stockage.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(_kPrefsPhone);
      final hash = prefs.getString(_kPrefsPasswordHash);
      if (phone != null && hash != null) {
        _account = UserAccount(
          phone: phone,
          passwordHash: hash,
          displayName: prefs.getString(_kPrefsDisplayName),
        );
      }
      final planCode = prefs.getString(_kPrefsPlanCode);
      final started = prefs.getString(_kPrefsStartedAt);
      final expires = prefs.getString(_kPrefsExpiresAt);
      final txn = prefs.getString(_kPrefsTxnRef);
      if (planCode != null && started != null && expires != null && txn != null) {
        _subscription = ActiveSubscription(
          planCode: planCode,
          planLabel: prefs.getString(_kPrefsPlanLabel) ?? planCode,
          startedAtUtc: DateTime.parse(started),
          expiresAtUtc: DateTime.parse(expires),
          transactionRef: txn,
          gatewayId: prefs.getString(_kPrefsGatewayId) ?? '',
        );
      }
      final giftRaw = prefs.getString(_kPrefsGiftCodes);
      if (giftRaw != null) {
        try {
          final decoded = jsonDecode(giftRaw) as List<dynamic>;
          _giftCodes
            ..clear()
            ..addAll(decoded.map(
                (e) => GiftCode.fromJson(e as Map<String, dynamic>)));
        } catch (_) {}
      }
      final redeemedRaw = prefs.getString(_kPrefsRedeemedCodes);
      if (redeemedRaw != null) {
        try {
          _redeemedCodes
            ..clear()
            ..addAll((jsonDecode(redeemedRaw) as List<dynamic>).cast<String>());
        } catch (_) {}
      }
      _lockEnabled =
          prefs.getBool(_kPrefsLockEnabled) ?? kDefaultAudioLockEnabled;
    } catch (_) {
      // En mode test / premier lancement, on part d'un état vide.
    }
    notifyListeners();
  }

  /// Crée un compte local. Retourne un message d'erreur si échec.
  Future<String?> register({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    final p = phone.trim();
    final pass = password.trim();
    if (p.length < 8) return 'Numéro de téléphone invalide (8 chiffres minimum).';
    if (pass.length < 6) return 'Le mot de passe doit contenir au moins 6 caractères.';
    _account = UserAccount(
      phone: p,
      passwordHash: hashPassword(pass),
      displayName: displayName?.trim().isEmpty ?? true ? null : displayName!.trim(),
    );
    await _persistAccount();
    notifyListeners();
    syncToLedger();
    return null;
  }

  /// Connecte un compte existant.
  Future<String?> login({
    required String phone,
    required String password,
  }) async {
    // Sans serveur : on considère toute inscription comme « existante ».
    final p = phone.trim();
    if (p.length < 8) return 'Numéro de téléphone invalide.';
    _account = UserAccount(
      phone: p,
      passwordHash: hashPassword(password.trim()),
    );
    await _persistAccount();
    notifyListeners();
    syncToLedger();
    return null;
  }

  /// Déconnecte (ne supprime pas l'abonnement).
  Future<void> logout() async {
    _account = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefsPhone);
      await prefs.remove(_kPrefsPasswordHash);
      await prefs.remove(_kPrefsDisplayName);
    } catch (_) {}
    notifyListeners();
  }

  /// Active l'abonnement. ⚠️ À n'appeler **qu'après** vérification réelle
  /// de la preuve de paiement (jamais sur simple clic « Payer »).
  Future<bool> activateSubscription({
    required SubscriptionPlan plan,
    required PaymentGateway gateway,
    required String proof,
  }) async {
    // Deuxième garde-fou : on re-vérifie ici, même si l'UI a vérifié.
    final ok = await gateway.verifyPayment(
      proof: proof,
      plan: plan,
      phone: _account?.phone ?? '',
    );
    if (!ok) return false;

    final now = DateTime.now().toUtc();
    _subscription = ActiveSubscription(
      planCode: plan.code,
      planLabel: plan.label,
      startedAtUtc: now,
      expiresAtUtc: now.add(Duration(days: plan.durationDays)),
      transactionRef: 'IMMK-${proof.trim().toUpperCase()}',
      gatewayId: gateway is OrangeMoneyGateway
          ? 'orange_money'
          : gateway is WaveGateway
              ? 'wave'
              : 'unknown',
    );
    _transactions.add(PaymentTransaction(
      gatewayId: _subscription!.gatewayId,
      planCode: plan.code,
      amountFcfa: plan.priceFcfa,
      ref: _subscription!.transactionRef,
      atUtc: now,
      status: 'confirmed',
    ));
    await _persistSubscription();
    notifyListeners();
    syncToLedger();
    return true;
  }

  /// Vrai si le code PIN saisi correspond au compte promoteur.
  bool verifyPromoterPin(String pin) => pin.trim() == kPromoterPin;

  /// Génère un nouveau code d'accès offert (imprévisible) pour un proche.
  Future<GiftCode> createGiftCode({String? note}) async {
    final gc = GiftCode(
      code: _generateGiftCode(),
      atUtc: DateTime.now().toUtc(),
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    );
    _giftCodes.insert(0, gc);
    await _persistGiftCodes();
    notifyListeners();
    return gc;
  }

  /// Retire un code offert de la liste du promoteur (suppression locale).
  Future<void> removeGiftCode(String code) async {
    _giftCodes.removeWhere((g) => g.code == code);
    await _persistGiftCodes();
    notifyListeners();
  }

  /// Active / désactive le verrouillage des abonnements sur cet appareil.
  ///
  /// Activé : les non-abonnés sont limités à 3 audios gratuits par catégorie.
  /// Désactivé : tous les audios sont libres (mode test de lecture).
  /// L'état est enregistré et conservé après redémarrage de l'app.
  Future<void> setLockEnabled(bool value) async {
    if (_lockEnabled == value) return;
    _lockEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefsLockEnabled, value);
    } catch (_) {}
    notifyListeners();
  }

  /// Active un code offert sur cet appareil.
  ///
  /// Retourne `null` si l'activation a réussi, sinon un message d'erreur.
  Future<String?> redeemGiftCode(String raw) async {
    final code = raw.trim().toUpperCase();
    final okFormat = RegExp(
      '^$kGiftCodePrefix-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\$',
    ).hasMatch(code);
    if (!okFormat) {
      return 'Code invalide. Format attendu : IMMKG-XXXX-XXXX-XXXX.';
    }
    if (_redeemedCodes.contains(code)) {
      return 'Ce code a déjà été utilisé sur cet appareil.';
    }
    if (isPremium) {
      return 'Vous avez déjà un abonnement actif.';
    }
    final now = DateTime.now().toUtc();
    _subscription = ActiveSubscription(
      planCode: 'gift',
      planLabel: 'Accès offert',
      startedAtUtc: now,
      expiresAtUtc: now.add(const Duration(days: 3650)),
      transactionRef: code,
      gatewayId: 'gift',
    );
    _redeemedCodes.add(code);
    await _persistRedeemed();
    await _persistSubscription();
    notifyListeners();
    syncToLedger();
    return null;
  }

  /// 📡 Envoie le profil + abonnement courants au registre du promoteur
  /// (« Base des utilisateurs »). Best-effort, jamais bloquant.
  ///
  /// Appelé à l'inscription, la connexion, lors d'un abonnement payé et à
  /// l'activation d'un code offert, ainsi qu'au démarrage de l'app si un
  /// compte est déjà connecté.
  void syncToLedger() {
    final a = _account;
    if (a == null) return;
    final s = _subscription;
    unawaited(
      UsersLedger.pushUser(
        phone: a.phone,
        displayName: a.displayName,
        subscription: s == null
            ? null
            : LedgerSubscription(
                planLabel: s.planLabel,
                startedAtUtc: s.startedAtUtc,
                expiresAtUtc: s.expiresAtUtc,
                gateway: s.gatewayId,
                ref: s.transactionRef,
                isGift: s.gatewayId == 'gift',
              ),
      ),
    );
  }

  String _generateGiftCode() {
    // Alphabet sans ambiguïté (pas de 0/O, 1/I).
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    String pick(int n) => List.generate(
          n,
          (_) => chars[rng.nextInt(chars.length)],
        ).join();
    return '$kGiftCodePrefix-${pick(4)}-${pick(4)}-${pick(4)}';
  }

  /// Vrai si l'audio à la position donnée est gratuit pour cet utilisateur.
  ///
  /// Règle : les 3 premiers audios de chaque catégorie sont gratuits
  /// (positionnels). Ensuite, verrouillés sauf si abonnement actif.
  bool isFree({
    required String category,
    required int positionInCategory,
  }) {
    if (isPremium) return true;
    return positionInCategory < freeAudiosPerCategory;
  }

  bool isLocked({
    required String category,
    required int positionInCategory,
  }) {
    return !isFree(category: category, positionInCategory: positionInCategory);
  }

  /// Efface tout (compte + abonnement). Utilisé par « Réinitialiser ».
  Future<void> resetAll() async {
    _account = null;
    _subscription = null;
    _transactions.clear();
    _giftCodes.clear();
    _redeemedCodes.clear();
    _lockEnabled = kDefaultAudioLockEnabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        _kPrefsPhone,
        _kPrefsPasswordHash,
        _kPrefsDisplayName,
        _kPrefsPlanCode,
        _kPrefsPlanLabel,
        _kPrefsStartedAt,
        _kPrefsExpiresAt,
        _kPrefsTxnRef,
        _kPrefsGatewayId,
        _kPrefsFreeLimit,
        _kPrefsGiftCodes,
        _kPrefsRedeemedCodes,
        _kPrefsLockEnabled,
      ]) {
        await prefs.remove(key);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persistAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsPhone, _account!.phone);
    await prefs.setString(_kPrefsPasswordHash, _account!.passwordHash);
    await prefs.setString(_kPrefsDisplayName, _account!.displayName ?? '');
  }

  Future<void> _persistSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsPlanCode, _subscription!.planCode);
    await prefs.setString(_kPrefsPlanLabel, _subscription!.planLabel);
    await prefs.setString(
        _kPrefsStartedAt, _subscription!.startedAtUtc.toIso8601String());
    await prefs.setString(
        _kPrefsExpiresAt, _subscription!.expiresAtUtc.toIso8601String());
    await prefs.setString(_kPrefsTxnRef, _subscription!.transactionRef);
    await prefs.setString(_kPrefsGatewayId, _subscription!.gatewayId);
  }

  Future<void> _persistGiftCodes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefsGiftCodes,
      jsonEncode(_giftCodes.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> _persistRedeemed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsRedeemedCodes, jsonEncode(_redeemedCodes));
  }

  /// Empreinte SHA-256 (via `package:crypto` officiel).
  static String hashPassword(String password) {
    if (password.isEmpty) return '';
    final digest = cryptolib.sha256.convert(utf8.encode(password));
    return digest.toString();
  }
}
