import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_jarvis.dart';
import '../../services/conversations/depot_conversations.dart';
import '../../services/importation/actualisation_whatsapp.dart';
import '../../services/importation/analyseur_whatsapp.dart';
import '../../theme/theme_jarvis.dart';
import 'logo_whatsapp.dart';

/// Ouvre le volet « Actualiser la conversation WhatsApp » (phase 5) par-
/// dessus le chat : le brouillon, la pièce jointe en attente, la position
/// dans l'historique, le vocal et PIM ne sont pas touchés. Renvoie les
/// messages enregistrés et leur contexte (null : fermé sans ajout) : ils
/// apparaissent en bulles dans le fil.
Future<AjoutsEnregistres?> afficherVoletActualisation(
  BuildContext context, {
  required ServiceActualisationWhatsApp service,
  List<ContexteServeur> contextesDuChat = const [],
}) {
  return showModalBottomSheet<AjoutsEnregistres>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: CouleursJarvis.texte.withValues(alpha: 0.16),
    elevation: 0,
    builder: (context) =>
        VoletActualisation(service: service, contextesDuChat: contextesDuChat),
  );
}

/// Saisies d'un volet fermé sans enregistrement (appui à côté, retour) :
/// rendues à la réouverture pour la même conversation WhatsApp, avec les
/// mêmes identifiants (un réessai ne duplique rien). En mémoire seulement.
final brouillonsActualisation = <String, List<EntreeActualisation>>{};

typedef AjoutsEnregistres = ({
  ContexteServeur contexte,
  List<MessageAjoute> messages,
});

class VoletActualisation extends StatefulWidget {
  const VoletActualisation({
    super.key,
    required this.service,
    this.contextesDuChat = const [],
  });

  final ServiceActualisationWhatsApp service;

  /// Pièces jointes du chat affiché : une seule → proposée d'emblée ;
  /// plusieurs → l'utilisateur choisit ; aucune → toutes celles du compte.
  final List<ContexteServeur> contextesDuChat;

  static const sousTitre = 'Actualiser la conversation WhatsApp';
  static const indication = 'Colle ici le message WhatsApp…';

  @override
  State<VoletActualisation> createState() => _VoletActualisationState();
}

class _VoletActualisationState extends State<VoletActualisation> {
  List<ContexteServeur> _contextes = const [];
  ContexteServeur? _choisi;
  bool _chargement = false;
  final _entrees = <EntreeActualisation>[EntreeActualisation()];
  final _textes = <String, TextEditingController>{};
  final _dates = <String, TextEditingController>{};
  List<Correspondance> _doublons = const [];
  String? _erreur;
  bool _envoi = false;
  List<MessageAjoute>? _ajoutes;
  String? _enEdition;

  /// Options secondaires (5.1) : plusieurs messages, date, ajouts
  /// précédents. La vue principale reste minimale.
  bool _options = false;
  final _edition = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.contextesDuChat.isNotEmpty) {
      _contextes = widget.contextesDuChat;
      if (_contextes.length == 1) _choisir(_contextes.single);
    } else {
      _chargerTous();
    }
  }

  // Vrai après un enregistrement réussi : plus de brouillon à garder.
  bool _enregistre = false;

  @override
  void dispose() {
    final c = _choisi;
    if (c != null && !_enregistre) {
      for (final e in _entrees) {
        e.texte = _textes[e.id]?.text ?? e.texte;
        e.dateBrute = _dates[e.id]?.text ?? e.dateBrute;
      }
      if (_entrees.any((e) => e.texte.trim().isNotEmpty)) {
        brouillonsActualisation[c.id] = List.of(_entrees);
      } else {
        brouillonsActualisation.remove(c.id);
      }
    }
    for (final c in [..._textes.values, ..._dates.values]) {
      c.dispose();
    }
    _edition.dispose();
    super.dispose();
  }

  Future<void> _chargerTous() async {
    setState(() => _chargement = true);
    final r = await widget.service.contextes();
    if (!mounted) return;
    setState(() {
      _chargement = false;
      switch (r) {
        case SuccesApi(:final valeur):
          _contextes = valeur;
          if (valeur.isEmpty) {
            _erreur = 'Aucune conversation WhatsApp enregistrée.';
          }
        case EchecApi():
          _erreur = 'Conversations WhatsApp indisponibles. Réessayez.';
      }
    });
  }

  void _choisir(ContexteServeur c) {
    setState(() {
      _choisi = c;
      // Volet fermé par erreur : la saisie revient telle quelle.
      final brouillon = brouillonsActualisation[c.id];
      if (brouillon != null && _entrees.every((e) => e.texte.trim().isEmpty)) {
        _entrees
          ..clear()
          ..addAll(brouillon);
        _textes.clear();
        _dates.clear();
      }
      _doublons = const [];
      _erreur = null;
      for (final e in _entrees) {
        // Jamais un auteur d'un autre contact par supposition.
        if (e.auteur != null && !_autres(c).contains(e.auteur)) e.auteur = null;
      }
    });
    _chargerAjoutes();
  }

  Future<void> _chargerAjoutes() async {
    final c = _choisi;
    if (c == null) return;
    final r = await widget.service.ajoutes(c.id);
    if (!mounted || _choisi?.id != c.id) return;
    setState(
      () => _ajoutes = r is SuccesApi<List<MessageAjoute>> ? r.valeur : null,
    );
  }

  List<String> _autres(ContexteServeur c) {
    final autres = [
      for (final p in c.participants)
        if (p != c.moi) p,
    ];
    return autres.isEmpty ? [c.contact] : autres;
  }

  /// Auteur effectif d'une entrée reçue (null : à choisir).
  String? _auteurDe(EntreeActualisation e) {
    final c = _choisi;
    if (c == null) return null;
    final autres = _autres(c);
    if (e.auteur != null) return e.auteur;
    return !c.groupe && autres.length == 1 ? autres.single : null;
  }

  TextEditingController _texte(EntreeActualisation e) =>
      _textes.putIfAbsent(e.id, () => TextEditingController(text: e.texte));
  TextEditingController _date(EntreeActualisation e) =>
      _dates.putIfAbsent(e.id, () => TextEditingController(text: e.dateBrute));

  bool get _valide {
    final c = _choisi;
    if (c == null || _envoi) return false;
    return _entrees.every(
      (e) =>
          e.texte.trim().isNotEmpty &&
          _dateValide(e) &&
          (e.sens == SensMessage.envoye ? c.moi != null : _auteurDe(e) != null),
    );
  }

  bool _dateValide(EntreeActualisation e) =>
      e.dateBrute.trim().isEmpty || e.date != null;

  static final _formatDate = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2})[:h](\d{2}))?$',
  );

  void _changerDate(EntreeActualisation e, String brut) {
    e.dateBrute = brut.trim();
    final m = _formatDate.firstMatch(e.dateBrute);
    DateTime? d;
    if (m != null) {
      final j = int.parse(m[1]!), mo = int.parse(m[2]!), a = int.parse(m[3]!);
      final h = int.tryParse(m[4] ?? '') ?? 0,
          mi = int.tryParse(m[5] ?? '') ?? 0;
      final essai = DateTime(a, mo, j, h, mi);
      if (essai.day == j && essai.month == mo && h < 24 && mi < 60) d = essai;
    }
    setState(() => e.date = d);
  }

  /// Extrait WhatsApp collé (en-têtes reconnus par le parseur de l'import) :
  /// messages proposés, jamais découpés sans l'accord de l'utilisateur.
  List<({String? auteur, String texte, DateTime? date, String brute})> _extrait(
    String texte,
  ) {
    if (!texte.contains('\n') &&
        !texte.contains(' - ') &&
        !texte.startsWith('[')) {
      return const [];
    }
    final a = AnalyseurWhatsApp();
    for (final l in const LineSplitter().convert(texte)) {
      a.ajouterLigne(l);
    }
    final c = a.terminer(nomFichier: 'extrait.txt');
    return [
      for (final m in c.messages)
        if (m.auteur != null)
          (auteur: m.auteur, texte: m.texte, date: m.date, brute: m.dateBrute),
    ];
  }

  void _separer(EntreeActualisation e) {
    final c = _choisi;
    final morceaux = _extrait(e.texte);
    if (c == null || morceaux.isEmpty) return;
    final i = _entrees.indexOf(e);
    setState(() {
      _entrees
        ..removeAt(i)
        ..insertAll(i, [
          for (final m in morceaux)
            EntreeActualisation(
              sens: m.auteur == c.moi ? SensMessage.envoye : SensMessage.recu,
              // Auteur inconnu du contexte : laissé à choisir, jamais deviné.
              auteur: m.auteur != c.moi && _autres(c).contains(m.auteur)
                  ? m.auteur
                  : null,
              texte: m.texte,
              date: m.date,
              dateBrute: m.brute,
            ),
        ]);
      _doublons = const [];
    });
  }

  void _deplacer(int i, int de) {
    final j = i + de;
    if (j < 0 || j >= _entrees.length) return;
    setState(() {
      final e = _entrees.removeAt(i);
      _entrees.insert(j, e);
      _doublons = const [];
    });
  }

  Future<void> _confirmer({bool malgreDoublons = false}) async {
    final c = _choisi;
    if (c == null || !_valide) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    for (final e in _entrees) {
      if (e.sens == SensMessage.recu) e.auteur = _auteurDe(e);
    }
    final r = await widget.service.ajouter(
      c.id,
      List.of(_entrees),
      confirmer: malgreDoublons,
    );
    if (!mounted) return;
    switch (r) {
      case AjoutReussi(:final messages):
        _enregistre = true;
        brouillonsActualisation.remove(c.id);
        Navigator.of(context).pop((contexte: c, messages: messages));
      case DoublonsPossibles(:final items):
        setState(() {
          _envoi = false;
          _doublons = items;
        });
      case EchecAjout(:final message):
        setState(() {
          _envoi = false;
          _erreur = message;
        });
    }
  }

  void _retirerDoublons() {
    final indices = {for (final d in _doublons) d.index};
    setState(() {
      final gardees = [
        for (final (i, e) in _entrees.indexed)
          if (!indices.contains(i)) e,
      ];
      _entrees
        ..clear()
        ..addAll(gardees.isEmpty ? [EntreeActualisation()] : gardees);
      _doublons = const [];
    });
  }

  Future<void> _supprimerAjout(MessageAjoute m) async {
    final c = _choisi;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CouleursJarvis.coque,
        title: const Text('Supprimer ce message ajouté ?'),
        content: Text(
          '« ${m.texte} »',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('confirmer-suppression-ajout'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.service.supprimer(c.id, m.id);
    if (!mounted) return;
    if (r is EchecApi) {
      setState(() => _erreur = 'Suppression impossible. Réessayez.');
    }
    await _chargerAjoutes();
  }

  Future<void> _enregistrerCorrection(MessageAjoute m) async {
    final c = _choisi;
    final texte = _edition.text.trim();
    if (c == null || texte.isEmpty) return;
    final r = await widget.service.modifier(c.id, m.id, texte: texte);
    if (!mounted) return;
    if (r is EchecApi) {
      setState(() => _erreur = 'Correction impossible. Réessayez.');
      return;
    }
    setState(() => _enEdition = null);
    await _chargerAjoutes();
  }

  @override
  Widget build(BuildContext context) {
    final c = _choisi;
    final hauteur = MediaQuery.sizeOf(context).height;
    return Padding(
      // Le clavier ne cache jamais le volet.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        key: const Key('volet-actualisation'),
        constraints: BoxConstraints(maxHeight: hauteur * 0.88),
        decoration: const BoxDecoration(
          color: CouleursJarvis.coque,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: CouleursJarvis.trait)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            10,
            18,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CouleursJarvis.trait,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const LogoWhatsApp(taille: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c?.contact ?? 'Choisissez la conversation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: CouleursJarvis.texte,
                          ),
                        ),
                        const Text(
                          VoletActualisation.sousTitre,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: CouleursJarvis.texteSecondaire,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_chargement)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CouleursJarvis.violet,
                    ),
                  ),
                ),
              if (_contextes.length > 1 ||
                  (c == null && _contextes.isNotEmpty)) ...[
                const SizedBox(height: 12),
                const _Titre('Quelle conversation actualiser ?'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final x in _contextes)
                      ChoiceChip(
                        key: Key('contexte-${x.id}'),
                        label: Text(
                          x.groupe ? '${x.contact} (groupe)' : x.contact,
                        ),
                        selected: c?.id == x.id,
                        onSelected: (_) => _choisir(x),
                        selectedColor: CouleursJarvis.lavande,
                        backgroundColor: CouleursJarvis.coque,
                        side: const BorderSide(color: CouleursJarvis.lavande),
                      ),
                  ],
                ),
              ],
              if (c != null) ...[
                for (final (i, e) in _entrees.indexed) ...[
                  const SizedBox(height: 12),
                  _carte(i, e, c),
                ],
                if (_options)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('ajouter-entree'),
                      onPressed: _entrees.length >= 50
                          ? null
                          : () => setState(() {
                              _entrees.add(EntreeActualisation());
                              _doublons = const [];
                            }),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Ajouter un autre message'),
                      style: TextButton.styleFrom(
                        foregroundColor: CouleursJarvis.signal,
                      ),
                    ),
                  ),
                if (_doublons.isNotEmpty) _avertissementDoublons(),
              ],
              if (_erreur case final e?) ...[
                const SizedBox(height: 8),
                Text(
                  e,
                  key: const Key('erreur-actualisation'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB3261E),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    key: const Key('options-actualisation'),
                    onPressed: c == null
                        ? null
                        : () => setState(() => _options = !_options),
                    icon: Icon(
                      _options ? Icons.expand_less_rounded : Icons.tune_rounded,
                      size: 18,
                    ),
                    label: const Text('Options'),
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursJarvis.texteSecondaire,
                    ),
                  ),
                  FilledButton(
                    key: const Key('confirmer-ajout'),
                    onPressed: _valide && _doublons.isEmpty ? _confirmer : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: CouleursJarvis.signal,
                    ),
                    child: _envoi
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Ajouter'),
                  ),
                ],
              ),
              if (_options && c != null && (_ajoutes?.isNotEmpty ?? false))
                _sectionAjoutes(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carte(int i, EntreeActualisation e, ContexteServeur c) {
    final autres = _autres(c);
    final extrait = _extrait(e.texte);
    return Container(
      key: Key('entree-$i'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      decoration: BoxDecoration(
        color: CouleursJarvis.ivoire,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleursJarvis.lavande),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<SensMessage>(
                  key: Key('sens-$i'),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: CouleursJarvis.lavande,
                    selectedForegroundColor: CouleursJarvis.signal,
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final s in SensMessage.values)
                      ButtonSegment(
                        value: s,
                        label: Text(s.libelle),
                        enabled: s == SensMessage.recu || c.moi != null,
                      ),
                  ],
                  selected: {e.sens},
                  onSelectionChanged: (s) => setState(() {
                    e.sens = s.single;
                    _doublons = const [];
                  }),
                ),
              ),
              if (_entrees.length > 1) ...[
                IconButton(
                  tooltip: 'Monter',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: i == 0 ? null : () => _deplacer(i, -1),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Descendre',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: i == _entrees.length - 1
                      ? null
                      : () => _deplacer(i, 1),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                ),
                IconButton(
                  key: Key('retirer-entree-$i'),
                  tooltip: 'Retirer',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: _entrees.length == 1
                      ? null
                      : () => setState(() {
                          _entrees.removeAt(i);
                          _doublons = const [];
                        }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (e.sens == SensMessage.envoye)
            Text(
              'De : ${c.moi} (vous)',
              style: const TextStyle(
                fontSize: 13,
                color: CouleursJarvis.texteSecondaire,
              ),
            )
          else if (!c.groupe && autres.length == 1)
            Text(
              'De : ${autres.single}',
              key: Key('auteur-$i'),
              style: const TextStyle(
                fontSize: 13,
                color: CouleursJarvis.texteSecondaire,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('De :', style: TextStyle(fontSize: 13)),
                for (final p in autres)
                  ChoiceChip(
                    key: Key('auteur-$i-$p'),
                    label: Text(p),
                    selected: e.auteur == p,
                    onSelected: (_) => setState(() {
                      e.auteur = p;
                      _doublons = const [];
                    }),
                    selectedColor: CouleursJarvis.lavande,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          const SizedBox(height: 6),
          TextField(
            key: Key('texte-entree-$i'),
            controller: _texte(e),
            minLines: 2,
            maxLines: 6,
            onChanged: (t) => setState(() {
              e.texte = t;
              _doublons = const [];
            }),
            decoration: const InputDecoration(
              hintText: VoletActualisation.indication,
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (extrait.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('separer-$i'),
                onPressed: () => _separer(e),
                icon: const Icon(Icons.call_split_rounded, size: 18),
                label: Text(
                  'Extrait WhatsApp reconnu : séparer en ${extrait.length} messages',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: CouleursJarvis.signal,
                ),
              ),
            ),
          if (_options) ...[
            const SizedBox(height: 6),
            TextField(
              key: Key('date-entree-$i'),
              controller: _date(e),
              onChanged: (t) => _changerDate(e, t),
              decoration: InputDecoration(
                hintText: 'Date et heure (facultatif) : jj/mm/aaaa hh:mm',
                isDense: true,
                errorText: _dateValide(e) ? null : 'Format : 16/10/2026 09:12',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avertissementDoublons() {
    return Container(
      key: const Key('doublons'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CouleursJarvis.violetPoudre.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Déjà connu de JARVIS :',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          for (final d in _doublons)
            Text(
              d.declaration
                  ? '• « ${d.texte} » : proposition déjà déclarée envoyée'
                  : '• « ${d.texte} » : déjà présent dans la conversation',
              style: const TextStyle(fontSize: 13),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('retirer-doublons'),
                onPressed: _retirerDoublons,
                child: const Text('Retirer ces messages'),
              ),
              TextButton(
                key: const Key('ajouter-quand-meme'),
                onPressed: () => _confirmer(malgreDoublons: true),
                child: const Text('C’est un nouveau message, l’ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionAjoutes(ContexteServeur c) {
    final ajoutes = _ajoutes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _Titre('Ajoutés à la main (${ajoutes.length})'),
        for (final m in ajoutes.reversed.take(20))
          Padding(
            key: Key('ajoute-${m.id}'),
            padding: const EdgeInsets.only(top: 6),
            child: _enEdition == m.id
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('edition-ajout'),
                          controller: _edition,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('enregistrer-correction'),
                        tooltip: 'Enregistrer',
                        onPressed: () => _enregistrerCorrection(m),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m.sens == SensMessage.envoye ? 'Vous' : m.auteur} : ${m.texte}'
                          '${m.corrige ? ' (corrigé)' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        key: Key('corriger-${m.id}'),
                        tooltip: 'Corriger',
                        onPressed: () => setState(() {
                          _enEdition = m.id;
                          _edition.text = m.texte;
                        }),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        key: Key('supprimer-${m.id}'),
                        tooltip: 'Supprimer',
                        onPressed: () => _supprimerAjout(m),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;

  @override
  Widget build(BuildContext context) => Text(
    texte,
    style: const TextStyle(
      fontSize: 12.5,
      letterSpacing: 0.3,
      fontWeight: FontWeight.w600,
      color: CouleursJarvis.texteSecondaire,
    ),
  );
}
