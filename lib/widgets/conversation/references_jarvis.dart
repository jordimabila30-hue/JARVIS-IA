import 'package:flutter/material.dart';

import '../../models/importation/reference_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import '../importation/logo_whatsapp.dart';

/// Messages WhatsApp originaux sous une réponse de JARVIS : petites cartes
/// (auteur, date, extrait) qui ouvrent le vrai message dans « Voir les
/// messages ». Trois au plus d'emblée ; « Voir les autres » pour la suite.
class ReferencesJarvis extends StatefulWidget {
  const ReferencesJarvis({
    super.key,
    required this.references,
    required this.surReference,
    this.note,
  });

  final List<ReferenceWhatsApp> references;
  final ValueChanged<ReferenceWhatsApp>? surReference;

  /// Avertissement du serveur (référence refusée, attribution contredite).
  final String? note;

  static const titre = 'Messages d’origine';
  static const premiers = 3;

  @override
  State<ReferencesJarvis> createState() => _ReferencesJarvisState();
}

class _ReferencesJarvisState extends State<ReferencesJarvis> {
  bool _tout = false;

  @override
  Widget build(BuildContext context) {
    final refs = widget.references;
    final visibles = _tout || refs.length <= ReferencesJarvis.premiers
        ? refs
        : refs.take(ReferencesJarvis.premiers).toList();
    final reste = refs.length - visibles.length;
    final note = widget.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (refs.isNotEmpty) ...[
          const Row(
            children: [
              LogoWhatsApp(taille: 13),
              SizedBox(width: 6),
              Text(
                ReferencesJarvis.titre,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.3,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in visibles) ...[
            CarteReference(
              reference: r,
              surAppui: widget.surReference == null
                  ? null
                  : () => widget.surReference!(r),
            ),
            const SizedBox(height: 8),
          ],
          if (reste > 0)
            TextButton(
              onPressed: () => setState(() => _tout = true),
              style: TextButton.styleFrom(
                foregroundColor: CouleursJarvis.signal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 34),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(
                'Voir ${reste == 1 ? 'l’autre message' : 'les $reste autres'}',
              ),
            ),
        ],
        if (note != null) ...[
          if (refs.isNotEmpty) const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 6),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              Expanded(
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Un message d'origine : auteur et date, puis un court extrait.
class CarteReference extends StatelessWidget {
  const CarteReference({super.key, required this.reference, this.surAppui});

  final ReferenceWhatsApp reference;
  final VoidCallback? surAppui;

  @override
  Widget build(BuildContext context) {
    final r = reference;
    final auteur = r.auteur ?? 'WhatsApp';
    return Semantics(
      button: surAppui != null,
      label: 'Message de $auteur, ${r.dateAffichee}',
      hint: surAppui == null ? null : 'Ouvrir ce message',
      excludeSemantics: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: surAppui,
          borderRadius: BorderRadius.circular(14),
          splashColor: CouleursJarvis.lavande.withValues(alpha: 0.35),
          highlightColor: CouleursJarvis.lavande.withValues(alpha: 0.18),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(9, 9, 8, 10),
            decoration: BoxDecoration(
              color: CouleursJarvis.coque.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CouleursJarvis.lavande.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Accent : bleu-violet pour l'utilisateur, violet pour l'autre.
                Container(
                  width: 3,
                  height: 38,
                  margin: const EdgeInsets.only(right: 9, top: 1),
                  decoration: BoxDecoration(
                    color:
                        (r.estMoi
                                ? CouleursJarvis.signal
                                : CouleursJarvis.violet)
                            .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: r.estMoi ? '$auteur (vous)' : auteur,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: CouleursJarvis.texte,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, height: 1.3),
                      ),
                      // Date sur sa ligne : jamais coupée sur un téléphone.
                      Text(
                        r.ajoute
                            ? '${r.dateBrute.isEmpty && r.date == null ? 'Date inconnue' : r.dateAffichee} · ajouté à la main'
                            : r.dateAffichee,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: CouleursJarvis.texteSecondaire,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '« ${r.extrait} »',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: CouleursJarvis.texte,
                        ),
                      ),
                    ],
                  ),
                ),
                if (surAppui != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: CouleursJarvis.texteSecondaire,
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
