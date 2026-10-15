import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ---------------------------------------------------------------------------
/// Base des utilisateurs — registre central du promoteur.
///
/// Chaque téléphone envoie (au moment de l'inscription, de la connexion, de
/// l'abonnement ou de l'activation d'un code offert) un **résumé non
/// sensible** : téléphone, nom affiché, dates et abonnement. Le promoteur
/// consulte ensuite toute la base depuis son panneau (Espace promoteur →
/// « Base des utilisateurs »).
///
/// Cette couche est « best-effort » : la vie locale de l'app ne dépend
/// **jamais** de la disponibilité du serveur (hors-ligne = tout continue).
/// ---------------------------------------------------------------------------

/// URL de base de l'API (serveur XAMPP local du développeur par défaut).
///
/// Pour la production :
///   flutter build --dart-define=LEDGER_API_URL=https://votre-site.com/IMMK/api
const String kLedgerApiBase = String.fromEnvironment(
  'LEDGER_API_URL',
  defaultValue: 'http://192.168.1.63/IMMK/api',
);

/// Clé partagée app ↔ serveur gérant la base des utilisateurs.
///
/// ⚠️ Doit rester identique à la constante `API_TOKEN` du fichier
/// `api/users.php` déployé sur le serveur.
const String kLedgerApiToken = 'IMMK-LEDGER-2026';

/// Abonnement enregistré côté serveur.
class LedgerSubscription {
  const LedgerSubscription({
    required this.planLabel,
    required this.startedAtUtc,
    required this.expiresAtUtc,
    required this.gateway,
    required this.ref,
    required this.isGift,
  });

  final String planLabel;
  final DateTime startedAtUtc;
  final DateTime expiresAtUtc;

  /// Identifiant du moyen de paiement (`orange_money`, `wave`, `gift`…).
  final String gateway;

  /// Référence de transaction ou code offert.
  final String ref;

  /// Vrai si l'accès provient d'un code offert par le promoteur.
  final bool isGift;

  bool get isActive => DateTime.now().toUtc().isBefore(expiresAtUtc);

  /// Jours restants (0 si expiré), calculés depuis la date d'expiration.
  int get daysRemaining {
    final now = DateTime.now().toUtc();
    if (!isActive) return 0;
    final diff = expiresAtUtc.difference(now);
    return (diff.inMinutes / (24 * 60)).ceil();
  }

  factory LedgerSubscription.fromJson(Map<String, dynamic> json) {
    final started = json['startedAtUtc'] as String? ?? '';
    final expires = json['expiresAtUtc'] as String? ?? '';
    return LedgerSubscription(
      planLabel: json['planLabel'] as String? ?? '',
      startedAtUtc: started.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.parse(started),
      expiresAtUtc: expires.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.parse(expires),
      gateway: json['gateway'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      isGift: json['isGift'] == true,
    );
  }
}

/// Un utilisateur inscrit, tel qu'enregistré côté serveur.
class RemoteUser {
  const RemoteUser({
    required this.phone,
    this.displayName,
    this.firstSeenUtc,
    this.lastSeenUtc,
    this.subscription,
  });

  final String phone;
  final String? displayName;
  final DateTime? firstSeenUtc;
  final DateTime? lastSeenUtc;
  final LedgerSubscription? subscription;

  bool get hasSubscription => subscription != null;

  factory RemoteUser.fromJson(Map<String, dynamic> json) {
    final sub = json['subscription'];
    return RemoteUser(
      phone: json['phone'] as String? ?? '',
      displayName: json['displayName'] as String?,
      firstSeenUtc: _parseDate(json['firstSeenUtc']),
      lastSeenUtc: _parseDate(json['lastSeenUtc']),
      subscription:
          sub is Map<String, dynamic> ? LedgerSubscription.fromJson(sub) : null,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
}

/// Client réseau de la base des utilisateurs.
class UsersLedger {
  UsersLedger._();

  static http.Client _client = http.Client();

  /// Injecte un client factice (tests uniquement).
  @visibleForTesting
  static void overrideClient(http.Client client) => _client = client;

  static Uri get _endpoint => Uri.parse('$kLedgerApiBase/users.php');

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'X-IMMK-Token': kLedgerApiToken,
      };

  /// Envoie (best-effort) le profil et l'abonnement du téléphone courant.
  ///
  /// N'échoue **jamais** : toute erreur réseau est ignorée silencieusement
  /// pour ne jamais bloquer l'utilisateur.
  static Future<void> pushUser({
    required String phone,
    String? displayName,
    LedgerSubscription? subscription,
  }) async {
    try {
      final user = <String, dynamic>{
        'phone': phone,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
        if (subscription != null)
          'subscription': {
            'planLabel': subscription.planLabel,
            'startedAtUtc': subscription.startedAtUtc.toIso8601String(),
            'expiresAtUtc': subscription.expiresAtUtc.toIso8601String(),
            'gateway': subscription.gateway,
            'ref': subscription.ref,
            'isGift': subscription.isGift,
          },
      };
      await _client
          .post(_endpoint, headers: _headers, body: jsonEncode({'user': user}))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort : jamais de blocage ni d'erreur visible pour l'utilisateur.
    }
  }

  /// Récupère la base complète des utilisateurs (écran promoteur).
  ///
  /// Lève une exception si le serveur est injoignable ou refuse l'accès.
  static Future<List<RemoteUser>> fetchAll() async {
    final resp =
        await _client.get(_endpoint, headers: _headers).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('Serveur indisponible (HTTP ${resp.statusCode}).');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'Erreur du serveur.');
    }
    final list = decoded['users'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RemoteUser.fromJson)
        .toList();
  }
}