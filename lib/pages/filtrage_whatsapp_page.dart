import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/importation/filtre_whatsapp.dart';
import '../services/importation/selection_whatsapp.dart';
import '../theme/theme_jarvis.dart';
import '../widgets/defilement_sans_barre.dart';
import '../widgets/importation/apercu_discussion.dart';
import '../widgets/importation/filtrage/apercu_selection.dart';
import '../widgets/importation/filtrage/barre_selection.dart';
import '../widgets/importation/filtrage/commandes_messages.dart';
import '../widgets/importation/filtrage/commandes_periode.dart';
import '../widgets/importation/filtrage/selecteur_mode_filtrage.dart';
import '../widgets/importation/lecture_whatsapp_widgets.dart';
import '../widgets/importation/logo_whatsapp.dart';

/// Import WhatsApp — interface 2 : choisir les messages à garder dans la
/// conversation déjà lue (rien n'est relu ni décompressé). Par période
/// (aujourd'hui, hier, 7 jours, derniers messages, période personnalisée
/// avec calendrier) ou par messages (plage, cases) ; l'aperçu montre la
/// sélection aussitôt. L'état ([selection]) appartient à la page d'import :
/// revenir ne perd rien. Rien n'est enregistré ni envoyé ici.
class FiltrageWhatsAppPage extends StatefulWidget {
  const FiltrageWhatsAppPage({
    super.key,
    required this.selection,
    this.surContinuer,
  });

  static const titre = 'Filtrer les messages';

  final SelectionWhatsApp selection;

  /// Ouverture de l'enregistrement (interface 3) avec les messages
  /// choisis. Null tant qu'elle n'existe pas : le bouton reste inactif.
  final void Function(MessagesChoisisWhatsApp choisis)? surContinuer;

  @override
  State<FiltrageWhatsAppPage> createState() => _FiltrageWhatsAppPageState();
}

class _FiltrageWhatsAppPageState extends State<FiltrageWhatsAppPage> {
  late DispositionAuteurs _disposition = DispositionAuteurs(
    widget.selection.conversation,
  );

  @override
  void didUpdateWidget(FiltrageWhatsAppPage ancien) {
    super.didUpdateWidget(ancien);
    if (!identical(ancien.selection, widget.selection)) {
      _disposition = DispositionAuteurs(widget.selection.conversation);
    }
  }

  void _retour() => Navigator.of(context).maybePop();

  Widget _commandes(SelectionWhatsApp s) {
    final avis = s.mode == ModeFiltrage.periode ? avisSansDate(s) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: s.mode == ModeFiltrage.periode
              ? CommandesPeriode(selection: s)
              : CommandesMessages(selection: s),
        ),
        if (avis != null) ...[
          const SizedBox(height: 8),
          Text(
            avis,
            style: TextStyle(
              fontSize: 12,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.sizeOf(context);
    final large = taille.width >= 900;
    final marge = taille.width < 600 ? 12.0 : 24.0;
    final surContinuer = widget.surContinuer;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _retour},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: CouleursJarvis.ivoire,
          body: DecoratedBox(
            decoration: BoxDecoration(gradient: degradeFondJarvis),
            child: SizedBox.expand(
              child: SafeArea(
                bottom: false,
                child: ListenableBuilder(
                  listenable: widget.selection,
                  builder: (context, _) {
                    final s = widget.selection;
                    final entete = Padding(
                      padding: EdgeInsets.fromLTRB(marge, 6, marge, 8),
                      child: _Entete(
                        nom: s.conversation.titre,
                        nombre: s.conversation.messages.length,
                        surRetour: _retour,
                      ),
                    );
                    final mode = SelecteurModeFiltrage(
                      mode: s.mode,
                      surChoix: s.changerMode,
                    );
                    final apercu = LayoutBuilder(
                      // Très peu de hauteur : les messages d'abord.
                      builder: (context, zone) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (zone.maxHeight >= 150)
                            Padding(
                              padding: EdgeInsets.fromLTRB(marge, 2, marge, 0),
                              child: EnteteApercu(selection: s),
                            ),
                          Expanded(
                            child: ApercuSelection(
                              selection: s,
                              disposition: _disposition,
                              navigation: s.mode == ModeFiltrage.messages,
                              marges: EdgeInsets.fromLTRB(marge, 6, marge, 10),
                            ),
                          ),
                        ],
                      ),
                    );
                    final barre = DecoratedBox(
                      decoration: BoxDecoration(
                        color: CouleursJarvis.coque.withValues(alpha: 0.96),
                        border: Border(
                          top: BorderSide(
                            color: CouleursJarvis.trait.withValues(alpha: 0.6),
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: CouleursJarvis.texte.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        minimum: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(marge, 10, marge, 0),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: BarreSelection(
                                nombre: s.nombreSelectionnes,
                                surContinuer: surContinuer == null
                                    ? null
                                    : () => surContinuer(s.resultat()),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    final separateur = Divider(
                      height: 1,
                      color: CouleursJarvis.trait.withValues(alpha: 0.6),
                    );
                    if (large) {
                      // Ordinateur : commandes à gauche, aperçu à droite.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          entete,
                          separateur,
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 420,
                                  child: ScrollConfiguration(
                                    behavior: const DefilementSansBarre(),
                                    child: SingleChildScrollView(
                                      padding: EdgeInsets.fromLTRB(
                                        marge,
                                        14,
                                        marge,
                                        14,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          mode,
                                          const SizedBox(height: 14),
                                          _commandes(s),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                VerticalDivider(
                                  width: 1,
                                  color: CouleursJarvis.trait.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: apercu,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          barre,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        entete,
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, zone) => _Empilement(
                              hauteur: zone.maxHeight,
                              marge: marge,
                              mode: mode,
                              commandes: _commandes(s),
                              separateur: separateur,
                              apercu: apercu,
                              // Le calendrier a besoin de plus de place.
                              etendu:
                                  s.mode == ModeFiltrage.periode &&
                                  s.capsule == CapsulePeriode.personnalise,
                            ),
                          ),
                        ),
                        barre,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Téléphone : mode, commandes, aperçu, les uns sous les autres. Les
/// commandes sont bornées (le calendrier défile) pour que l'aperçu garde
/// au moins 180 px ; sur un écran court (paysage, grande police), le
/// sélecteur de mode défile avec elles ; s'il ne reste presque rien, tout
/// défile ensemble.
class _Empilement extends StatelessWidget {
  const _Empilement({
    required this.hauteur,
    required this.marge,
    required this.mode,
    required this.commandes,
    required this.separateur,
    required this.apercu,
    this.etendu = false,
  });

  final double hauteur;
  final double marge;
  final Widget mode;
  final Widget commandes;
  final Widget separateur;
  final Widget apercu;
  final bool etendu;

  @override
  Widget build(BuildContext context) {
    // Presque plus de place (petit écran et très grande police) : tout
    // défile ensemble, l'aperçu garde une hauteur fixe.
    if (hauteur < 300) {
      return ScrollConfiguration(
        behavior: const DefilementSansBarre(),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(marge, 0, marge, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [mode, const SizedBox(height: 10), commandes],
                ),
              ),
              separateur,
              SizedBox(height: 320, child: apercu),
            ],
          ),
        ),
      );
    }
    final court = hauteur < 520;
    Widget defilant(Widget enfant) => ScrollConfiguration(
      behavior: const DefilementSansBarre(),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(marge, 0, marge, 8),
        child: enfant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!court) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: marge),
            child: mode,
          ),
          const SizedBox(height: 10),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(
            // L'aperçu garde au moins 180 px.
            maxHeight: math.max(
              0,
              math.min(
                hauteur * (court ? 0.45 : (etendu ? 0.56 : 0.36)),
                hauteur - 180,
              ),
            ),
          ),
          child: defilant(
            court
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [mode, const SizedBox(height: 10), commandes],
                  )
                : commandes,
          ),
        ),
        separateur,
        Expanded(child: apercu),
      ],
    );
  }
}

/// Retour, logo WhatsApp, « Filtrer les messages », nom de la
/// conversation et nombre réel de messages.
class _Entete extends StatelessWidget {
  const _Entete({
    required this.nom,
    required this.nombre,
    required this.surRetour,
  });

  final String nom;
  final int nombre;
  final VoidCallback surRetour;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: surRetour,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            foregroundColor: CouleursJarvis.texte,
            minimumSize: const Size(44, 44),
            side: BorderSide(
              color: CouleursJarvis.trait.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const LogoWhatsApp(taille: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  FiltrageWhatsAppPage.titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: policeAffichage,
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: CouleursJarvis.texte,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$nom · ${nombreEnFrancais(nombre)} '
                'message${nombre > 1 ? 's' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: CouleursJarvis.texteSecondaire,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
