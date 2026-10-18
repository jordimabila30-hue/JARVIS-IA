import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/integrations/etat_gmail.dart';
import '../../services/api_jarvis.dart';
import '../../services/integrations/service_gmail.dart';
import '../../theme/theme_jarvis.dart';
import '../parametres/elements_parametres.dart';

/// Ce que JARVIS peut faire (et ne fera jamais) avec Gmail.
const autorisationsGmail = [
  (Icons.search_rounded, 'Rechercher vos e-mails (expéditeur, objet, période)'),
  (Icons.mark_email_read_outlined, 'Lire un e-mail ou une discussion'),
  (Icons.summarize_outlined, 'Les résumer dans votre conversation'),
];
const interditsGmail = 'Lecture seule : JARVIS ne peut ni envoyer, ni supprimer, ni modifier vos e-mails. '
    'Votre mot de passe Google n’est jamais demandé dans JARVIS : la connexion se fait chez Google.';

/// Paramètres › Gmail : connecter, changer de compte, déconnecter.
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
      return const CarteReglages(enfants: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: NoteReglage('Connectez-vous à JARVIS pour relier un compte Gmail.'),
        ),
      ]);
    }
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(_cle(service)), child: _contenu(context, service)),
      ),
    );
  }

  String _cle(ServiceGmail s) => '${s.etat?.statut}-${s.enAttente}-${s.etat == null && s.erreur != null}';

  Widget _contenu(BuildContext context, ServiceGmail s) {
    final etat = s.etat;
    if (etat == null) {
      return CarteReglages(enfants: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: s.erreur == null
              ? const Row(children: [
                  SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: CouleursJarvis.signal)),
                  SizedBox(width: 14),
                  Text('Lecture de la connexion Gmail…', style: TextStyle(color: CouleursJarvis.texteSecondaire)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NoteReglage(s.erreur == ErreurApi.injoignable
                      ? 'Le serveur JARVIS est injoignable : état de Gmail indisponible.'
                      : 'État de Gmail indisponible pour le moment.'),
                  TextButton(onPressed: s.actualiser, child: const Text('Réessayer')),
                ]),
        ),
      ]);
    }
    final enfants = <Widget>[
      _EnTeteGmail(etat: etat, attente: s.enAttente),
      if (s.enAttente) _Attente(service: s) else ..._corps(context, s, etat),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarteReglages(enfants: enfants),
        if (s.information != null) ...[
          const SizedBox(height: 12),
          NoteReglage(s.information!),
        ],
        if (etat.statut != StatutGmail.nonConfigure) ...[
          const SizedBox(height: 18),
          const CarteReglages(titre: 'Autorisations', enfants: [_Autorisations()]),
        ],
      ],
    );
  }

  List<Widget> _corps(BuildContext context, ServiceGmail s, EtatGmail etat) => switch (etat.statut) {
    StatutGmail.nonConfigure => [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: NoteReglage('Gmail n’est pas encore configuré sur ce serveur JARVIS. '
            'L’administrateur doit d’abord renseigner les identifiants Google.'),
      ),
    ],
    StatutGmail.nonConnecte => [
      const _Texte('Connectez le compte Google que vous souhaitez utiliser avec JARVIS pour rechercher, '
          'consulter et résumer vos e-mails.'),
      _Actions(principal: ('Choisir un compte Google', s.connecter)),
    ],
    StatutGmail.connecte => [
      _Ligne('Compte', etat.email ?? '—'),
      const _Ligne('État', 'Connecté', couleur: Color(0xFF2E8B57)),
      _Ligne('Autorisation', etat.lectureSeule ? 'Lecture seule' : 'À vérifier'),
      _Actions(
        secondaire: ('Changer de compte', s.connecter),
        danger: ('Déconnecter Gmail', () => _confirmerDeconnexion(context, s)),
      ),
    ],
    StatutGmail.aRenouveler => [
      _Ligne('Compte', etat.email ?? '—'),
      const _Texte('La connexion Gmail doit être renouvelée.', important: true),
      _Actions(
        principal: ('Reconnecter Gmail', s.connecter),
        danger: ('Déconnecter Gmail', () => _confirmerDeconnexion(context, s)),
      ),
    ],
  };

  Future<void> _confirmerDeconnexion(BuildContext context, ServiceGmail s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: CouleursJarvis.coque,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Déconnecter Gmail ?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        content: const Text('JARVIS n’aura plus accès à ce compte et l’autorisation sera retirée chez Google. '
            'Vos e-mails ne sont pas touchés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CouleursJarvis.signal),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok == true) await s.deconnecter();
  }
}

class _EnTeteGmail extends StatelessWidget {
  const _EnTeteGmail({required this.etat, required this.attente});

  final EtatGmail etat;
  final bool attente;

  @override
  Widget build(BuildContext context) {
    final (titre, sous) = attente
        ? ('Connexion à Google…', 'Terminez la connexion dans le navigateur, puis revenez ici.')
        : switch (etat.statut) {
            StatutGmail.connecte => ('Gmail connecté', 'JARVIS peut consulter ce compte en lecture seule.'),
            StatutGmail.aRenouveler => ('Gmail à reconnecter', 'L’autorisation a expiré ou a été retirée.'),
            StatutGmail.nonConfigure => ('Gmail', 'Indisponible sur ce serveur.'),
            StatutGmail.nonConnecte => ('Connecter Gmail', 'Aucun compte Google relié.'),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: CouleursJarvis.ivoire, borderRadius: BorderRadius.circular(13),
              border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.7))),
          child: SvgPicture.asset('assets/logos/gmail.svg'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: CouleursJarvis.texte)),
            const SizedBox(height: 3),
            Text(sous, style: const TextStyle(fontSize: 12.5, color: CouleursJarvis.texteSecondaire)),
          ]),
        ),
      ]),
    );
  }
}

class _Attente extends StatelessWidget {
  const _Attente({required this.service});

  final ServiceGmail service;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: CouleursJarvis.signal)),
        const SizedBox(width: 14),
        const Expanded(
          child: Text('En attente de Google : choisissez le compte et acceptez la lecture des e-mails.',
              style: TextStyle(fontSize: 13, color: CouleursJarvis.texteSecondaire)),
        ),
        TextButton(onPressed: service.annulerAttente, child: const Text('Annuler')),
      ]),
    );
  }
}

class _Texte extends StatelessWidget {
  const _Texte(this.texte, {this.important = false});

  final String texte;
  final bool important;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(texte, style: TextStyle(fontSize: 14, height: 1.45,
            color: important ? CouleursJarvis.critique : CouleursJarvis.texte)),
      );
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.libelle, this.valeur, {this.couleur});

  final String libelle;
  final String valeur;
  final Color? couleur;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 16, runSpacing: 4, children: [
          Text(libelle, style: const TextStyle(fontSize: 14, color: CouleursJarvis.texteSecondaire)),
          Text(valeur, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
              color: couleur ?? CouleursJarvis.texte)),
        ]),
      );
}

typedef _Action = (String, VoidCallback);

class _Actions extends StatelessWidget {
  const _Actions({this.principal, this.secondaire, this.danger});

  final _Action? principal;
  final _Action? secondaire;
  final _Action? danger;

  @override
  Widget build(BuildContext context) {
    final forme = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        if (principal != null)
          FilledButton.icon(
            onPressed: principal!.$2,
            icon: const Icon(Icons.account_circle_outlined, size: 18),
            label: Text(principal!.$1),
            style: FilledButton.styleFrom(backgroundColor: CouleursJarvis.signal, minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18), shape: forme),
          ),
        if (secondaire != null)
          OutlinedButton.icon(
            onPressed: secondaire!.$2,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(secondaire!.$1),
            style: OutlinedButton.styleFrom(foregroundColor: CouleursJarvis.signal, minimumSize: const Size(0, 44),
                side: BorderSide(color: CouleursJarvis.signal.withValues(alpha: 0.4)), shape: forme),
          ),
        if (danger != null)
          TextButton(
            onPressed: danger!.$2,
            style: TextButton.styleFrom(foregroundColor: CouleursJarvis.texteSecondaire,
                minimumSize: const Size(0, 44), shape: forme),
            child: Text(danger!.$1),
          ),
      ]),
    );
  }
}

class _Autorisations extends StatelessWidget {
  const _Autorisations();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (icone, texte) in autorisationsGmail)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(icone, size: 18, color: CouleursJarvis.signal),
                const SizedBox(width: 10),
                Expanded(child: Text(texte, style: const TextStyle(fontSize: 13.5, color: CouleursJarvis.texte))),
              ]),
            ),
          const SizedBox(height: 4),
          const NoteReglage(interditsGmail),
        ]),
      );
}
