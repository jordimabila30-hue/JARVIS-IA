import 'package:flutter/foundation.dart';

import '../../models/importation/conversation_whatsapp.dart';
import '../../models/importation/filtre_whatsapp.dart';
import 'index_whatsapp.dart';

/// Capsule active du mode « Par période ».
enum CapsulePeriode {
  aujourdhui('Aujourd’hui'),
  hier('Hier'),
  septJours('7 derniers jours'),
  derniers('Derniers messages'),
  personnalise('Personnalisé');

  const CapsulePeriode(this.libelle);
  final String libelle;
}

/// Borne de la période personnalisée que le calendrier modifie.
enum BornePeriode { debut, fin }

/// État du filtrage d'UNE conversation lue (interface 2) : mode, filtre,
/// période personnalisée, mois du calendrier, et messages cochés. Il vit
/// dans la page d'import, avec la conversation : revenir à l'interface 1
/// puis rouvrir le filtrage retrouve tout ; un autre fichier crée un
/// nouvel état (jamais les filtres de l'ancien).
///
/// Sélection : un filtre donne des messages « correspondants », tous
/// cochés ; l'utilisateur peut en décocher et les recocher. Un nouveau
/// filtre garde décochés les messages qui l'étaient et qu'il contient
/// encore. Identifiants stables (`m<ordre>`), jamais un rang d'affichage.
class SelectionWhatsApp extends ChangeNotifier {
  SelectionWhatsApp(this.conversation, {DateTime Function()? horloge})
    : index = IndexWhatsApp(conversation),
      _horloge = horloge ?? DateTime.now {
    _coches = Uint8List(index.nombre);
    final dernier = index.dernierJour ?? _horloge();
    _moisAffiche = DateTime(dernier.year, dernier.month);
  }

  final ConversationWhatsApp conversation;
  final IndexWhatsApp index;
  final DateTime Function() _horloge;

  static const finAvantDebut = 'La fin est avant le début.';

  // --- Mode et filtre ------------------------------------------------------

  ModeFiltrage _mode = ModeFiltrage.periode;
  ModeFiltrage get mode => _mode;

  CapsulePeriode? _capsule;
  CapsulePeriode? get capsule => _capsule;

  FiltreWhatsApp? _filtre;

  /// Dernier filtre appliqué (null : aucun).
  FiltreWhatsApp? get filtre => _filtre;

  /// Période personnalisée en cours d'édition (gardée même invalide).
  FiltrePeriode? _periode;
  FiltrePeriode? get periode => _periode;

  /// Message de la période invalide (null : aucun problème).
  String? get erreurPeriode =>
      _periode != null && !_periode!.valide ? finAvantDebut : null;

  DateTime _moisAffiche = DateTime(2000);

  /// Mois affiché par le calendrier (1er du mois).
  DateTime get moisAffiche => _moisAffiche;

  // Calendrier : premier jour touché d'une plage de jours.
  DateTime? _ancreJour;

  // --- Sélection -----------------------------------------------------------

  late Uint8List _coches;
  int _nombre = 0;
  List<int> _correspondants = const [];

  // Plage du mode « Par messages » : premier message désigné.
  int? _ancrePlage;
  bool _plageEnCours = false;

  int _version = 0;

  /// Change quand la liste affichée change (pas à chaque coche).
  int get versionAffichage => _version;

  /// Nombre de messages cochés.
  int get nombreSelectionnes => _nombre;

  /// Messages correspondant au filtre actif (ordre d'origine).
  List<MessageWhatsApp> get correspondants => [
    for (final p in _correspondants) index.messages[p],
  ];
  int get nombreCorrespondants => _correspondants.length;

  /// Choix d'une plage en cours (mode « Par messages »).
  bool get plageEnCours => _plageEnCours;

  /// Premier message désigné de la plage (null : pas encore).
  String? get premierDeLaPlage =>
      _ancrePlage == null ? null : index.messages[_ancrePlage!].id;

  /// Le mode « Par période » montre les messages du filtre de période
  /// actif ; sinon (et en mode « Par messages »), toute la conversation.
  bool get afficheCorrespondants =>
      _mode == ModeFiltrage.periode &&
      _filtre != null &&
      _filtre is! FiltrePlage;

  /// Messages affichés dans l'aperçu, ordre d'origine (événements de
  /// WhatsApp compris quand toute la conversation est montrée).
  List<MessageWhatsApp> get visibles =>
      afficheCorrespondants ? correspondants : conversation.messages;

  bool estCoche(String id) {
    final p = index.position(id);
    return p != null && _coches[p] == 1;
  }

  /// Sélectionnable (message d'un participant) ?
  bool estSelectionnable(String id) => index.position(id) != null;

  // --- Actions -------------------------------------------------------------

  void changerMode(ModeFiltrage mode) {
    if (mode == _mode) return;
    _mode = mode;
    _plageEnCours = false;
    _ancrePlage = null;
    _version++;
    notifyListeners();
  }

  /// Applique un filtre : ses messages sont cochés, sauf ceux que
  /// l'utilisateur avait décochés parmi les correspondants précédents.
  void appliquer(FiltreWhatsApp filtre) {
    final nouveaux = index.resultat(filtre, _horloge());
    final decoches = <int>{
      for (final p in _correspondants)
        if (_coches[p] == 0) p,
    };
    _coches.fillRange(0, _coches.length, 0);
    var n = 0;
    for (final p in nouveaux) {
      if (decoches.contains(p)) continue;
      _coches[p] = 1;
      n++;
    }
    _nombre = n;
    _correspondants = nouveaux;
    _filtre = filtre;
    _version++;
    notifyListeners();
  }

  /// Capsule du mode « Par période ». Les jours relatifs s'appliquent
  /// aussitôt ; « Personnalisé » reprend la période en cours (sinon le
  /// dernier jour ayant des messages) ; « Derniers messages » commence
  /// par le plus petit nombre proposé (ou garde celui choisi).
  void choisirCapsule(CapsulePeriode capsule) {
    _capsule = capsule;
    switch (capsule) {
      case CapsulePeriode.aujourdhui:
        appliquer(const FiltreJourRelatif(JourRelatif.aujourdhui));
      case CapsulePeriode.hier:
        appliquer(const FiltreJourRelatif(JourRelatif.hier));
      case CapsulePeriode.septJours:
        appliquer(const FiltreJourRelatif(JourRelatif.septDerniersJours));
      case CapsulePeriode.derniers:
        if (_filtre is FiltreDerniers) {
          notifyListeners();
        } else {
          appliquer(FiltreDerniers(nombresDerniers.first));
        }
      case CapsulePeriode.personnalise:
        final p = _periode;
        if (p != null) {
          _afficherMoisDe(p.debut);
          if (p.valide) {
            appliquer(p);
          } else {
            notifyListeners();
          }
          return;
        }
        final dernier = index.dernierJour;
        if (dernier == null) {
          notifyListeners();
          return;
        }
        // Choisi pour l'aperçu immédiat, pas par l'utilisateur : le
        // premier jour touché commence une nouvelle période.
        _ancreJour = null;
        definirPeriode(FiltrePeriode.jour(dernier));
    }
  }

  /// Nombres proposés pour « Derniers messages », bornés au nombre réel :
  /// 10, 25, 50, 100 s'ils sont inférieurs, puis le total (« tous »).
  List<int> get nombresDerniers {
    final total = index.nombre;
    final r = [
      for (final n in FiltreDerniers.choix)
        if (n < total) n,
    ];
    if (total > 0 && total <= FiltreDerniers.choix.last) r.add(total);
    return r.isEmpty ? [total] : r;
  }

  void choisirDerniers(int nombre) {
    _capsule = CapsulePeriode.derniers;
    appliquer(FiltreDerniers(nombre));
  }

  /// Période personnalisée : appliquée si elle est valide ; sinon gardée
  /// (pour correction) avec [erreurPeriode], la sélection ne change pas.
  void definirPeriode(FiltrePeriode periode) {
    _capsule = CapsulePeriode.personnalise;
    _periode = periode;
    if (periode.valide) {
      appliquer(periode);
    } else {
      notifyListeners();
    }
  }

  void modifierDebut(DateTime debut) {
    final p = _periode ?? FiltrePeriode.jour(debut);
    _ancreJour = null;
    definirPeriode(FiltrePeriode(debut, p.fin));
  }

  void modifierFin(DateTime fin) {
    final p = _periode ?? FiltrePeriode.jour(fin);
    _ancreJour = null;
    definirPeriode(FiltrePeriode(p.debut, fin));
  }

  BornePeriode? _cible;

  /// Borne que le prochain jour touché remplacera (null : plage de jours).
  BornePeriode? get cible => _cible;

  /// « Début » ou « Fin » touché : le calendrier montre son mois et le
  /// prochain jour touché devient sa date (l'heure est gardée).
  void ciblerDate(BornePeriode? borne) {
    _cible = borne;
    final p = _periode;
    if (p != null && borne != null) {
      _afficherMoisDe(borne == BornePeriode.debut ? p.debut : p.fin);
    }
    notifyListeners();
  }

  /// Jour touché dans le calendrier. Avec une borne ciblée, il devient sa
  /// date. Sinon un premier toucher choisit le jour entier ; un second,
  /// sur un autre jour, étend la période jusqu'à lui ; le suivant
  /// recommence. Un jour sans message n'est pas choisi.
  void choisirJour(DateTime jour) {
    if (index.nombreLeJour(jour) == 0) return;
    final cible = _cible;
    final p0 = _periode;
    if (cible != null && p0 != null) {
      _cible = null;
      final b = cible == BornePeriode.debut ? p0.debut : p0.fin;
      final d = DateTime(jour.year, jour.month, jour.day, b.hour, b.minute);
      cible == BornePeriode.debut ? modifierDebut(d) : modifierFin(d);
      return;
    }
    final ancre = _ancreJour;
    final p = _periode;
    final memeJour =
        ancre != null &&
        ancre.year == jour.year &&
        ancre.month == jour.month &&
        ancre.day == jour.day;
    if (ancre != null && !memeJour && p != null && p.estJourEntier) {
      _ancreJour = null;
      definirPeriode(FiltrePeriode.jours(ancre, jour));
      return;
    }
    _ancreJour = DateTime(jour.year, jour.month, jour.day);
    definirPeriode(FiltrePeriode.jour(jour));
  }

  /// Le calendrier attend-il le second jour d'une plage ?
  bool get calendrierAttendFin => _ancreJour != null;

  void afficherMois(int annee, int mois) {
    final m = DateTime(annee, mois);
    if (m == _moisAffiche) return;
    _moisAffiche = m;
    notifyListeners();
  }

  void _afficherMoisDe(DateTime d) => _moisAffiche = DateTime(d.year, d.month);

  /// Coche ou décoche un message.
  void basculer(String id) {
    final p = index.position(id);
    if (p == null) return;
    _ecrire(p, _coches[p] == 0);
    notifyListeners();
  }

  /// Coche ou décoche plusieurs messages (un groupe de médias).
  void cocher(Iterable<String> ids, bool coche) {
    var change = false;
    for (final id in ids) {
      final p = index.position(id);
      if (p == null) continue;
      change |= _ecrire(p, coche);
    }
    if (change) notifyListeners();
  }

  /// Coche ou décoche tous les messages affichés.
  void cocherVisibles(bool coche) =>
      cocher([for (final m in visibles) m.id], coche);

  bool _ecrire(int p, bool coche) {
    final v = coche ? 1 : 0;
    if (_coches[p] == v) return false;
    _coches[p] = v;
    _nombre += coche ? 1 : -1;
    return true;
  }

  /// Mode « Par messages » : commence (ou abandonne) le choix d'une plage.
  void commencerPlage() {
    _plageEnCours = true;
    _ancrePlage = null;
    notifyListeners();
  }

  void annulerPlage() {
    _plageEnCours = false;
    _ancrePlage = null;
    notifyListeners();
  }

  /// Message touché pendant le choix d'une plage : le premier, puis le
  /// dernier (la plage est alors appliquée).
  void designer(String id) {
    final p = index.position(id);
    if (!_plageEnCours || p == null) return;
    final ancre = _ancrePlage;
    if (ancre == null) {
      _ancrePlage = p;
      notifyListeners();
      return;
    }
    _plageEnCours = false;
    _ancrePlage = null;
    appliquer(FiltrePlage(index.messages[ancre].id, id));
  }

  /// Messages cochés, prêts pour l'enregistrement (interface 3). Rien
  /// n'est enregistré ici.
  MessagesChoisisWhatsApp resultat() => MessagesChoisisWhatsApp(
    conversationSource: conversation.identifiant,
    titre: conversation.titre,
    nomFichier: conversation.nomFichier,
    dateIncertaine: conversation.dateIncertaine,
    messages: [
      for (var p = 0; p < _coches.length; p++)
        if (_coches[p] == 1) index.messages[p],
    ],
  );
}
