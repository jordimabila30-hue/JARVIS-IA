import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/integrations/etat_gmail.dart';
import '../../services/integrations/service_gmail.dart';
import '../../theme/theme_jarvis.dart';
import '../parametres/elements_parametres.dart';

Color get _vert => CouleursJarvis.lisible(const Color(0xFF2E8B57));

/// Statut court de Gmail, le même dans Outils et sur la page Gmail.
/// « Connecté » seulement d'après la dernière lecture du serveur.
(String, Color) statutGmail(ServiceGmail? s) {
  if (s == null) return ('Indisponible', CouleursJarvis.texteSecondaire);
  if (s.enAttente) return ('Connexion en cours', CouleursJarvis.signal);
  return switch (s.etat?.statut) {
    null when s.erreur != null => (
      'Non vérifié',
      CouleursJarvis.texteSecondaire,
    ),
    null => ('Vérification…', CouleursJarvis.texteSecondaire),
    StatutGmail.connecte => ('Connecté', _vert),
    StatutGmail.nonConnecte => ('Déconnecté', CouleursJarvis.texteSecondaire),
    StatutGmail.aRenouveler => ('À reconnecter', CouleursJarvis.critique),
    StatutGmail.nonConfigure => (
      'Indisponible',
      CouleursJarvis.texteSecondaire,
    ),
  };
}

/// Logo Gmail dans sa tuile claire.
class LogoGmail extends StatelessWidget {
  const LogoGmail({super.key, this.taille = 42});

  final double taille;

  @override
  Widget build(BuildContext context) => Container(
    width: taille,
    height: taille,
    padding: EdgeInsets.all(taille * 0.21),
    decoration: BoxDecoration(
      color: CouleursJarvis.coque,
      borderRadius: BorderRadius.circular(taille * 0.3),
      border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.7)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F3A3350),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: SvgPicture.asset('assets/logos/gmail.svg'),
  );
}

/// Pastille d'état : point coloré (ou petit cercle en attente) et libellé.
class StatutOutil extends StatelessWidget {
  const StatutOutil({
    super.key,
    required this.libelle,
    required this.couleur,
    this.attente = false,
    this.taille = 13,
  });

  final String libelle;
  final Color couleur;
  final bool attente;
  final double taille;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (attente)
        SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: couleur),
        )
      else
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          libelle,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: taille,
            fontWeight: FontWeight.w500,
            color: couleur,
          ),
        ),
      ),
    ],
  );
}

/// Paramètres › Outils › Gmail : statut, compte, accès, « Gérer la
/// connexion ». Affiche aussitôt le dernier état connu de [ServiceGmail]
/// et le relit en silence (jamais de chargement plein écran).
class PanneauGmail extends StatefulWidget {
  const PanneauGmail({super.key, required this.service});

  /// null : JARVIS ouvert sans compte.
  final ServiceGmail? service;

  @override
  State<PanneauGmail> createState() => _PanneauGmailState();
}

class _PanneauGmailState extends State<PanneauGmail> {
  @override
  void initState() {
    super.initState();
    // Après la construction : la lecture notifie les autres écrans.
    Future.microtask(() => widget.service?.actualiser());
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    if (service == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnTete(statut: statutGmail(null)),
          const SizedBox(height: 18),
          const CarteReglages(
            enfants: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: NoteReglage(
                  'Connectez-vous à JARVIS pour relier un compte Gmail.',
                ),
              ),
            ],
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnTete(statut: statutGmail(service), attente: service.enAttente),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _corps(context, service),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corps(BuildContext context, ServiceGmail s) {
    final etat = s.etat;
    final notes = [
      if (s.information != null) s.information!,
      if (etat != null && !s.fiable)
        'Dernier état connu : vérification impossible pour le moment.',
    ];
    final pied = [
      for (final n in notes) ...[const SizedBox(height: 12), NoteReglage(n)],
      if (etat != null && !s.fiable)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => s.actualiser(force: true),
            child: const Text('Réessayer'),
          ),
        ),
    ];
    if (s.enAttente) {
      return [
        const SizedBox(height: 18),
        CarteReglages(enfants: [_Attente(service: s)]),
        ...pied,
      ];
    }
    if (etat == null) {
      if (s.erreur == null) return const [];
      return [
        const SizedBox(height: 18),
        CarteReglages(
          enfants: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: const NoteReglage(
                'Impossible de lire l’état de Gmail pour le moment.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => s.actualiser(force: true),
                child: const Text('Réessayer'),
              ),
            ),
          ],
        ),
      ];
    }
    final gerer = CarteReglages(
      enfants: [
        _LigneAction(
          icone: Icons.tune_rounded,
          titre: 'Gérer la connexion',
          description: 'Changer de compte ou déconnecter',
          surAppui: () => _gerer(context, s),
        ),
      ],
    );
    return switch (etat.statut) {
      StatutGmail.connecte => [
        const SizedBox(height: 18),
        CarteReglages(
          enfants: [
            _Info(
              icone: Icons.person_outline_rounded,
              libelle: 'Compte Google',
              valeur: etat.email ?? '—',
            ),
            _Info(
              icone: Icons.verified_user_outlined,
              libelle: 'Accès',
              valeur: etat.lectureSeule ? 'Lecture seule' : 'À vérifier',
              detail: 'Rechercher, lire et résumer vos e-mails.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        gerer,
        ...pied,
      ],
      StatutGmail.aRenouveler => [
        const SizedBox(height: 18),
        CarteReglages(
          enfants: [
            if (etat.email != null)
              _Info(
                icone: Icons.person_outline_rounded,
                libelle: 'Compte Google',
                valeur: etat.email!,
              ),
            _Invitation(
              texte: 'L’autorisation a expiré ou a été retirée chez Google.',
              bouton: 'Reconnecter Gmail',
              surAppui: s.connecter,
            ),
          ],
        ),
        const SizedBox(height: 12),
        gerer,
        ...pied,
      ],
      StatutGmail.nonConnecte => [
        const SizedBox(height: 18),
        CarteReglages(
          enfants: [
            _Invitation(
              icone: true,
              texte:
                  'Connectez le compte Google que vous souhaitez utiliser avec JARVIS.',
              bouton: 'Choisir un compte Google',
              surAppui: s.connecter,
              securite: true,
            ),
          ],
        ),
        ...pied,
      ],
      StatutGmail.nonConfigure => [
        const SizedBox(height: 18),
        const CarteReglages(
          enfants: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: NoteReglage(
                'Gmail n’est pas encore disponible sur ce serveur JARVIS.',
              ),
            ),
          ],
        ),
        ...pied,
      ],
    };
  }

  /// « Gérer la connexion » : changer de compte ou déconnecter (feuille sur
  /// téléphone, petite fenêtre ailleurs).
  Future<void> _gerer(BuildContext context, ServiceGmail s) async {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    final contenu = _GestionConnexion(email: s.etat?.email);
    final choix = etroit
        ? await showModalBottomSheet<_Gestion>(
            context: context,
            backgroundColor: CouleursJarvis.ivoire,
            showDragHandle: true,
            useSafeArea: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => contenu,
          )
        : await showDialog<_Gestion>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: CouleursJarvis.ivoire,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: contenu,
                ),
              ),
            ),
          );
    if (!context.mounted) return;
    switch (choix) {
      case _Gestion.changer:
        await s.connecter();
      case _Gestion.deconnecter:
        await _confirmerDeconnexion(context, s);
      case null:
    }
  }

  Future<void> _confirmerDeconnexion(
    BuildContext context,
    ServiceGmail s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: CouleursJarvis.coque,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Déconnecter Gmail ?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        content: const Text(
          'JARVIS n’aura plus accès à ce compte et l’autorisation sera retirée chez Google. '
          'Vos e-mails ne sont pas touchés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CouleursJarvis.signal,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) await s.deconnecter();
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.statut, this.attente = false});

  final (String, Color) statut;
  final bool attente;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 4),
    child: Row(
      children: [
        const LogoGmail(taille: 56),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gmail',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: CouleursJarvis.texte,
                ),
              ),
              const SizedBox(height: 5),
              StatutOutil(
                libelle: statut.$1,
                couleur: statut.$2,
                attente: attente,
                taille: 14,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Information du compte : icône, libellé discret, valeur (et détail).
class _Info extends StatelessWidget {
  const _Info({
    required this.icone,
    required this.libelle,
    required this.valeur,
    this.detail,
  });

  final IconData icone;
  final String libelle;
  final String valeur;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(icone, size: 21, color: CouleursJarvis.texteSecondaire),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                libelle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: CouleursJarvis.texteSecondaire,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                valeur,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: CouleursJarvis.texte,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 3),
                Text(
                  detail!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Ligne cliquable (icône, titre, description, chevron).
class _LigneAction extends StatelessWidget {
  const _LigneAction({
    required this.icone,
    required this.titre,
    required this.description,
    required this.surAppui,
  });

  final IconData icone;
  final String titre;
  final String description;
  final VoidCallback surAppui;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: surAppui,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icone, size: 21, color: CouleursJarvis.texteSecondaire),
          const SizedBox(width: 16),
          Expanded(
            child: TexteReglage(titre: titre, description: description),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: CouleursJarvis.texteSecondaire,
          ),
        ],
      ),
    ),
  );
}

/// Invitation à (re)connecter : texte court, bouton, mention Google.
class _Invitation extends StatelessWidget {
  const _Invitation({
    required this.texte,
    required this.bouton,
    required this.surAppui,
    this.icone = false,
    this.securite = false,
  });

  final String texte;
  final String bouton;
  final VoidCallback surAppui;
  final bool icone;
  final bool securite;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      children: [
        if (icone) ...[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: CouleursJarvis.signal.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mail_outline_rounded,
              size: 23,
              color: CouleursJarvis.signal,
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: CouleursJarvis.texte,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: surAppui,
              icon: const Icon(Icons.account_circle_outlined, size: 19),
              label: Text(
                bouton,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: CouleursJarvis.signal,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
        if (securite) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: CouleursJarvis.texteSecondaire,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Connexion sécurisée via Google.',
                  style: TextStyle(
                    fontSize: 12,
                    color: CouleursJarvis.texteSecondaire,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Attente extends StatelessWidget {
  const _Attente({required this.service});

  final ServiceGmail service;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Terminez la connexion chez Google, dans le navigateur, puis revenez ici.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: service.annulerAttente,
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}

enum _Gestion { changer, deconnecter }

/// Contenu de « Gérer la connexion ».
class _GestionConnexion extends StatelessWidget {
  const _GestionConnexion({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    Widget action(
      _Gestion g,
      IconData icone,
      String titre,
      String description,
    ) => ListTile(
      onTap: () => Navigator.pop(context, g),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      leading: Icon(icone, color: CouleursJarvis.texteSecondaire),
      title: Text(
        titre,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: CouleursJarvis.texte,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(fontSize: 12.5, color: CouleursJarvis.texteSecondaire),
      ),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gérer la connexion',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CouleursJarvis.texte,
                  ),
                ),
                if (email != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    email!,
                    style: TextStyle(
                      fontSize: 13,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                ],
              ],
            ),
          ),
          action(
            _Gestion.changer,
            Icons.swap_horiz_rounded,
            'Changer de compte',
            'Choisir un autre compte Google',
          ),
          action(
            _Gestion.deconnecter,
            Icons.logout_rounded,
            'Déconnecter Gmail',
            'Retirer l’accès de JARVIS à ce compte',
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: NoteReglage(
              'Lecture seule : JARVIS ne peut ni envoyer, ni supprimer, ni modifier vos e-mails. '
              'La connexion se fait chez Google ; votre mot de passe n’est jamais demandé dans JARVIS.',
            ),
          ),
        ],
      ),
    );
  }
}
