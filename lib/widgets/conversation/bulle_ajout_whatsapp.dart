import 'package:flutter/material.dart';

import '../../services/importation/actualisation_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import '../importation/logo_whatsapp.dart';

/// Message WhatsApp collé par l'utilisateur (phase 5.1), dans le fil
/// JARVIS : reçu → à gauche, au nom de l'auteur ; envoyé → à droite,
/// « Vous → contact ». Compact, texte intégral, sans paragraphe explicatif.
/// Menu `···` : Modifier, Supprimer (messages AJOUTÉS seulement : un message
/// importé n'est jamais affiché ici).
class BulleAjoutWhatsApp extends StatelessWidget {
  const BulleAjoutWhatsApp({
    super.key,
    required this.ajout,
    this.surCorriger,
    this.surSupprimer,
    this.taille = 15,
  });

  final AjoutDansLeFil ajout;
  final Future<bool> Function(String texte)? surCorriger;
  final Future<bool> Function()? surSupprimer;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final m = ajout.message;
    final envoye = m.sens == SensMessage.envoye;
    final date = m.date;
    return Align(
      alignment: envoye ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.82).clamp(0, 560),
        ),
        child: Container(
          key: Key('bulle-ajout-${m.id}'),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(12, 7, 2, 7),
          decoration: BoxDecoration(
            color: envoye
                ? CouleursJarvis.violetPoudre.withValues(alpha: 0.85)
                : CouleursJarvis.coque,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(envoye ? 16 : 4),
              bottomRight: Radius.circular(envoye ? 4 : 16),
            ),
            border: Border.all(color: CouleursJarvis.lavande),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LogoWhatsApp(taille: 12),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            envoye ? 'Vous → ${ajout.contact}' : m.auteur,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: envoye
                                  ? CouleursJarvis.texteSecondaire
                                  : CouleursJarvis.violet,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.texte,
                      style: TextStyle(
                        fontSize: taille - 0.5,
                        height: 1.4,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    if (date != null)
                      Text(
                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} '
                        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                  ],
                ),
              ),
              if (surCorriger != null || surSupprimer != null)
                PopupMenuButton<String>(
                  key: Key('menu-ajout-${m.id}'),
                  tooltip: 'Options',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                  color: CouleursJarvis.coque,
                  onSelected: (v) => v == 'modifier'
                      ? _modifier(context)
                      : _supprimer(context),
                  itemBuilder: (context) => [
                    if (surCorriger != null)
                      const PopupMenuItem(
                        value: 'modifier',
                        child: Text('Modifier'),
                      ),
                    if (surSupprimer != null)
                      const PopupMenuItem(
                        value: 'supprimer',
                        child: Text('Supprimer'),
                      ),
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        m.corrige
                            ? 'Ajouté à la main · corrigé'
                            : 'Ajouté à la main',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: CouleursJarvis.texteSecondaire,
                        ),
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

  Future<void> _modifier(BuildContext context) async {
    final champ = TextEditingController(text: ajout.message.texte);
    final texte = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CouleursJarvis.coque,
        title: const Text('Modifier le message'),
        content: TextField(
          key: const Key('champ-modifier-ajout'),
          controller: champ,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('valider-modifier-ajout'),
            onPressed: () => Navigator.of(context).pop(champ.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    champ.dispose();
    if (texte != null &&
        texte.trim().isNotEmpty &&
        texte != ajout.message.texte) {
      await surCorriger?.call(texte);
    }
  }

  Future<void> _supprimer(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CouleursJarvis.coque,
        title: const Text('Supprimer ce message ajouté ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('valider-supprimer-ajout'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await surSupprimer?.call();
  }
}
