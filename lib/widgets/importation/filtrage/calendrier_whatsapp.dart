import 'package:flutter/material.dart';

import '../../../services/importation/selection_whatsapp.dart';
import '../../../theme/theme_jarvis.dart';
import '../../../utils/local_date_time.dart';

/// Calendrier de la conversation : les jours qui ont réellement des
/// messages sont mis en évidence (avec leur nombre), la période
/// personnalisée y apparaît en violet. Navigation par mois (flèches) et
/// par année (menu), dans les limites de la conversation.
class CalendrierWhatsApp extends StatelessWidget {
  const CalendrierWhatsApp({super.key, required this.selection});

  static const joursCourts = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  final SelectionWhatsApp selection;

  static String libelleMois(DateTime mois) {
    final m = moisEnFrancais(mois);
    return '${m[0].toUpperCase()}${m.substring(1)} ${mois.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final index = s.index;
    final mois = s.moisAffiche;
    final premier = index.premierJour, dernier = index.dernierJour;
    final precedent = DateTime(mois.year, mois.month - 1);
    final suivant = DateTime(mois.year, mois.month + 1);
    final peutReculer =
        premier != null &&
        !precedent.isBefore(DateTime(premier.year, premier.month));
    final peutAvancer =
        dernier != null &&
        !suivant.isAfter(DateTime(dernier.year, dernier.month));
    final jours = index.joursDuMois(mois.year, mois.month);
    final periode = s.periode;
    final debutP = periode != null && periode.valide
        ? DateTime(periode.debut.year, periode.debut.month, periode.debut.day)
        : null;
    final finP = periode != null && periode.valide
        ? DateTime(periode.fin.year, periode.fin.month, periode.fin.day)
        : null;
    final decalage = DateTime(mois.year, mois.month).weekday - 1;
    final nbJours = DateTime(mois.year, mois.month + 1, 0).day;
    final cellules = decalage + nbJours;
    final lignes = (cellules / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Mois précédent',
              onPressed: peutReculer
                  ? () => s.afficherMois(precedent.year, precedent.month)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: CouleursJarvis.texte,
            ),
            Expanded(
              child: Center(
                child: _ChoixAnnee(selection: s, libelle: libelleMois(mois)),
              ),
            ),
            IconButton(
              tooltip: 'Mois suivant',
              onPressed: peutAvancer
                  ? () => s.afficherMois(suivant.year, suivant.month)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
              color: CouleursJarvis.texte,
            ),
          ],
        ),
        Row(
          children: [
            for (final j in joursCourts)
              Expanded(
                child: Center(
                  child: Text(
                    j,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var l = 0; l < lignes; l++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final jour = l * 7 + c - decalage + 1;
                      if (jour < 1 || jour > nbJours) {
                        return const SizedBox(height: _CaseJour.hauteur);
                      }
                      final date = DateTime(mois.year, mois.month, jour);
                      final dans =
                          debutP != null &&
                          finP != null &&
                          !date.isBefore(debutP) &&
                          !date.isAfter(finP);
                      return _CaseJour(
                        jour: jour,
                        nombre: jours[jour] ?? 0,
                        dansPeriode: dans,
                        borne: dans && (date == debutP || date == finP),
                        surAppui: () => s.choisirJour(date),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Mois et année affichés ; un menu permet de changer d'année.
class _ChoixAnnee extends StatelessWidget {
  const _ChoixAnnee({required this.selection, required this.libelle});

  final SelectionWhatsApp selection;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final annees = selection.index.annees;
    final texte = Text(
      libelle,
      style: TextStyle(
        fontFamily: policeAffichage,
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: CouleursJarvis.texte,
      ),
    );
    if (annees.length < 2) return texte;
    return PopupMenuButton<int>(
      tooltip: 'Choisir l’année',
      color: CouleursJarvis.coque,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (annee) {
        // Le mois affiché s'il a des messages cette année-là, sinon le
        // dernier mois qui en a.
        final m = selection.moisAffiche.month;
        if (selection.index.moisAvecMessages(annee, m)) {
          selection.afficherMois(annee, m);
          return;
        }
        for (var k = 12; k >= 1; k--) {
          if (selection.index.moisAvecMessages(annee, k)) {
            selection.afficherMois(annee, k);
            return;
          }
        }
      },
      itemBuilder: (_) => [
        for (final a in annees.reversed)
          PopupMenuItem(
            value: a,
            child: Text(
              '$a',
              style: TextStyle(
                fontWeight: a == selection.moisAffiche.year
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: CouleursJarvis.texte,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: texte),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: CouleursJarvis.texteSecondaire,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un jour : numéro, et nombre de messages s'il en a. Sans message : pâle
/// et inactif.
class _CaseJour extends StatelessWidget {
  const _CaseJour({
    required this.jour,
    required this.nombre,
    required this.dansPeriode,
    required this.borne,
    required this.surAppui,
  });

  static const hauteur = 42.0;

  final int jour;
  final int nombre;
  final bool dansPeriode;
  final bool borne;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) {
    final actif = nombre > 0;
    final Color fond;
    final Color encre;
    if (borne) {
      fond = CouleursJarvis.signal;
      encre = CouleursJarvis.ivoire;
    } else if (dansPeriode) {
      fond = CouleursJarvis.lavande;
      encre = CouleursJarvis.signal;
    } else if (actif) {
      fond = CouleursJarvis.violetPoudre.withValues(alpha: 0.75);
      encre = CouleursJarvis.texte;
    } else {
      fond = Colors.transparent;
      encre = CouleursJarvis.texteSecondaire.withValues(alpha: 0.45);
    }
    return Semantics(
      button: actif,
      selected: dansPeriode,
      label: actif
          ? '$jour, $nombre message${nombre > 1 ? 's' : ''}'
          : '$jour, aucun message',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: fond,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: actif ? surAppui : null,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: hauteur - 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$jour',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: actif ? FontWeight.w600 : FontWeight.w400,
                          color: encre,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (actif)
                        Text(
                          '$nombre',
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            color: borne
                                ? CouleursJarvis.ivoire.withValues(alpha: 0.85)
                                : CouleursJarvis.signal.withValues(alpha: 0.8),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
