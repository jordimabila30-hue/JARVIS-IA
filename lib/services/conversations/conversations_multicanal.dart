import 'package:flutter/foundation.dart';

import '../../models/conversations/apercu_conversation.dart';
import '../../models/conversations/source_conversation.dart';
import 'epingles_conversations.dart';
import 'fournisseur_conversations.dart';

/// État des conversations du menu latéral, indépendant de l'affichage :
/// source choisie, recherche, listes triées (épinglées d'abord), position
/// de défilement de chaque liste.
///
/// Vit avec l'accueil : fermer puis rouvrir le menu retrouve la même
/// source, la même recherche et les mêmes positions. Choisir une source ne
/// touche jamais à la conversation ouverte dans l'accueil.
class ConversationsMulticanal extends ChangeNotifier {
  ConversationsMulticanal({
    required List<FournisseurConversations> fournisseurs,
    required this.epingles,
  }) : _fournisseurs = {for (final f in fournisseurs) f.source: f} {
    for (final f in fournisseurs) {
      f.addListener(notifyListeners);
    }
    epingles.addListener(notifyListeners);
  }

  final Map<SourceConversation, FournisseurConversations> _fournisseurs;
  final EpinglesConversations epingles;

  /// Sources du sélecteur, dans l'ordre de [SourceConversation].
  List<SourceConversation> get sources => [
    for (final s in SourceConversation.values)
      if (_fournisseurs.containsKey(s)) s,
  ];

  /// Source affichée (seul le sélecteur la change).
  final selection = ValueNotifier(SourceConversation.jarvis);

  /// Texte de recherche, appliqué à la source affichée seulement.
  final recherche = ValueNotifier('');

  final _positions = <SourceConversation, double>{};

  void choisir(SourceConversation source) {
    if (source == selection.value || !_fournisseurs.containsKey(source)) {
      return;
    }
    // La recherche porte sur une messagerie : elle repart de zéro.
    recherche.value = '';
    selection.value = source;
  }

  /// Position de défilement mémorisée de la liste d'une source.
  double position(SourceConversation source) => _positions[source] ?? 0;

  void memoriserPosition(SourceConversation source, double position) =>
      _positions[source] = position;

  /// Conversations de [source] : épinglées d'abord (dernière épinglée en
  /// tête), puis les autres de la plus récente à la plus ancienne,
  /// filtrées par [requete] (titre ou aperçu, sans tenir compte de la
  /// casse ni des accents).
  List<ApercuConversation> liste(
    SourceConversation source, {
    String requete = '',
  }) {
    final toutes = _fournisseurs[source]?.conversations ?? const [];
    final q = normaliser(requete.trim());
    final filtrees = [
      for (final c in toutes)
        if (q.isEmpty ||
            normaliser(c.titre).contains(q) ||
            normaliser(c.apercu).contains(q))
          c,
    ];
    filtrees.sort((a, b) {
      final ra = epingles.rang(a), rb = epingles.rang(b);
      if ((ra >= 0) != (rb >= 0)) return ra >= 0 ? -1 : 1;
      if (ra >= 0) return ra.compareTo(rb);
      final d = b.derniereActivite.compareTo(a.derniereActivite);
      return d != 0 ? d : a.id.compareTo(b.id);
    });
    return filtrees;
  }

  /// Ouvre une conversation dans l'accueil (via sa messagerie).
  bool ouvrir(ApercuConversation c) =>
      c.disponible && (_fournisseurs[c.source]?.ouvrir(c.id) ?? false);

  /// Supprime une conversation des données locales de sa messagerie, puis
  /// son épingle. Faux si rien n'a été supprimé.
  bool supprimer(ApercuConversation c) {
    final supprimee = _fournisseurs[c.source]?.supprimer(c.id) ?? false;
    if (supprimee) epingles.retirer(c);
    return supprimee;
  }

  /// Minuscules sans accents, pour la recherche.
  static String normaliser(String texte) {
    final s = texte.toLowerCase();
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      b.write(_sansAccent[ch] ?? ch);
    }
    return b.toString();
  }

  static const _sansAccent = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', //
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', //
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', //
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', //
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };

  /// Les fournisseurs et les épingles lui appartiennent : ils sont libérés
  /// avec lui.
  @override
  void dispose() {
    for (final f in _fournisseurs.values) {
      f.removeListener(notifyListeners);
      if (f is ChangeNotifier) (f as ChangeNotifier).dispose();
    }
    epingles.dispose();
    selection.dispose();
    recherche.dispose();
    super.dispose();
  }
}
