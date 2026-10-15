import 'package:flutter_test/flutter_test.dart';
import 'package:imam_madou_kone/freemium/freemium_core.dart';
import 'package:imam_madou_kone/freemium/freemium_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests du compte promoteur et des codes d'accès offert.
void main() {
  final store = FreemiumStore.instance;
  final codeFormat =
      RegExp(r'^IMMKG-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.resetAll();
    await store.load();
  });

  group('Compte promoteur', () {
    test('le PIN promoteur est vérifié', () {
      expect(store.verifyPromoterPin(kPromoterPin), isTrue);
      expect(store.verifyPromoterPin('000000'), isFalse);
      expect(store.verifyPromoterPin(''), isFalse);
    });

    test('le PIN est distinct des comptes utilisateurs', () {
      expect(kPromoterPin, isNotEmpty);
      expect(store.isLoggedIn, isFalse);
    });
  });

  group('Génération des codes offerts', () {
    test('crée un code imprévisible au bon format', () async {
      final gc = await store.createGiftCode(note: 'Tonton');
      expect(codeFormat.hasMatch(gc.code), isTrue);
      expect(gc.note, 'Tonton');
      expect(store.giftCodes.length, 1);
      expect(store.giftCodes.first.code, gc.code);
    });

    test('génère des codes différents à chaque appel', () async {
      final a = await store.createGiftCode();
      final b = await store.createGiftCode();
      expect(a.code, isNot(b.code));
      expect(store.giftCodes.length, 2);
    });

    test('supprime un code de la liste', () async {
      final gc = await store.createGiftCode();
      await store.removeGiftCode(gc.code);
      expect(store.giftCodes, isEmpty);
    });
  });

  group('Activation d\'un code (bénéficiaire)', () {
    test('active un accès gratuit illimité', () async {
      final gc = await store.createGiftCode();
      final err = await store.redeemGiftCode(gc.code);
      expect(err, isNull);
      expect(store.isPremium, isTrue);
      expect(store.subscription!.planLabel, 'Accès offert');
      expect(store.daysRemaining, greaterThan(3649));
    });

    test('refuse un format invalide', () async {
      final err = await store.redeemGiftCode('BONJOUR');
      expect(err, isNotNull);
      expect(store.isPremium, isFalse);
    });

    test('refuse un code déjà utilisé sur cet appareil', () async {
      final gc = await store.createGiftCode();
      await store.redeemGiftCode(gc.code);
      final second = await store.redeemGiftCode(gc.code);
      expect(second, contains('sur cet appareil'));
    });

    test('refuse si un abonnement est déjà actif', () async {
      final a = await store.createGiftCode();
      final b = await store.createGiftCode();
      await store.redeemGiftCode(a.code);
      final err = await store.redeemGiftCode(b.code);
      expect(err, contains('abonnement actif'));
    });

    test('les codes survivent au rechargement du store', () async {
      final gc = await store.createGiftCode(note: 'Maman');
      await store.redeemGiftCode(gc.code);
      final fresh = FreemiumStore.instance;
      await fresh.load();
      expect(fresh.giftCodes.length, 1);
      expect(fresh.giftCodes.first.code, gc.code);
      expect(fresh.isPremium, isTrue);
    });
  });

  group('Commutateur de verrouillage (panneau promoteur)', () {
    test('état initial = kDefaultAudioLockEnabled', () {
      expect(store.lockEnabled, kDefaultAudioLockEnabled);
    });

    test('setLockEnabled persiste après rechargement', () async {
      await store.setLockEnabled(true);
      expect(store.lockEnabled, isTrue);
      final fresh = FreemiumStore.instance;
      await fresh.load();
      expect(fresh.lockEnabled, isTrue);
      await fresh.setLockEnabled(false);
      expect(fresh.lockEnabled, isFalse);
    });

    test('isAudioLockedForUser obéit au commutateur', () async {
      // Verrou OFF : aucun audio n'est verrouillé, même au-delà des gratuits.
      await store.setLockEnabled(false);
      expect(isAudioLockedForUser(category: 'X', positionInCategory: 50),
          isFalse);
      await store.setLockEnabled(true);
      // Verrou ON : les 3 premiers restent gratuits, le 4e est verrouillé.
      expect(isAudioLockedForUser(category: 'X', positionInCategory: 0),
          isFalse);
      expect(isAudioLockedForUser(category: 'X', positionInCategory: 2),
          isFalse);
      expect(isAudioLockedForUser(category: 'X', positionInCategory: 3),
          isTrue);
      // Un abonné actif n'est jamais verrouillé.
      final gc = await store.createGiftCode();
      await store.redeemGiftCode(gc.code);
      expect(isAudioLockedForUser(category: 'X', positionInCategory: 99),
          isFalse);
    });

    test('resetAll rétablit la valeur par défaut', () async {
      await store.setLockEnabled(true);
      await store.resetAll();
      expect(store.lockEnabled, kDefaultAudioLockEnabled);
    });
  });
}