import 'package:flutter/material.dart';

import '../../models/importation/piece_jointe_whatsapp.dart';
import '../../pages/resume_whatsapp_page.dart';
import '../../theme/theme_jarvis.dart';
import '../importation/lecture_whatsapp_widgets.dart';
import '../importation/logo_whatsapp.dart';

/// « WhatsApp · 35 messages ».
String libelleNombrePieceJointe(PieceJointeWhatsApp p) {
  final n = p.nombre;
  return '${p.source.libelle} · ${nombreEnFrancais(n)} '
      'message${n > 1 ? 's' : ''}';
}

/// Pièce jointe en attente d'envoi, dans la barre de saisie : logo
/// WhatsApp, nom du contact, nombre de messages, et une croix pour la
/// retirer (le texte saisi reste).
class PieceJointeEnAttente extends StatelessWidget {
  const PieceJointeEnAttente({
    super.key,
    required this.piece,
    required this.surRetirer,
    this.enCours = false,
  });

  static const retirer = 'Retirer la pièce jointe';
  static const enregistrement = 'Enregistrement de la pièce jointe…';

  final PieceJointeWhatsApp piece;
  final VoidCallback surRetirer;

  /// Enregistrement en cours : petit anneau à la place de la croix.
  final bool enCours;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Semantics(
          label:
              'Pièce jointe : ${piece.titre}, ${libelleNombrePieceJointe(piece)}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  CouleursJarvis.violetPoudre.withValues(alpha: 0.55),
                  CouleursJarvis.coque.withValues(alpha: 0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: CouleursJarvis.lavande.withValues(alpha: 0.95),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoWhatsApp(taille: 30),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piece.titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: CouleursJarvis.texte,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        libelleNombrePieceJointe(piece),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: CouleursJarvis.texteSecondaire,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                if (enCours)
                  const Tooltip(
                    message: enregistrement,
                    child: SizedBox.square(
                      dimension: 36,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CouleursJarvis.signal,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: retirer,
                    onPressed: surRetirer,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    style: IconButton.styleFrom(
                      foregroundColor: CouleursJarvis.texteSecondaire,
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

/// Pièce jointe envoyée, dans le message de l'utilisateur : un objet à
/// part (pas un texte), avec « Voir les messages » pour relire les
/// messages WhatsApp originaux (lus sur le serveur pour une pièce jointe
/// relue d'un autre appareil ou après un redémarrage).
class CartePieceJointeEnvoyee extends StatefulWidget {
  const CartePieceJointeEnvoyee({
    super.key,
    required this.piece,
    this.taille = 14.5,
  });

  static const voirMessages = 'Voir les messages';
  static const titrePage = 'Messages joints';
  static const chargement = 'Chargement des messages…';

  final PieceJointeWhatsApp piece;
  final double taille;

  @override
  State<CartePieceJointeEnvoyee> createState() =>
      _CartePieceJointeEnvoyeeState();
}

class _CartePieceJointeEnvoyeeState extends State<CartePieceJointeEnvoyee> {
  bool _chargement = false;

  // Messages lus une fois (serveur), gardés pour les consultations suivantes.
  PieceJointeWhatsApp? _lue;

  Future<void> _voir() async {
    var piece = _lue ?? widget.piece;
    final charger = piece.chargerMessages;
    if (piece.distante && charger != null) {
      if (_chargement) return;
      setState(() => _chargement = true);
      try {
        piece = _lue = piece.avecMessages(await charger());
      } catch (e) {
        if (!mounted) return;
        setState(() => _chargement = false);
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '$e',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: CouleursJarvis.ivoire,
                ),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: CouleursJarvis.texte.withValues(alpha: 0.92),
            ),
          );
        return;
      }
      if (!mounted) return;
      setState(() => _chargement = false);
    }
    if (!mounted) return;
    final aVoir = piece;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResumeWhatsAppPage(
          conversation: aVoir.commeConversation,
          titrePage: CartePieceJointeEnvoyee.titrePage,
          moi: aVoir.moi.isEmpty ? null : aVoir.moi,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final piece = widget.piece;
    final taille = widget.taille;
    final debut = piece.debut, fin = piece.fin;
    final details = [
      libelleNombrePieceJointe(piece),
      if (debut != null && fin != null) ResumeWhatsAppPage.periode(debut, fin),
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CouleursJarvis.lavande.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const LogoWhatsApp(taille: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      piece.titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: taille,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: CouleursJarvis.texte,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: CouleursJarvis.texteSecondaire,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _chargement ? null : _voir,
              icon: _chargement
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CouleursJarvis.signal,
                      ),
                    )
                  : const Icon(Icons.visibility_outlined, size: 16),
              label: Text(
                _chargement
                    ? CartePieceJointeEnvoyee.chargement
                    : CartePieceJointeEnvoyee.voirMessages,
              ),
              style: TextButton.styleFrom(
                foregroundColor: CouleursJarvis.signal,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
