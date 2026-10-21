import 'package:flutter/material.dart';

import '../../services/integrations/service_gmail.dart';
import '../../theme/theme_jarvis.dart';
import '../parametres/elements_parametres.dart';
import 'panneau_gmail.dart';

/// Outils (ODO) réellement disponibles, présentés dans Paramètres › Outils.
/// Ajouter un outil : une valeur ici, puis son logo, son statut et sa page
/// dans [PanneauOutils] et `FenetreParametres` (aucun outil fictif).
enum OutilJarvis {
  gmail('Gmail', 'E-mails Google'),

  /// Préparé seulement : aucun fournisseur raccordé, aucune permission,
  /// aucun événement (ni réel ni fictif).
  agenda('Agenda', 'Rendez-vous et événements');

  const OutilJarvis(this.nom, this.description);

  final String nom;
  final String description;
}

/// Paramètres › Outils : un outil par ligne (logo, nom, statut, chevron).
/// Le statut vient du même service que la page de l'outil.
class PanneauOutils extends StatefulWidget {
  const PanneauOutils({super.key, required this.gmail, required this.surChoix});

  /// null : JARVIS ouvert sans compte.
  final ServiceGmail? gmail;
  final ValueChanged<OutilJarvis> surChoix;

  @override
  State<PanneauOutils> createState() => _PanneauOutilsState();
}

class _PanneauOutilsState extends State<PanneauOutils> {
  @override
  void initState() {
    super.initState();
    // Relecture discrète (rien si l'état est récent) : le dernier état connu
    // s'affiche aussitôt.
    Future.microtask(() => widget.gmail?.actualiser());
  }

  @override
  Widget build(BuildContext context) {
    return CarteReglages(
      enfants: [
        for (final outil in OutilJarvis.values)
          switch (outil) {
            OutilJarvis.gmail => ListenableBuilder(
              listenable: widget.gmail ?? const _Fixe(),
              builder: (context, _) {
                final (libelle, couleur) = statutGmail(widget.gmail);
                return _LigneOutil(
                  outil: outil,
                  logo: const LogoGmail(),
                  statut: StatutOutil(
                    libelle: libelle,
                    couleur: couleur,
                    attente: widget.gmail?.enAttente ?? false,
                  ),
                  surAppui: () => widget.surChoix(outil),
                );
              },
            ),
            OutilJarvis.agenda => _LigneOutil(
              outil: outil,
              logo: const LogoAgenda(),
              statut: StatutOutil(
                libelle: PanneauAgenda.statut,
                couleur: CouleursJarvis.texteSecondaire,
              ),
              surAppui: () => widget.surChoix(outil),
            ),
          },
      ],
    );
  }
}

/// Aucun service : rien à écouter.
class _Fixe implements Listenable {
  const _Fixe();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _LigneOutil extends StatelessWidget {
  const _LigneOutil({
    required this.outil,
    required this.logo,
    required this.statut,
    required this.surAppui,
  });

  final OutilJarvis outil;
  final Widget logo;
  final Widget statut;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: surAppui,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            logo,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    outil.nom,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: CouleursJarvis.texte,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    outil.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: CouleursJarvis.creme.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: CouleursJarvis.trait.withValues(alpha: 0.6),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: statut,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: CouleursJarvis.texteSecondaire,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pastille de l'Agenda (même taille que le logo Gmail).
class LogoAgenda extends StatelessWidget {
  const LogoAgenda({super.key, this.taille = 36});

  final double taille;

  @override
  Widget build(BuildContext context) => Container(
    width: taille,
    height: taille,
    decoration: BoxDecoration(
      color: CouleursJarvis.creme,
      borderRadius: BorderRadius.circular(taille * 0.28),
      border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.7)),
    ),
    child: Icon(
      Icons.event_rounded,
      size: taille * 0.58,
      color: CouleursJarvis.signal,
    ),
  );
}

/// Paramètres › Outils › Agenda : présentation honnête d'un outil à venir.
/// Aucune connexion lancée, aucune permission demandée, aucun événement.
class PanneauAgenda extends StatelessWidget {
  const PanneauAgenda({super.key});

  static const statut = 'Bientôt disponible';
  static const explication =
      'JARVIS pourra bientôt consulter votre agenda (Google Agenda ou un '
      'autre fournisseur) pour vous rappeler vos rendez-vous et vous aider '
      'à organiser vos journées. La connexion n’est pas encore disponible : '
      'JARVIS n’a aujourd’hui aucun accès à votre calendrier.';

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LogoAgenda(taille: 56),
        const SizedBox(height: 16),
        Text(
          OutilJarvis.agenda.nom,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: CouleursJarvis.texte,
          ),
        ),
        const SizedBox(height: 8),
        StatutOutil(libelle: statut, couleur: CouleursJarvis.texteSecondaire),
        const SizedBox(height: 16),
        Text(
          explication,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: CouleursJarvis.texteSecondaire,
          ),
        ),
      ],
    ),
  );
}
