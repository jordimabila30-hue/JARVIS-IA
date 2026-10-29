import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/importation/conversation_whatsapp.dart';
import '../models/importation/piece_jointe_whatsapp.dart';
import '../models/importation/reference_whatsapp.dart';
import '../models/message_conversation.dart';
import '../services/conversation/conversation_session.dart';
import '../services/ecriture/ecriture_progressive.dart';
import '../theme/gabarit_jarvis.dart';
import '../theme/theme_jarvis.dart';
import '../utils/chrono_perf.dart';
import '../widgets/conversation/bulle_ajout_whatsapp.dart';
import '../widgets/conversation/bulle_utilisateur.dart';
import '../widgets/conversation/carte_jarvis.dart';
import '../widgets/conversation/carte_piece_jointe.dart';
import 'resume_whatsapp_page.dart';
import '../widgets/defilement_sans_barre.dart';

/// Mesures verticales de la conversation, pour une hauteur disponible.
///
/// De haut en bas : le fil (seule surface qui défile), un écart de
/// sécurité, puis la zone PIM réservée juste au-dessus de la barre.
class MesuresConversation {
  const MesuresConversation({
    required this.zonePim,
    required this.securite,
    required this.fondu,
    required this.margeBas,
  });

  /// [hauteur] : place entre le logo et la barre de saisie.
  ///
  /// La zone PIM a la hauteur réellement occupée par les particules
  /// au-dessus de la barre ([zonePimDe]) ; elle ne prend jamais plus de
  /// 45 % de la place, pour qu'aucun débordement ne soit possible.
  factory MesuresConversation.de(double hauteur, GabaritJarvis g) {
    return MesuresConversation(
      zonePim: math.max(0.0, math.min(zonePimDe(g), hauteur * 0.45)),
      securite: g.compact ? 4 : 6,
      fondu: fonduDe(g),
      margeBas: g.compact ? 2 : 4,
    );
  }

  /// Marge verticale autour de chaque message (14 px entre deux messages).
  /// Sous le dernier, elle s'ajoute à [margeBas].
  static const ecartMessages = 7.0;

  /// Hauteur des particules au-dessus de la barre, mesurée sur les pixels
  /// dessinés (`tool/mesure_zone_pim_test.dart`) : 29 à 41 px au repos
  /// (environ 33 px sur téléphone), 35 à 42 px pendant l'impulsion d'envoi.
  /// On réserve un peu plus que le repos : l'impulsion et l'inertie du
  /// clavier passent un instant derrière les cartes, jamais devant.
  ///
  /// Du bas de la dernière carte au haut de la barre :
  /// [margeBas] + [ecartMessages] + [securite] + zone = 51 px (téléphone),
  /// 57 px (ordinateur).
  static double zonePimDe(GabaritJarvis g) => g.compact ? 38 : 40;

  static double fonduDe(GabaritJarvis g) => g.compact ? 14 : 20;

  /// Hauteur réservée aux particules au-dessus de la barre.
  final double zonePim;

  /// Écart entre le bas du fil et la zone PIM.
  final double securite;

  /// Hauteur des fondus en haut et en bas du fil (les cartes s'effacent
  /// au lieu d'être coupées net).
  final double fondu;

  /// Marge sous le dernier message, dans le fil, quand il est en bas (en
  /// plus de [ecartMessages]).
  final double margeBas;
}

/// Conversation écrite avec JARVIS.
///
/// Ce n'est pas un nouvel écran : c'est la zone centrale de l'accueil qui
/// se transforme en fil de discussion. Le logo, le fond, la barre de saisie
/// et les particules PIM (autour de la barre) restent ceux de l'accueil.
///
/// Zones, de haut en bas : le fil (fenêtre qui défile, sans barre de
/// défilement visible), un écart de sécurité, la zone PIM réservée
/// ([cleZonePim]) au-dessus de la barre. Le fil ne descend jamais dans la
/// zone PIM, et les particules n'en sortent pas par le haut.
///
/// Le fil est ancré en bas, comme une messagerie : le dernier message reste
/// au-dessus de la zone PIM, même quand le clavier s'ouvre ; on remonte
/// pour relire les anciens.
class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.session,
    required this.gabarit,
    required this.surPoserQuestion,
    this.cleZonePim,
    this.reveilServeur,
  });

  final ConversationSession session;

  /// Réveil du serveur hébergé en cours (`ApiJarvis.reveilEnCours`).
  final ValueListenable<bool>? reveilServeur;
  final GabaritJarvis gabarit;

  /// « Poser une question » : la page rend le focus au champ de saisie.
  final VoidCallback surPoserQuestion;

  /// Zone PIM réservée : les particules ne sont pas dessinées au-dessus.
  final GlobalKey? cleZonePim;

  /// Fenêtre du fil (pour les tests).
  static const cleFil = Key('fil-conversation');

  /// Distance au bas (px) sous laquelle l'utilisateur est « en bas » : une
  /// nouvelle réponse y fait descendre le fil ; plus haut, il relit et sa
  /// position est conservée.
  static const seuilBas = 120.0;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _defilement = ScrollController();
  int? _dernier;
  bool _reflexion = false;

  @override
  void initState() {
    super.initState();
    _dernier = widget.session.messages.lastOrNull?.id;
    _conversationAffichee = widget.session.idCourant;
    _reflexion = _attente(widget.session);
    widget.session.addListener(_surSession);
    final dernier = widget.session.messages.lastOrNull;
    final ecriture = dernier?.ecriture;
    if (ecriture != null && !ecriture.termine) _suivre(ecriture, dernier!.id);
    _defilement.addListener(_majSuspension);
  }

  /// Réponse en préparation ou conversation en cours de chargement : les
  /// mêmes trois points en bas du fil.
  static bool _attente(ConversationSession s) => s.enReflexion || s.chargement;

  @override
  void didUpdateWidget(ConversationPage ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.session != widget.session) {
      ancien.session.removeListener(_surSession);
      widget.session.addListener(_surSession);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_surSession);
    _suivre(null);
    _defilement.dispose();
    super.dispose();
  }

  // Réponse en train de s'écrire en bas du fil : sa carte grandit. Fil
  // ancré en bas : tant qu'elle est visible, le texte se construit sous les
  // yeux de l'utilisateur. Entièrement hors de la vue (il relit plus haut),
  // l'écriture se met en pause : rien ne bouge dans l'historique, son geste
  // n'est jamais contrarié ; elle reprend quand il redescend.
  EcritureProgressive? _ecritureSuivie;
  int? _idSuivi;

  void _suivre(EcritureProgressive? ecriture, [int? id]) {
    if (identical(ecriture, _ecritureSuivie)) return;
    final ancienne = _ecritureSuivie;
    if (ancienne != null) {
      ancienne.removeListener(_surEcriture);
      ancienne.suspendue = false;
    }
    _ecritureSuivie = ecriture;
    _idSuivi = id;
    ecriture?.addListener(_surEcriture);
    _majSuspension();
  }

  void _surEcriture() {
    final e = _ecritureSuivie;
    if (e == null) return;
    if (e.termine) {
      _suivre(null);
      return;
    }
    _majSuspension();
  }

  void _majSuspension() {
    final e = _ecritureSuivie;
    final id = _idSuivi;
    if (e == null || id == null || !_defilement.hasClients) return;
    final boite = _boite(id);
    // Liste inversée : la carte la plus récente occupe le bas du fil
    // (positions 0 à sa hauteur, marges comprises).
    final etendue = boite == null
        ? ConversationPage.seuilBas
        : boite.size.height + 2 * MesuresConversation.ecartMessages + 4;
    e.suspendue = _defilement.offset > etendue;
  }

  /// Liste inversée : la position 0 est le bas du fil (le plus récent).
  bool get _presDuBas =>
      !_defilement.hasClients ||
      _defilement.offset <= ConversationPage.seuilBas;

  void _surSession() {
    final session = widget.session;
    final messages = session.messages;
    // Nouveau message en bas (des messages plus anciens chargés en haut ne
    // font jamais descendre le fil).
    final ajout = messages.isNotEmpty && messages.last.id != _dernier;
    final reflexion = _attente(session) && !_reflexion;
    // Message de l'utilisateur : il vient d'agir, on descend toujours.
    // Réponse de JARVIS : seulement s'il est déjà près du bas, sinon il
    // garde sa place dans l'historique.
    final deLUtilisateur = ajout && !messages.last.deJarvis;
    final descendre = (ajout || reflexion) && (deLUtilisateur || _presDuBas);
    _dernier = messages.lastOrNull?.id;
    _reflexion = _attente(session);
    if (messages.isEmpty) {
      _cles.clear();
    } else if (session.idCourant != _conversationAffichee) {
      // Autre conversation : seules les clés de ses messages restent.
      final ids = {for (final m in messages) m.id};
      _cles.removeWhere((id, _) => !ids.contains(id));
    }
    _conversationAffichee = session.idCourant;
    final dernier = messages.lastOrNull;
    final ecriture = dernier?.ecriture;
    _suivre(
      ecriture == null || ecriture.termine ? null : ecriture,
      dernier?.id,
    );
    // L'utilisateur relit l'historique : un message visible sert de repère
    // pour qu'il ne bouge pas quand la réponse arrive en bas.
    final repere = !descendre && !_presDuBas ? _repere() : null;
    setState(() {});
    if (repere != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _garder(repere));
    }
    if (!descendre) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_defilement.hasClients) return;
      if (_defilement.offset <= 0) return;
      _defilement.animateTo(
        0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  // Une clé par message affiché, pour retrouver sa position à l'écran.
  final _cles = <int, GlobalKey>{};
  String? _conversationAffichee;
  GlobalKey _cle(int id) => _cles.putIfAbsent(id, GlobalKey.new);

  RenderBox? _boite(int id) {
    final objet = _cles[id]?.currentContext?.findRenderObject();
    if (objet is! RenderBox || !objet.attached || !objet.hasSize) return null;
    return objet;
  }

  double? _hauteurEcran(int id) => _boite(id)?.localToGlobal(Offset.zero).dy;

  /// Message en cours de lecture : le plus ancien encore visible en haut du
  /// fil, et sa position à l'écran.
  (int, double)? _repere() {
    final page = context.findRenderObject();
    if (page is! RenderBox || !page.hasSize) return null;
    final hautFil = page.localToGlobal(Offset.zero).dy;
    for (final m in widget.session.messages) {
      final boite = _boite(m.id);
      if (boite == null) continue;
      final y = boite.localToGlobal(Offset.zero).dy;
      if (y + boite.size.height > hautFil) return (m.id, y);
    }
    return null;
  }

  /// Après la mise à jour : compense le décalage éventuel du repère.
  void _garder((int, double) repere) {
    if (!mounted || !_defilement.hasClients) return;
    final (id, avant) = repere;
    final apres = _hauteurEcran(id);
    if (apres == null) return;
    final ecart = avant - apres;
    if (ecart.abs() < 0.5) return;
    final p = _defilement.position;
    // Liste inversée : augmenter la position fait descendre le contenu.
    p.jumpTo((p.pixels + ecart).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  /// Message d'origine d'une réponse : « Voir les messages » s'ouvre sur
  /// lui, dans SA pièce jointe (identifiée par le serveur). Le chat reste
  /// tel quel dessous : le retour y ramène, à la même position.
  Future<void> _ouvrirReference(ReferenceWhatsApp r) async {
    final service = widget.session.piecesJointes;
    if (service == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour consulter ce message.'),
        ),
      );
      return;
    }
    PieceJointeWhatsApp? piece;
    for (final m in widget.session.messages) {
      if (m.pieceJointe?.id == r.contexte) piece = m.pieceJointe;
    }
    final participants =
        piece?.participants ??
        [r.contact, if (r.moi != null && r.moi != r.contact) r.moi!];
    final conversation = ConversationWhatsApp(
      titre: piece?.titre ?? r.contact,
      messages: const [],
      participants: [
        for (final p in participants) ParticipantWhatsApp(nom: p, messages: 0),
      ],
      ordreDate: OrdreDate.jourMoisAnnee,
      dateIncertaine: piece?.dateIncertaine ?? r.datesIncertaines,
      lignesNonRattachees: const [],
      nombreLignesNonRattachees: 0,
      nomFichier: '',
    );
    final moi = piece?.moi ?? r.moi;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResumeWhatsAppPage.surMessage(
          conversation: conversation,
          chargeur: (apres, limite) =>
              service.page(r.contexte, apres: apres, limite: limite),
          cible: r.ordre,
          titrePage: CartePieceJointeEnvoyee.titrePage,
          moi: moi == null || moi.isEmpty ? null : moi,
          nombre: piece?.nombre,
        ),
      ),
    );
  }

  Future<void> _surAction(int id, ActionRapide action) async {
    if (action == ActionRapide.question) widget.surPoserQuestion();
    await widget.session.action(id, action);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gabarit;
    // Fil construit une fois par build : pendant la montée du clavier,
    // seul LayoutBuilder recalcule les zones (les messages ne sont pas
    // reconstruits).
    final fil = _fil(
      MesuresConversation.fonduDe(g),
      MesuresConversation.de(0, g).margeBas,
    );
    return LayoutBuilder(
      builder: (context, contraintes) {
        final m = MesuresConversation.de(contraintes.maxHeight, g);
        return Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  // Même largeur que la barre de saisie : le fil s'aligne
                  // sur elle.
                  constraints: BoxConstraints(maxWidth: g.largeurSaisie),
                  child: fil,
                ),
              ),
            ),
            SizedBox(height: m.securite),
            // Zone PIM : vide, réservée aux particules autour de la barre.
            SizedBox(
              key: widget.cleZonePim,
              width: double.infinity,
              height: m.zonePim,
            ),
          ],
        );
      },
    );
  }

  Widget _fil(double fondu, double margeBas) {
    final g = widget.gabarit;
    final session = widget.session;
    final messages = session.messages;
    final reflexion = _attente(session);
    final taille = g.compact ? 14.5 : 15.0;
    final decalage = reflexion ? 1 : 0;
    // Tout en haut : « messages précédents » (conversation enregistrée dont
    // seuls les derniers messages sont chargés).
    final precedents = session.plusAnciens && !session.chargement;
    final total = messages.length + decalage + (precedents ? 1 : 0);

    final contenu = ScrollConfiguration(
      // Défilement à la molette, au trackpad et au doigt, sans barre
      // visible (Web, Windows, Android, iOS).
      behavior: const DefilementSansBarre(),
      child: SelectionArea(
        child: ListView.builder(
          controller: _defilement,
          reverse: true,
          // Marges dans la fenêtre : aucune carte collée au logo ni à la
          // zone PIM quand le fil est au repos.
          padding: EdgeInsets.only(top: fondu + 6, bottom: margeBas),
          itemCount: total,
          // Les messages gardent leur état (et leur place quand on relit
          // l'historique) quand une réponse arrive en bas.
          findChildIndexCallback: (cle) {
            if (cle == const ValueKey('reflexion')) {
              return reflexion ? 0 : null;
            }
            if (cle == const ValueKey('precedents')) {
              return precedents ? total - 1 : null;
            }
            if (cle is! ValueKey<int>) return null;
            final i = messages.indexWhere((m) => m.id == cle.value);
            return i < 0 ? null : messages.length - 1 - i + decalage;
          },
          itemBuilder: (context, i) {
            // Liste inversée : l'élément 0 est le plus récent.
            if (reflexion && i == 0) {
              return Padding(
                key: const ValueKey('reflexion'),
                padding: const EdgeInsets.symmetric(
                  vertical: MesuresConversation.ecartMessages,
                ),
                child: ReflexionJarvis(reveilServeur: widget.reveilServeur),
              );
            }
            if (precedents && i == total - 1) {
              return Padding(
                key: const ValueKey('precedents'),
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(
                  child: TextButton(
                    onPressed: session.chargerPlusAnciens,
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursJarvis.texteSecondaire,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('Afficher les messages précédents'),
                  ),
                ),
              );
            }
            final m = messages[messages.length - 1 - (i - decalage)];
            return Padding(
              key: ValueKey(m.id),
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: KeyedSubtree(
                key: _cle(m.id),
                child: m.ajoutWhatsApp != null
                    // Phase 5.1 : message WhatsApp collé (reçu / envoyé).
                    ? BulleAjoutWhatsApp(
                        ajout: m.ajoutWhatsApp!,
                        taille: taille,
                        surCorriger: (t) => session.corrigerAjout(m.id, t),
                        surSupprimer: () => session.supprimerAjout(m.id),
                      )
                    : m.deJarvis
                    ? CarteJarvis(
                        message: m,
                        taille: taille,
                        surTon: (ton) => session.choisirTon(m.id, ton),
                        surAction: (a) => _surAction(m.id, a),
                        surChoix: (c) => session.choisir(m.id, c),
                        surReference: _ouvrirReference,
                        surTonPropositions: (ton, longueur) =>
                            session.regarderTon(m.id, ton, longueur: longueur),
                        tonPropositions: session.tonRegarde(m.id),
                        longueurPropositions: session.longueurRegardee(m.id),
                        contactPropositions: session.contactPropositions,
                        surReprendrePropositions: () =>
                            session.reprendrePropositions(m.id),
                        repriseEnCours: session.repriseEnCours(m.id),
                        preparation: session.preparationEnCours(m.id),
                        surStatutProposition: (p, envoyee) => session
                            .declarerEnvoyee(m.id, p.id, envoyee: envoyee),
                      )
                    : BulleUtilisateur(message: m, taille: taille),
              ),
            );
          },
        ),
      ),
    );
    // Mesure seulement (JARVIS_PERF) : coût du fondu, jamais hors banc.
    if (ChronoPerf.sans('fil.fondu')) {
      return KeyedSubtree(key: ConversationPage.cleFil, child: contenu);
    }
    return ShaderMask(
      key: ConversationPage.cleFil,
      // Fondus haut et bas : une carte qui sort de la fenêtre s'efface
      // doucement au lieu d'être coupée net.
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) {
        // En bas, le fondu tient dans la marge : au repos, le dernier
        // message reste entièrement net.
        final f = r.height <= 0 ? 0.0 : math.min(0.3, fondu / r.height);
        final bas = margeBas + MesuresConversation.ecartMessages;
        final fb = r.height <= 0 ? 0.0 : math.min(0.3, bas / r.height);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, f, 1 - fb, 1],
        ).createShader(Offset.zero & r.size);
      },
      child: contenu,
    );
  }
}
