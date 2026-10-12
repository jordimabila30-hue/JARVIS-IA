import 'source_conversation.dart';

/// Une conversation telle que le menu latéral la présente, quelle que soit
/// sa messagerie : de quoi l'afficher, la trier, la rechercher et l'ouvrir.
/// Les détails propres à chaque plateforme restent dans son fournisseur.
class ApercuConversation {
  const ApercuConversation({
    required this.source,
    required this.id,
    required this.titre,
    required this.apercu,
    required this.derniereActivite,
    this.disponible = true,
    this.ouverte = false,
  });

  final SourceConversation source;

  /// Identifiant stable, unique dans sa source (sert aussi aux épingles).
  final String id;

  /// Nom du contact ou titre de la conversation.
  final String titre;

  /// Début du dernier message.
  final String apercu;

  final DateTime derniereActivite;

  /// Faux si la conversation est listée mais ne peut pas encore être
  /// ouverte (contenu pas encore chargé…).
  final bool disponible;

  /// Vrai pour la conversation affichée dans l'accueil.
  final bool ouverte;

  /// Clé globale : la même conversation n'existe que dans sa source.
  String get cle => '${source.name}:$id';
}
