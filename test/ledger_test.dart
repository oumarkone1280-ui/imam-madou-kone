import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:imam_madou_kone/freemium/ledger_api.dart';

/// Tests de la « Base des utilisateurs » (registre central du promoteur) :
/// parsing des réponses serveur, calculs d'abonnement et envoi best-effort.
void main() {
  test('fetchAll parse la base renvoyée par le serveur', () async {
    final body = jsonEncode({
      'ok': true,
      'count': 2,
      'users': [
        {
          'phone': '+22370123456',
          'displayName': 'Moussa',
          'firstSeenUtc': '2026-10-01T10:00:00Z',
          'lastSeenUtc': '2026-10-07T08:00:00Z',
          'subscription': {
            'planLabel': '1 mois',
            'startedAtUtc': '2026-10-01T10:00:00Z',
            'expiresAtUtc': '2030-10-01T10:00:00Z',
            'gateway': 'orange_money',
            'ref': 'IMMK-ABCD',
            'isGift': false,
          },
        },
        {
          'phone': '+22376543210',
          'displayName': 'Aïcha',
          'firstSeenUtc': '2026-10-05T09:00:00Z',
        },
      ],
    });

    UsersLedger.overrideClient(MockClient((request) async {
      expect(request.url.toString(), endsWith('/api/users.php'));
      expect(request.headers['X-IMMK-Token'], kLedgerApiToken);
      return http.Response(body, 200,
          headers: {'content-type': 'application/json'});
    }));

    final users = await UsersLedger.fetchAll();
    expect(users, hasLength(2));

    final moussa = users.first;
    expect(moussa.phone, '+22370123456');
    expect(moussa.displayName, 'Moussa');
    expect(moussa.firstSeenUtc, DateTime.utc(2026, 10, 1, 10));
    expect(moussa.hasSubscription, isTrue);
    expect(moussa.subscription!.planLabel, '1 mois');
    expect(moussa.subscription!.gateway, 'orange_money');
    expect(moussa.subscription!.isGift, isFalse);
    expect(moussa.subscription!.isActive, isTrue);
    expect(moussa.subscription!.daysRemaining, greaterThan(1400));

    final aicha = users[1];
    expect(aicha.phone, '+22376543210');
    expect(aicha.displayName, 'Aïcha');
    expect(aicha.hasSubscription, isFalse);
  });

  test('un abonnement expiré est marqué inactif avec 0 jour restant', () {
    final sub = LedgerSubscription(
      planLabel: '1 mois',
      startedAtUtc: DateTime.utc(2020, 1, 1),
      expiresAtUtc: DateTime.utc(2020, 2, 1),
      gateway: 'wave',
      ref: 'IMMK-WXYZ',
      isGift: false,
    );
    expect(sub.isActive, isFalse);
    expect(sub.daysRemaining, 0);
  });

  test('un code offert est reconnu comme un don (isGift)', () {
    final sub = LedgerSubscription(
      planLabel: 'Accès offert',
      startedAtUtc: DateTime.utc(2026, 10, 1),
      expiresAtUtc: DateTime.utc(2036, 10, 1),
      gateway: 'gift',
      ref: 'IMMKG-AAAA-BBBB-CCCC',
      isGift: true,
    );
    expect(sub.isGift, isTrue);
    expect(sub.isActive, isTrue);
  });

  test('pushUser envoie le profil et l\'abonnement avec le bon jeton',
      () async {
    String? sentBody;
    Map<String, String>? sentHeaders;

    UsersLedger.overrideClient(MockClient((request) async {
      sentBody = request.body;
      sentHeaders = request.headers;
      return http.Response(
          jsonEncode({'ok': true, 'phone': '+22370123456'}), 200);
    }));

    await UsersLedger.pushUser(
      phone: '+22370123456',
      displayName: 'Moussa',
      subscription: LedgerSubscription(
        planLabel: '1 an',
        startedAtUtc: DateTime.utc(2026, 10, 1, 10),
        expiresAtUtc: DateTime.utc(2027, 10, 1, 10),
        gateway: 'orange_money',
        ref: 'IMMK-ABCD',
        isGift: false,
      ),
    );

    expect(sentHeaders!['X-IMMK-Token'], kLedgerApiToken);
    final decoded = jsonDecode(sentBody!) as Map<String, dynamic>;
    final user = decoded['user'] as Map<String, dynamic>;
    expect(user['phone'], '+22370123456');
    expect(user['displayName'], 'Moussa');
    final sub = user['subscription'] as Map<String, dynamic>;
    expect(sub['planLabel'], '1 an');
    expect(sub['gateway'], 'orange_money');
    expect(sub['isGift'], isFalse);
  });

  test('pushUser sans abonnement remonte seulement le profil', () async {
    String? sentBody;
    UsersLedger.overrideClient(MockClient((request) async {
      sentBody = request.body;
      return http.Response(jsonEncode({'ok': true}), 200);
    }));

    await UsersLedger.pushUser(phone: '+22370000000');

    final decoded = jsonDecode(sentBody!) as Map<String, dynamic>;
    final user = decoded['user'] as Map<String, dynamic>;
    expect(user.containsKey('subscription'), isFalse);
  });

  test('pushUser n\'échoue jamais si le serveur est injoignable', () async {
    UsersLedger.overrideClient(
      MockClient((request) async => throw http.ClientException('hors ligne')),
    );

    await UsersLedger.pushUser(phone: '+22370000000');
    // Aucune exception ne doit remonter : best-effort.
  });
}