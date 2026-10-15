import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'freemium_core.dart';
import 'ledger_api.dart';

/// ---------------------------------------------------------------------------
/// Interface utilisateur Freemium — écrans autonomes.
///
/// Consomme exclusivement l'API du store canonique `FreemiumStore.instance`
/// (défini dans `freemium_core.dart`). Aucun lien vers `main.dart` :
/// l'app principale appelle ces écrans, pas l'inverse.
/// ---------------------------------------------------------------------------

const Color _omAccent = Color(0xFF00479D);   // bleu Orange Money
const Color _waveAccent = Color(0xFF1AA3A6);    // turquoise Wave
const Color _premiumGreen = Color(0xFF0D4A3E);

String _price(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]} ',
    );

/// Texte principal : sombre en mode clair, très clair en mode sombre
/// (lisibilité garantie quel que soit le thème).
Color _textMain(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE9F0ED)
        : const Color(0xFF1C1F1E);

/// Texte secondaire (gris) adapté au thème.
Color _textSub(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF9EB0A9)
        : const Color(0xFF67706D);

/// Surface des cartes : crème en mode clair, vert très foncé en mode sombre.
Color _surfaceCard(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1B2E29)
        : const Color(0xFFF5F1E8);

/// Fond de page adapté au thème (crème / émeraude très sombre).
Color _pageSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0E1A16)
        : const Color(0xFFF5F1E8);

/// Ligne de bordure des cartes adaptée au thème.
Color _lineColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2E443C)
        : const Color(0xFFE0DED6);

/// Vert premium utilisé en texte : plus lumineux en mode sombre.
Color _premiumText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF57B6A0)
        : _premiumGreen;

/// Page principale « Freemium » : expose l'état du compte et de l'abonnement
/// avec des actions (se connecter, s'abonner, mon abonnement, se déconnecter).
class FreemiumHubPage extends StatelessWidget {
  const FreemiumHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FreemiumStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accès Premium'),
        backgroundColor: _premiumGreen,
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final sub = store.subscription;
          final isPremiumLive = sub?.isActive ?? false;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== Bandeau statut =====
                _StatusBanner(premium: isPremiumLive, store: store),
                const SizedBox(height: 18),
                // ===== Compte =====
                _AccountCard(store: store),
                const SizedBox(height: 18),
                // ===== Actions =====
                if (store.isLoggedIn && !isPremiumLive)
                  OutlinedButton.icon(
                    onPressed: () => _openSubscribe(context),
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text('S\'abonner maintenant'),
                  ),
                if (isPremiumLive) ...[
                  OutlinedButton.icon(
                    onPressed: () => _openMySubscription(context),
                    icon: const Icon(Icons.event_available),
                    label: const Text('Voir mon abonnement'),
                  ),
                ],
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 6),
                // ===== Espace promoteur (gestion des accès offerts) =====
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PromoterGatePage(),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Espace promoteur'),
                  style: TextButton.styleFrom(
                    foregroundColor: _textSub(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSubscribe(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlansPage()),
    );
  }

  void _openMySubscription(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MySubscriptionPage()),
    );
  }
}

/// Bandeau vert « Abonnement actif » ou gris « Aucun abonnement ».
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.premium, required this.store});

  final bool premium;
  final FreemiumStore store;

  @override
  Widget build(BuildContext context) {
    final green = premium;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: green
            ? const Color(0xFF0D4A3E)
            : _surfaceCard(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            green ? Icons.verified_rounded : Icons.lock_rounded,
            color: green ? const Color(0xFF7FD6B0) : _textSub(context),
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  green
                      ? '🟢 Abonnement actif'
                      : '🔒 Aucun abonnement actif',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: green ? Colors.white : _textMain(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  green
                      ? 'Jours restants : ${store.daysRemaining} j'
                      : '3 audios gratuits par catégorie · illimité après abonnement',
                  style: TextStyle(
                    fontSize: 13,
                    color: green ? Colors.white70 : _textSub(context),
                  ),
                ),
              ],
            ),
          ),
          if (green)
            IconButton(
              tooltip: 'Détails',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MySubscriptionPage(),
                  ),
                );
              },
              icon: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          if (!green)
            IconButton(
              tooltip: 'S\'abonner',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlansPage()),
                );
              },
              icon: Icon(Icons.arrow_forward, color: _textSub(context)),
            ),
        ],
      ),
    );
  }
}

/// Carte compte : connecté → profil + déconnexion ; sinon → se connecter.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.store});

  final FreemiumStore store;

  @override
  Widget build(BuildContext context) {
    final account = store.account;
    final isLoggedIn = store.isLoggedIn;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: _lineColor(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: isLoggedIn
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _premiumGreen,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account?.phone ?? 'Utilisateur',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (account?.displayName != null)
                            Text(account!.displayName!,
                                style: TextStyle(
                                    fontSize: 13, color: _textSub(context))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => store.logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Se déconnecter'),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Text(
                  'Créez un compte pour gérer votre abonnement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSub(context)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AuthPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Se connecter / Créer un compte'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Page connexion / inscription (compte local).
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _registerMode = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = FreemiumStore.instance;
    String? err;
    if (_registerMode) {
      err = await store.register(
        phone: _phone.text,
        password: _password.text,
        displayName: _displayName.text,
      );
    } else {
      err = await store.login(
        phone: _phone.text,
        password: _password.text,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_registerMode ? 'Créer un compte' : 'Connexion'),
        backgroundColor: _premiumGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.account_circle_rounded,
                size: 72, color: _premiumText(context)),
            const SizedBox(height: 8),
            const Text(
              'Imam Madou Koné',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 24),
            if (_registerMode)
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(
                  labelText: 'Nom / prénom (optionnel)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            if (_registerMode) const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '07 00 00 00 00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                helperText: '6 caractères minimum · jamais stocké en clair',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () =>
                      setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_registerMode ? 'Créer le compte' : 'Se connecter'),
              style: FilledButton.styleFrom(
                backgroundColor: _premiumGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _registerMode = !_registerMode;
                _error = null;
              }),
              child: Text(_registerMode
                  ? 'J\'ai déjà un compte — me connecter'
                  : 'Pas de compte ? Créer un compte'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page de choix de la formule d'abonnement.
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choisir une formule'),
        backgroundColor: _premiumGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Accès illimité à tous les audios, toutes catégories.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: _textSub(context)),
          ),
          const SizedBox(height: 18),
          for (final plan in SubscriptionPlan.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PlanCard(
                plan: plan,
                onChoose: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentPage(plan: plan),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Paiement après confirmation du code reçu.',
              style: TextStyle(fontSize: 12, color: _textSub(context)),
            ),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          // ===== Code offert : simple icône discrète =====
          Center(
            child: IconButton.filledTonal(
              onPressed: () => _redeemGiftCodeDialog(context),
              icon: const Icon(Icons.key_rounded),
              iconSize: 28,
              tooltip: 'J\'ai un code offert (accès gratuit)',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF0D4A3E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ouvre la boîte de dialogue d'activation d'un code d'accès offert.
  Future<void> _redeemGiftCodeDialog(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎁 Code offert'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'IMMKG-XXXX-XXXX-XXXX',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: _premiumGreen),
            child: const Text('Activer'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    final store = FreemiumStore.instance;
    final err = await store.redeemGiftCode(code);
    if (!context.mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Accès offert activé ! Profitez de tous les audios.'),
          backgroundColor: Color(0xFF0D4A3E),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MySubscriptionPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ $err')),
      );
    }
  }
}

/// Carte d'une formule (prix formaté, durée, accroche).
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onChoose});

  final SubscriptionPlan plan;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceCard(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onChoose,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _premiumGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    plan.code.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.tagline,
                      style: TextStyle(
                          fontSize: 12, color: _textSub(context)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_price(plan.priceFcfa)} F CFA',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _premiumGreen,
                    ),
                  ),
                  Text(
                    plan.durationDays == 30
                        ? '30 jours'
                        : plan.durationDays == 90
                            ? '90 jours'
                            : '365 jours',
                    style: TextStyle(
                      fontSize: 11,
                      color: _textSub(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Page de paiement : choix Orange Money / Wave + n° 77 92 65 87 + code.
class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key, required this.plan});

  final SubscriptionPlan plan;

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  PaymentGateway _selected = const OrangeMoneyGateway();
  final _proof = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _proof.dispose();
    super.dispose();
  }

  Future<void> _chooseGateway() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Choisir le moyen de paiement',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone, color: _omAccent),
              title: const Text('Orange Money'),
              subtitle: const Text('Envoyer au 77 92 65 87'),
              onTap: () => Navigator.pop(context, 'om'),
            ),
            ListTile(
              leading: const Icon(Icons.waves, color: _waveAccent),
              title: const Text('Wave'),
              subtitle: const Text('Envoyer au 77 92 65 87'),
              onTap: () => Navigator.pop(context, 'wave'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice != null && mounted) {
      setState(() {
        _selected = choice == 'om'
            ? const OrangeMoneyGateway()
            : const WaveGateway();
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final store = FreemiumStore.instance;
    // Activation UNIQUEMENT si la preuve (code) est réellement confirmée.
    final ok = await store.activateSubscription(
      plan: widget.plan,
      gateway: _selected,
      proof: _proof.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _success =
            '🎉 Abonnement ${widget.plan.label} activé avec succès !';
      } else {
        _error = 'Code de confirmation invalide. '
            'Vérifiez le code reçu après le paiement.';
      }
    });
    if (ok) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MySubscriptionPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOm = _selected is OrangeMoneyGateway;
    return Scaffold(
      appBar: AppBar(
        title: Text('Paiement — ${widget.plan.label}'),
        backgroundColor: _premiumGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Récapitulatif
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceCard(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text('${widget.plan.label} · ${widget.plan.tagline}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  Text('${_price(widget.plan.priceFcfa)} F CFA',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: _premiumText(context))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Moyen de paiement
            ListenableBuilder(
              listenable: FreemiumStore.instance,
              builder: (context, _) {
                return OutlinedButton(
                  onPressed: _chooseGateway,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.smartphone,
                        color: isOm ? _omAccent : _waveAccent,
                      ),
                      const SizedBox(width: 10),
                      Text('${_selected.name} → 77 92 65 87'),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // Étapes
            Text('Comment ça marche ?',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textMain(context))),
            const SizedBox(height: 8),
            _Step(num: '1', text: 'Envoyez ${_price(widget.plan.priceFcfa)} F CFA par ${_selected.name} au 77 92 65 87'),
            const SizedBox(height: 6),
            const _Step(num: '2', text: 'Recevez un code de confirmation (ex. IMMK-1234)'),
            const SizedBox(height: 6),
            _Step(
                num: '3',
                text:
                    'Après avoir reçu le code, saisissez-le ci-dessous. Paiement vérifié avant activation.'),
            const SizedBox(height: 18),
            TextField(
              controller: _proof,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code de confirmation',
                hintText: 'IMMK-1234',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!,
                  style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: const Text('Confirmer et activer'),
              style: FilledButton.styleFrom(
                backgroundColor: _premiumGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '🔒 Aucun déblocage sans code valide. '
              'L\'activation n\'a lieu qu\'après vérification du paiement.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _textSub(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.num, required this.text});

  final String num;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _premiumGreen,
          ),
          child: Center(
            child: Text(num,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

/// Page « Mon abonnement » : statut, formule, dates, jours restants.
class MySubscriptionPage extends StatelessWidget {
  const MySubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FreemiumStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon abonnement'),
        backgroundColor: _premiumGreen,
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final sub = store.subscription;
          final active = sub?.isActive ?? false;
          if (!active || sub == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 64, color: _textSub(context)),
                    const SizedBox(height: 12),
                    const Text('🔒 Aucun abonnement actif',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Abonnez-vous pour accéder à l\'intégralité des '
                      'audios, toutes catégories.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textSub(context)),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PlansPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.workspace_premium),
                      label: const Text('Voir les abonnements'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _premiumGreen,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final days = store.daysRemaining;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D4A3E),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: Color(0xFF7FD6B0), size: 44),
                    const SizedBox(height: 6),
                    const Text('🟢 Abonnement actif',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(
                      '$days jour${days > 1 ? 's' : ''} restant${days > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('depuis le ${_fmtLocal(sub.startedAtUtc.toLocal())}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _InfoRow(label: 'Formule', value: sub.planLabel),
              _InfoRow(label: 'Début', value: _fmtLocal(sub.startedAtUtc.toLocal())),
              _InfoRow(
                  label: 'Expiration',
                  value: _fmtLocal(sub.expiresAtUtc.toLocal())),
              _InfoRow(label: 'Référence', value: sub.transactionRef),
              _InfoRow(
                label: 'Moyen de paiement',
                value: sub.gatewayId == 'gift'
                    ? 'Code offert (promoteur)'
                    : sub.gatewayId,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _fmtLocal(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} '
        '${two(l.hour)}h${two(l.minute)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: _textSub(context))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Boîte de dialogue d'audio verrouillé.
///
/// Affichée quand un utilisateur non-abonné tente d'écouter un audio
/// au-delà des 3 gratuits de sa catégorie.
/// --------------------------------------------------------------------------
/// ESPACE PROMOTEUR
///
/// Compte distinct des comptes utilisateurs : protégé par un PIN
/// (`kPromoterPin` dans `freemium_core.dart`), il permet de générer des
/// codes d'accès offert pour la famille / les proches. Les autres
/// utilisateurs continuent de payer l'abonnement via OM / Wave.
/// --------------------------------------------------------------------------
class PromoterGatePage extends StatefulWidget {
  const PromoterGatePage({super.key});

  @override
  State<PromoterGatePage> createState() => _PromoterGatePageState();
}

class _PromoterGatePageState extends State<PromoterGatePage> {
  final _pin = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final store = FreemiumStore.instance;
    if (!store.verifyPromoterPin(_pin.text)) {
      setState(() => _error = 'PIN incorrect. Accès refusé.');
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PromoterPanelPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace promoteur'),
        backgroundColor: const Color(0xFF1B2A3A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.admin_panel_settings_rounded,
                size: 56,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF7FD6B0)
                    : const Color(0xFF1B2A3A)),
            const SizedBox(height: 12),
            const Text(
              'Accès réservé au promoteur',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Saisissez votre code PIN pour gérer les codes '
              'd\'accès offert (famille, proches).\n\n'
              'Les autres utilisateurs continuent de payer '
              'l\'abonnement via OM / Wave.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSub(context)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pin,
              obscureText: _obscure,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                hintText: 'Code PIN',
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Entrer'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A3A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau du promoteur : génération et gestion des codes d'accès offert.
class PromoterPanelPage extends StatefulWidget {
  const PromoterPanelPage({super.key});

  @override
  State<PromoterPanelPage> createState() => _PromoterPanelPageState();
}

class _PromoterPanelPageState extends State<PromoterPanelPage> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final store = FreemiumStore.instance;
    final gc = await store.createGiftCode(note: _note.text);
    _note.clear();
    if (!mounted) return;
    setState(() => _busy = false);
    await Clipboard.setData(ClipboardData(text: gc.code));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎁 Code offert créé !'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Le code est copié dans le presse-papiers. Envoyez-le à la '
              'personne concernée (WhatsApp, SMS...). Elle le saisira dans '
              '« J\'ai un code offert » pour un accès gratuit.',
              style: TextStyle(fontSize: 13, color: _textSub(context)),
            ),
            const SizedBox(height: 14),
            SelectableText(
              gc.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = FreemiumStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panneau promoteur'),
        backgroundColor: const Color(0xFF1B2A3A),
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final codes = store.giftCodes;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2A3A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_user_rounded,
                          color: Color(0xFF7FD6B0), size: 30),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connecté · Promoteur',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Gérez les accès gratuits offerts à vos '
                              'proches. Les autres paient l\'abonnement.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // ===== Commutateur de verrouillage (piloté par le promoteur)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: store.lockEnabled
                        ? const Color(0xFF3E3016)
                        : const Color(0xFF123B2B),
                    border: Border.all(
                      color: store.lockEnabled
                          ? const Color(0xFFEF9A4D)
                          : const Color(0xFF2E7D32),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        store.lockEnabled
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: store.lockEnabled
                            ? const Color(0xFFE65100)
                            : const Color(0xFF2E7D32),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Verrouillage des abonnements',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              store.lockEnabled
                                  ? 'ACTIF : limité à 3 gratuits par catégorie '
                                      'sans abonnement.'
                                  : 'DÉSACTIVÉ : tout le monde écoute '
                                      'librement (mode test).',
                              style: TextStyle(
                                  fontSize: 11.5, color: _textSub(context)),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: store.lockEnabled,
                        onChanged: (v) => store.setLockEnabled(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // ===== Base des utilisateurs (registre central du promoteur)
                Material(
                  color: _surfaceCard(context),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const UsersLedgerPage(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.group_rounded,
                              color: const Color(0xFF2E7D32), size: 30),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Base des utilisateurs',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Tous les inscrits et leurs abonnements '
                                  '(téléphone, statut, jours restants).',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: _textSub(context)),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: const Color(0xFF2E7D32)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Pour qui ? (facultatif)',
                    hintText: 'Ex. Tonton Moussa, Cousine Aïcha...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: const Icon(Icons.add_card),
                  label:
                      Text(_busy ? 'Génération...' : 'Générer un code offert'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D4A3E),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  codes.isEmpty
                      ? 'Aucun code généré pour le moment.'
                      : 'Codes offerts (${codes.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final g in codes)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            g.code,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Créé le ${_fmtDate(g.atUtc.toLocal())}'
                            '${g.note == null ? '' : ' · ${g.note}'}',
                            style: TextStyle(
                                fontSize: 12, color: _textSub(context)),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  await Clipboard.setData(
                                      ClipboardData(text: g.code));
                                  messenger.showSnackBar(const SnackBar(
                                    content: Text('Code copié ✅'),
                                    duration: Duration(seconds: 2),
                                  ));
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copier'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  await store.removeGiftCode(g.code);
                                },
                                icon: const Icon(Icons.delete_outline,
                                    size: 16),
                                label: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'ℹ️ Chaque code vaut un accès gratuit illimité (10 ans) '
                  'et ne fonctionne qu\'une fois par téléphone. '
                  'Les utilisateurs sans code paient l\'abonnement '
                  'via OM / Wave.',
                  style: TextStyle(fontSize: 12, color: _textSub(context)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/// Écran « Base des utilisateurs » : tous les inscrits et leurs abonnements,
/// collectés depuis les téléphones via l'API du registre du promoteur.
class UsersLedgerPage extends StatefulWidget {
  const UsersLedgerPage({super.key});

  @override
  State<UsersLedgerPage> createState() => _UsersLedgerPageState();
}

class _UsersLedgerPageState extends State<UsersLedgerPage> {
  List<RemoteUser>? _users;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = _users == null;
      _error = null;
    });
    try {
      final users = await UsersLedger.fetchAll();
      users.sort((a, b) {
        final da = a.firstSeenUtc;
        final db = b.firstSeenUtc;
        if (da == null) return db == null ? 0 : 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageSurface(context),
      appBar: AppBar(
        title: const Text('Base des utilisateurs'),
        backgroundColor: const Color(0xFF1B2A3A),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text('Chargement de la base…',
                style: TextStyle(color: _textSub(context))),
          ],
        ),
      );
    }
    if (_error != null && _users == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48, color: _textSub(context)),
              const SizedBox(height: 12),
              const Text(
                'Impossible de joindre le serveur de collecte.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _textSub(context)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D4A3E),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final users = _users ?? const <RemoteUser>[];
    final active = users
        .where((u) => u.subscription?.isActive ?? false)
        .length;
    final gifted =
        users.where((u) => u.subscription?.isGift ?? false).length;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _statsRow(users.length, active, gifted),
          const SizedBox(height: 16),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.person_off_outlined,
                        size: 40, color: _textSub(context)),
                    const SizedBox(height: 10),
                    Text(
                      'Aucun utilisateur inscrit pour le moment.\n'
                      'Les inscriptions des téléphones apparaîtront ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textSub(context)),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final u in users) _userCard(u),
        ],
      ),
    );
  }

  Widget _statsRow(int total, int active, int gifted) {
    Widget cell(int value, String label, IconData icon, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _surfaceCard(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _lineColor(context)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5, color: _textSub(context))),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell(total, 'Inscrits', Icons.people_alt_rounded,
            const Color(0xFF0D4A3E)),
        const SizedBox(width: 8),
        cell(active, 'Actifs', Icons.card_membership_rounded,
            const Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        cell(gifted, 'Offerts', Icons.card_giftcard_rounded,
            const Color(0xFFB26A00)),
      ],
    );
  }

  Widget _userCard(RemoteUser u) {
    final sub = u.subscription;
    final hasName = (u.displayName?.trim().isNotEmpty ?? false);
    final name = hasName ? u.displayName!.trim() : 'Utilisateur';
    final initial = hasName ? name[0].toUpperCase() : '?';

    final Color badgeColor;
    final IconData badgeIcon;
    final String badgeText;
    if (sub == null) {
      badgeColor = const Color(0xFF616161);
      badgeIcon = Icons.lock_outline_rounded;
      badgeText = 'Aucun abonnement';
    } else if (sub.isGift) {
      badgeColor = const Color(0xFF8A6D00);
      badgeIcon = Icons.card_giftcard_rounded;
      badgeText = sub.isActive ? 'Offert · Actif' : 'Offert · Expiré';
    } else if (sub.isActive) {
      badgeColor = const Color(0xFF2E7D32);
      badgeIcon = Icons.check_circle_rounded;
      badgeText = '${sub.planLabel} · Actif · ${sub.daysRemaining} j restants';
    } else {
      badgeColor = const Color(0xFFB3261E);
      badgeIcon = Icons.error_outline_rounded;
      badgeText = '${sub.planLabel} · Expiré';
    }

    final infoParts = <String>[
      'Depuis le ${_fmtDate(u.firstSeenUtc)}',
      if (sub != null && sub.gateway.isNotEmpty)
        sub.isGift ? 'via code offert' : 'via ${_gatewayLabel(sub.gateway)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _lineColor(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF0D4A3E),
              child: Text(
                initial,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(u.phone,
                      style: TextStyle(
                          fontSize: 12.5, color: _textSub(context))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 14, color: badgeColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            badgeText,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: badgeColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    infoParts.join(' · '),
                    style: TextStyle(
                        fontSize: 11, color: _textSub(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _gatewayLabel(String g) {
    switch (g) {
      case 'orange_money':
        return 'Orange Money';
      case 'wave':
        return 'Wave';
      case 'gift':
        return 'code offert';
      default:
        return g;
    }
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

Future<void> showLockedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('🔒 Contenu réservé aux abonnés'),
      content: const Text(
        'Vous avez déjà écouté les 3 audios gratuits de cette catégorie.\n\n'
        'Abonnez-vous pour débloquer l\'intégralité des audios, '
        'toutes catégories, en 30 / 90 / 365 jours.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(
              ctx,
              MaterialPageRoute(builder: (_) => const PlansPage()),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: _premiumGreen,
          ),
          child: const Text('S\'abonner maintenant'),
        ),
      ],
    ),
  );
}

/// Indique si un audio est verrouillé pour l'utilisateur non-abonné.
///
/// Le verrouillage est piloté par le **commutateur promoteur**
/// (`store.lockEnabled`) : activable / désactivable à tout moment depuis
/// l'Espace promoteur, sans recompiler. Position **au sein de la catégorie** :
/// les 3 premiers sont gratuits, les suivants (position >= 3) sont
/// verrouillés sans abonnement.
bool isAudioLockedForUser({
  required String category,
  required int positionInCategory,
}) {
  final store = FreemiumStore.instance;
  if (!store.lockEnabled) return false;
  if (store.isPremium) return false;
  return positionInCategory >= 3;
}
