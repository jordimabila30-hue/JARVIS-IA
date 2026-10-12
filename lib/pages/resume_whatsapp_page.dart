import 'package:flutter/material.dart';

import '../models/importation/conversation_whatsapp.dart';
import '../theme/theme_jarvis.dart';
import '../utils/local_date_time.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/importation/apercu_discussion.dart';
import '../widgets/importation/lecture_whatsapp_widgets.dart';
import '../widgets/importation/logo_whatsapp.dart';

/// Résumé facultatif d'une conversation lue : son nom, son ampleur, puis
/// la discussion elle-même, présentée comme dans une messagerie (ouverte
/// sur les messages les plus récents). Aucun choix demandé ici : « Moi »
/// sera désigné à l'enregistrement. Revenir ne perd rien (la conversation
/// reste dans la page d'import).
class ResumeWhatsAppPage extends StatefulWidget {
  const ResumeWhatsAppPage({super.key, required this.conversation});

  static const titre = 'Résumé de la conversation';
  static const mediasNonImportes = 'Médias non importés';
  static const datesIncertaines = 'jour et mois des dates incertains';

  final ConversationWhatsApp conversation;

  /// « 172 messages · 3 juillet – 11 octobre 2026 ».
  static String ampleur(ConversationWhatsApp c) {
    final n = c.messages.length;
    final debut = c.debut, fin = c.fin;
    return [
      '${nombreEnFrancais(n)} message${n > 1 ? 's' : ''}',
      if (debut != null && fin != null) periode(debut, fin),
    ].join(' · ');
  }

  /// Période couverte : « 6 septembre 2026 », « 3 – 11 octobre 2026 »,
  /// « 3 juillet – 11 octobre 2026 », « 3 juillet 2020 – 11 octobre 2026 ».
  static String periode(DateTime debut, DateTime fin) {
    String jour(DateTime d) => d.day == 1 ? '1er' : '${d.day}';
    if (debut.year != fin.year) {
      return '${jourEnFrancais(debut)} – ${jourEnFrancais(fin)}';
    }
    if (debut.month != fin.month) {
      return '${jour(debut)} ${moisEnFrancais(debut)} – ${jourEnFrancais(fin)}';
    }
    if (debut.day != fin.day) return '${jour(debut)} – ${jourEnFrancais(fin)}';
    return jourEnFrancais(fin);
  }

  @override
  State<ResumeWhatsAppPage> createState() => _ResumeWhatsAppPageState();
}

class _ResumeWhatsAppPageState extends State<ResumeWhatsAppPage> {
  // Préparés une fois (parcours linéaire) ; seules les bulles visibles
  // sont construites.
  late final List<ElementApercu> _elements = elementsApercu(
    widget.conversation.messages,
  );
  late final DispositionAuteurs _disposition = DispositionAuteurs(
    widget.conversation,
  );

  Widget _element(ElementApercu e) {
    final d = _disposition;
    switch (e) {
      case JourApercu(:final jour):
        return SeparateurJour(jour);
      case MessageApercu(:final message, :final debutSuite):
        return BulleApercu(
          message: message,
          cote: d.cote(message.auteur),
          debutSuite: debutSuite,
          // L'alignement ne dit pas qui est l'utilisateur : le nom est
          // donné en tête de chaque suite.
          auteur: debutSuite ? message.auteur : null,
          couleurAuteur: d.couleur(message.auteur),
        );
      case MediasApercu(:final medias, :final debutSuite):
        final auteur = medias.first.auteur;
        return BulleMediasGroupes(
          medias: medias,
          cote: d.cote(auteur),
          debutSuite: debutSuite,
          auteur: debutSuite ? auteur : null,
          couleurAuteur: d.couleur(auteur),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final taille = MediaQuery.sizeOf(context);
    final marge = taille.width < 600 ? 12.0 : 28.0;
    final cote = taille.width > 640 + 2 * marge
        ? (taille.width - 640) / 2
        : marge;
    final secondaires = [
      if (c.nombreMedias > 0) ResumeWhatsAppPage.mediasNonImportes,
      if (c.dateIncertaine) ResumeWhatsAppPage.datesIncertaines,
    ];
    final n = _elements.length;
    return Scaffold(
      backgroundColor: CouleursJarvis.ivoire,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: degradeFondJarvis),
        child: SizedBox.expand(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(cote, 6, cote, 10),
                  child: _Entete(
                    nom: c.titre,
                    ampleur: ResumeWhatsAppPage.ampleur(c),
                    secondaire: secondaires.join(' · '),
                  ),
                ),
                Divider(
                  height: 1,
                  color: CouleursJarvis.trait.withValues(alpha: 0.6),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const DefilementSansBarre(),
                    // Inversée : ouverte sur les messages les plus récents,
                    // et virtualisée (seules les bulles visibles existent).
                    child: CustomScrollView(
                      reverse: true,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            cote,
                            8,
                            cote,
                            12 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          sliver: SliverList.builder(
                            itemCount: n,
                            itemBuilder: (context, i) =>
                                _element(_elements[n - 1 - i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Retour, puis le nom de la conversation et une ligne d'informations.
class _Entete extends StatelessWidget {
  const _Entete({
    required this.nom,
    required this.ampleur,
    required this.secondaire,
  });

  final String nom;
  final String ampleur;
  final String secondaire;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: CouleursJarvis.texte,
            minimumSize: const Size(48, 48),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const LogoWhatsApp(taille: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: const Text(
                          ResumeWhatsAppPage.titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: CouleursJarvis.texteSecondaire,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: policeAffichage,
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: CouleursJarvis.texte,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ampleur,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: CouleursJarvis.texte,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (secondaire.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaire,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
