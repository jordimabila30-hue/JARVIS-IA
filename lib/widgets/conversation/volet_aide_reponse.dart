import 'package:flutter/material.dart';

import '../../theme/theme_jarvis.dart';

/// Messagerie d'où vient le message rapporté (simple indication pour JARVIS).
enum OrigineMessage {
  instagram('Instagram'),
  messenger('Messenger'),
  email('E-mail'),
  sms('SMS'),
  autre('Autre');

  const OrigineMessage(this.libelle);
  final String libelle;
}

/// Demande d'aide à répondre à un message reçu hors WhatsApp : le message
/// copié ou rapporté, sa messagerie, et ce que l'utilisateur veut dire.
/// Rien n'est lu dans la messagerie, rien n'y est envoyé.
class DemandeAideReponse {
  const DemandeAideReponse({
    required this.message,
    required this.origine,
    this.intention = '',
  });

  final String message;
  final OrigineMessage origine;
  final String intention;

  /// Question envoyée à JARVIS (le message reçu est cité, c'est une donnée).
  String get question {
    final de = origine == OrigineMessage.autre ? '' : ' sur ${origine.libelle}';
    final suite = intention.trim().isEmpty
        ? ''
        : '\nCe que je veux répondre : ${intention.trim()}';
    return 'Aide-moi à répondre à ce message que j’ai reçu$de. Propose une '
        'réponse naturelle que je pourrai copier.\n'
        '« ${message.trim()} »$suite';
  }
}

/// Volet « Répondre à un message reçu » ; null si fermé sans envoi.
Future<DemandeAideReponse?> afficherVoletAideReponse(BuildContext context) =>
    showModalBottomSheet<DemandeAideReponse>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoletAideReponse(),
    );

class VoletAideReponse extends StatefulWidget {
  const VoletAideReponse({super.key});

  static const titre = 'Répondre à un message reçu';
  static const action = 'Proposer une réponse';

  @override
  State<VoletAideReponse> createState() => _VoletAideReponseState();
}

class _VoletAideReponseState extends State<VoletAideReponse> {
  final _message = TextEditingController();
  final _intention = TextEditingController();
  var _origine = OrigineMessage.instagram;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    _intention.dispose();
    super.dispose();
  }

  void _valider() => Navigator.of(context).pop(
    DemandeAideReponse(
      message: _message.text,
      origine: _origine,
      intention: _intention.text,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pret = _message.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: CouleursJarvis.coque,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: CouleursJarvis.trait)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                VoletAideReponse.titre,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CouleursJarvis.texte,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Colle ou raconte le message. JARVIS propose une réponse, '
                'rien n’est envoyé.',
                style: TextStyle(
                  fontSize: 13,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in OrigineMessage.values)
                    ChoiceChip(
                      label: Text(o.libelle),
                      selected: o == _origine,
                      onSelected: (_) => setState(() => _origine = o),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('aide-message'),
                controller: _message,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Message reçu',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('aide-intention'),
                controller: _intention,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Ce que tu veux dire (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: pret ? _valider : null,
                child: const Text(VoletAideReponse.action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
