import 'package:flutter/material.dart';

import '../../models/importation/conversation_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import '../../utils/local_date_time.dart';
import '../conversation/heure_message.dart';
import 'lecture_whatsapp_widgets.dart';

// Aperçu d'une conversation lue, présenté comme une messagerie : jours,
// bulles, médias. Affichage seulement : la conversation (messages, ordre,
// dates) n'est jamais modifiée.

/// Une ligne de l'aperçu.
sealed class ElementApercu {
  const ElementApercu();
}

/// Séparateur : le jour des messages qui suivent ; null : date illisible
/// dans l'export (le message garde alors sa date brute).
final class JourApercu extends ElementApercu {
  const JourApercu(this.jour);
  final DateTime? jour;
}

/// Un message, tel quel.
final class MessageApercu extends ElementApercu {
  const MessageApercu(this.message, {required this.debutSuite});
  final MessageWhatsApp message;

  /// Premier d'une suite du même auteur (nom affiché, coin de bulle).
  final bool debutSuite;
}

/// Plusieurs médias non importés consécutifs (même auteur, même jour, sans
/// légende) : une seule petite bulle, avec leur nombre et leurs heures.
final class MediasApercu extends ElementApercu {
  const MediasApercu(this.medias, {required this.debutSuite});
  final List<MessageWhatsApp> medias;
  final bool debutSuite;
}

/// Au moins autant de médias consécutifs pour les regrouper.
const seuilRegroupementMedias = 3;

/// Légende d'un média (lignes après le nom du fichier joint), sinon vide.
String legendeMedia(MessageWhatsApp m) {
  if (m.nomFichierMedia == null) return '';
  final lignes = m.texte.split('\n');
  return lignes.length > 1 ? lignes.skip(1).join('\n').trim() : '';
}

DateTime? _jourDe(MessageWhatsApp m) {
  final d = m.date;
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

// « Les messages et les appels sont chiffrés de bout en bout… » (et ses
// traductions) : avis de WhatsApp, sans intérêt dans l'aperçu.
final _chiffrement = RegExp(
  r'bout en bout|end-to-end|extremo a extremo|ende-zu-ende|ponta a ponta',
  caseSensitive: false,
);

/// Avis de chiffrement de WhatsApp (message système) : masqué dans
/// l'aperçu, gardé dans la conversation.
bool estAvisChiffrement(MessageWhatsApp m) =>
    m.type == TypeMessageWhatsApp.systeme && _chiffrement.hasMatch(m.texte);

bool _mediaSeul(MessageWhatsApp m) =>
    m.type == TypeMessageWhatsApp.media && legendeMedia(m).isEmpty;

/// Les lignes de l'aperçu, dans l'ordre exact de l'export. Un séparateur
/// est posé dès que le jour change (dans un sens ou dans l'autre : un
/// export peut contenir de petites inversions) : il porte toujours le jour
/// réel des messages placés juste en dessous. L'avis de chiffrement n'est
/// pas montré.
List<ElementApercu> elementsApercu(List<MessageWhatsApp> tous) {
  final messages = [
    for (final m in tous)
      if (!estAvisChiffrement(m)) m,
  ];
  final elements = <ElementApercu>[];
  var premier = true;
  DateTime? jour;
  String? auteurPrecedent;
  var i = 0;
  while (i < messages.length) {
    final m = messages[i];
    final j = _jourDe(m);
    if (premier || j != jour) {
      elements.add(JourApercu(j));
      jour = j;
      premier = false;
      auteurPrecedent = null;
    }
    final debutSuite =
        m.type != TypeMessageWhatsApp.systeme && m.auteur != auteurPrecedent;
    if (_mediaSeul(m)) {
      var fin = i + 1;
      while (fin < messages.length &&
          _mediaSeul(messages[fin]) &&
          messages[fin].auteur == m.auteur &&
          _jourDe(messages[fin]) == j) {
        fin++;
      }
      if (fin - i >= seuilRegroupementMedias) {
        elements.add(
          MediasApercu(messages.sublist(i, fin), debutSuite: debutSuite),
        );
        auteurPrecedent = m.auteur;
        i = fin;
        continue;
      }
    }
    elements.add(MessageApercu(m, debutSuite: debutSuite));
    auteurPrecedent = m.type == TypeMessageWhatsApp.systeme ? null : m.auteur;
    i++;
  }
  return elements;
}

/// Côté d'une bulle. N'indique pas qui est l'utilisateur : « Moi » sera
/// choisi à l'enregistrement.
enum CoteBulle { gauche, droite }

/// Disposition stable des auteurs : à deux, le premier qui écrit dans
/// l'export à gauche, l'autre à droite ; en groupe, tous à gauche, chacun
/// avec sa couleur.
class DispositionAuteurs {
  DispositionAuteurs(ConversationWhatsApp c, {this.moi})
    : groupe = c.estGroupe {
    if (!groupe && moi == null) {
      for (final m in c.messages) {
        final a = m.auteur;
        if (a != null && m.type != TypeMessageWhatsApp.systeme) {
          _premier = a;
          break;
        }
      }
    }
    for (var i = 0; i < c.participants.length; i++) {
      _couleurs[c.participants[i].nom] = _palette[i % _palette.length];
    }
  }

  final bool groupe;

  /// Utilisateur confirmé (pièce jointe) : ses messages à droite, ceux des
  /// autres à gauche, même en groupe. Null : disposition par défaut.
  final String? moi;
  String? _premier;
  final _couleurs = <String, Color>{};

  // Tons doux, lisibles sur l'ivoire, dans la famille de JARVIS.
  static const _palette = [
    CouleursJarvis.signal,
    Color(0xFF8A63B8),
    Color(0xFF3F7E8C),
    Color(0xFFA9606F),
    Color(0xFF6E7F3A),
    Color(0xFFA8743A),
  ];

  CoteBulle cote(String? auteur) {
    if (moi != null) return auteur == moi ? CoteBulle.droite : CoteBulle.gauche;
    return groupe || auteur == _premier ? CoteBulle.gauche : CoteBulle.droite;
  }

  Color couleur(String? auteur) => _couleurs[auteur] ?? CouleursJarvis.signal;
}

/// Séparateur de jour : petite capsule centrée (« dimanche 6 septembre
/// 2026 »).
class SeparateurJour extends StatelessWidget {
  const SeparateurJour(this.jour, {super.key});

  static const dateIllisible = 'Date non reconnue';

  final DateTime? jour;

  static String libelle(DateTime? jour) => jour == null
      ? dateIllisible
      : '${jourDeLaSemaine(jour)} ${jourEnFrancais(jour)}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: CouleursJarvis.coque.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: CouleursJarvis.trait.withValues(alpha: 0.55),
            ),
          ),
          child: Text(
            libelle(jour),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
      ),
    );
  }
}

/// Cadre commun des bulles : largeur adaptée au contenu (bornée), côté,
/// couleur, coin marqué en tête de suite, nom de l'auteur si utile.
class _Bulle extends StatelessWidget {
  /// Espace au-dessus d'une bulle (plus grand en tête de suite) : la bulle
  /// elle-même commence en dessous.
  static double margeHaut(bool debutSuite) => debutSuite ? 8 : 2;

  const _Bulle({
    required this.cote,
    required this.debutSuite,
    required this.auteur,
    required this.couleurAuteur,
    required this.compacte,
    required this.child,
  });

  final CoteBulle cote;
  final bool debutSuite;
  final String? auteur;
  final Color couleurAuteur;

  /// Médias, messages supprimés : bulle plus petite.
  final bool compacte;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final droite = cote == CoteBulle.droite;
    const rayon = Radius.circular(18);
    const coin = Radius.circular(5);
    return Padding(
      padding: EdgeInsets.only(top: margeHaut(debutSuite)),
      child: Align(
        alignment: droite ? Alignment.centerRight : Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, contraintes) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (contraintes.maxWidth * 0.8).clamp(0, 440),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Même lavande que les messages écrits dans le chat JARVIS.
                gradient: droite
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xE8ECE8FB), Color(0xDDE2E7FA)],
                      )
                    : null,
                color: droite ? null : CouleursJarvis.coque,
                borderRadius: BorderRadius.only(
                  topLeft: debutSuite && !droite ? coin : rayon,
                  topRight: debutSuite && droite ? coin : rayon,
                  bottomLeft: rayon,
                  bottomRight: rayon,
                ),
                border: Border.all(
                  color: droite
                      ? Colors.white.withValues(alpha: 0.75)
                      : CouleursJarvis.trait.withValues(alpha: 0.6),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x083A3350),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: compacte
                    ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                    : const EdgeInsets.fromLTRB(12, 7, 10, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (auteur case final nom?) ...[
                      Text(
                        nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: couleurAuteur,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Heure d'un message ; sa date brute si l'export la rend illisible.
class _Heure extends StatelessWidget {
  const _Heure(this.message);

  final MessageWhatsApp message;

  @override
  Widget build(BuildContext context) {
    final heure = switch (message.date) {
      final d? => HeureMessage(d),
      null => Text(
        message.dateBrute,
        style: const TextStyle(fontSize: 11, color: HeureMessage.couleur),
      ),
    };
    if (!message.ajoute) return heure;
    // Provenance toujours visible : collé par l'utilisateur.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'ajouté à la main',
          style: TextStyle(
            fontSize: 10.5,
            fontStyle: FontStyle.italic,
            color: HeureMessage.couleur,
          ),
        ),
        if (message.date != null || message.dateBrute.isNotEmpty) ...[
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: HeureMessage.couleur),
          ),
          heure,
        ],
      ],
    );
  }
}

/// Un message de l'aperçu : texte (retours à la ligne d'origine), média
/// non importé (petite bulle), message supprimé, ou événement système.
class BulleApercu extends StatelessWidget {
  /// Espace au-dessus de la bulle (pour aligner un élément sur la bulle).
  static double margeHaut(bool debutSuite) => _Bulle.margeHaut(debutSuite);

  const BulleApercu({
    super.key,
    required this.message,
    required this.cote,
    required this.debutSuite,
    this.auteur,
    this.couleurAuteur = CouleursJarvis.signal,
  });

  static const mediaNonImporte = 'Média non importé';
  static const supprime = 'Message supprimé';

  final MessageWhatsApp message;
  final CoteBulle cote;
  final bool debutSuite;

  /// Nom affiché en tête de bulle (null : pas utile).
  final String? auteur;
  final Color couleurAuteur;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.type == TypeMessageWhatsApp.systeme) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 4),
        child: Text(
          m.texte,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
      );
    }
    final legende = m.type == TypeMessageWhatsApp.media ? legendeMedia(m) : '';
    final Widget contenu = switch (m.type) {
      TypeMessageWhatsApp.supprime => _Ligne(
        icone: Icons.block_rounded,
        texte: supprime,
        heure: _Heure(m),
      ),
      TypeMessageWhatsApp.media when legende.isEmpty => _Ligne(
        icone: iconeMedia(m.typeMedia),
        texte: mediaNonImporte,
        heure: _Heure(m),
      ),
      TypeMessageWhatsApp.media => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Ligne(icone: iconeMedia(m.typeMedia), texte: mediaNonImporte),
          const SizedBox(height: 4),
          _TexteAvecHeure(texte: legende, heure: _Heure(m)),
        ],
      ),
      _ => _TexteAvecHeure(texte: m.texte, heure: _Heure(m)),
    };
    return _Bulle(
      cote: cote,
      debutSuite: debutSuite,
      auteur: auteur,
      couleurAuteur: couleurAuteur,
      compacte:
          m.type == TypeMessageWhatsApp.supprime ||
          (m.type == TypeMessageWhatsApp.media && legende.isEmpty),
      child: contenu,
    );
  }

  static IconData iconeMedia(TypeMediaWhatsApp? type) => switch (type) {
    TypeMediaWhatsApp.image => Icons.image_outlined,
    TypeMediaWhatsApp.video => Icons.videocam_outlined,
    TypeMediaWhatsApp.vocal ||
    TypeMediaWhatsApp.audio => Icons.mic_none_rounded,
    TypeMediaWhatsApp.document => Icons.description_outlined,
    TypeMediaWhatsApp.contact => Icons.person_outline,
    TypeMediaWhatsApp.autocollant ||
    TypeMediaWhatsApp.gif => Icons.emoji_emotions_outlined,
    _ => Icons.attach_file_rounded,
  };
}

/// Plusieurs médias non importés consécutifs : « 4 médias non importés »,
/// avec la plage horaire réelle (« 21:01 – 21:04 ») pour les situer.
class BulleMediasGroupes extends StatelessWidget {
  const BulleMediasGroupes({
    super.key,
    required this.medias,
    required this.cote,
    required this.debutSuite,
    this.auteur,
    this.couleurAuteur = CouleursJarvis.signal,
  });

  final List<MessageWhatsApp> medias;
  final CoteBulle cote;
  final bool debutSuite;
  final String? auteur;
  final Color couleurAuteur;

  static String libelle(int n) => '${nombreEnFrancais(n)} médias non importés';

  /// « 21:01 » ou « 21:01 – 21:04 » (heures réelles, dans l'ordre).
  static String? plage(List<MessageWhatsApp> medias) {
    final dates = [for (final m in medias) ?m.date];
    if (dates.isEmpty) return null;
    final debut = heureCourte(dates.first), fin = heureCourte(dates.last);
    return debut == fin ? debut : '$debut – $fin';
  }

  @override
  Widget build(BuildContext context) {
    final heures = plage(medias);
    return _Bulle(
      cote: cote,
      debutSuite: debutSuite,
      auteur: auteur,
      couleurAuteur: couleurAuteur,
      compacte: true,
      child: _Ligne(
        icone: Icons.perm_media_outlined,
        texte: libelle(medias.length),
        heure: heures == null
            ? null
            : Text(
                heures,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  letterSpacing: 0.4,
                  color: HeureMessage.couleur,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
      ),
    );
  }
}

/// Icône, libellé discret, heure : sur une ligne (passe à la ligne si
/// l'espace manque).
class _Ligne extends StatelessWidget {
  const _Ligne({required this.icone, required this.texte, this.heure});

  final IconData icone;
  final String texte;
  final Widget? heure;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 2,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 16, color: CouleursJarvis.texteSecondaire),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                texte,
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
            ),
          ],
        ),
        ?heure,
      ],
    );
  }
}

/// Texte d'un message, l'heure en bas à droite : sur la dernière ligne si
/// elle y tient, sinon juste en dessous (comme dans une messagerie).
class _TexteAvecHeure extends StatelessWidget {
  const _TexteAvecHeure({required this.texte, required this.heure});

  final String texte;
  final Widget heure;

  static const _style = TextStyle(
    fontSize: 14.5,
    height: 1.4,
    color: CouleursJarvis.texte,
  );

  @override
  Widget build(BuildContext context) {
    // Place réservée au bout du texte pour l'heure (suit la taille du
    // texte choisie par l'utilisateur).
    final reserve = MediaQuery.textScalerOf(context).scale(44);
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            text: texte,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(width: reserve, height: 12),
              ),
            ],
          ),
          style: _style,
        ),
        Positioned(right: 0, bottom: 1, child: heure),
      ],
    );
  }
}
