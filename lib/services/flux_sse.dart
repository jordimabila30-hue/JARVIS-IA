import 'dart:async';
import 'dart:convert';

/// Un événement d'un flux `text/event-stream` (Server-Sent Events).
class EvenementSse {
  const EvenementSse(this.type, this.donnees);

  /// Champ `event:` (« message » par défaut, comme dans la norme).
  final String type;

  /// Lignes `data:` réunies (séparées par un retour à la ligne).
  final String donnees;
}

/// Découpe des octets reçus en événements SSE.
///
/// Les octets arrivent par paquets quelconques : un caractère accentué ou
/// une ligne peuvent être coupés entre deux paquets. Le décodage UTF-8 et
/// le découpage en lignes se font donc en flux ([utf8.decoder],
/// [LineSplitter]), et un événement n'est émis qu'à la ligne vide qui le
/// termine. Un événement inachevé à la fin du flux est ignoré (norme SSE) :
/// jamais de réponse tronquée prise pour complète.
Stream<EvenementSse> decoderSse(Stream<List<int>> octets) async* {
  var type = '';
  final donnees = <String>[];
  await for (final ligne
      in octets.transform(utf8.decoder).transform(const LineSplitter())) {
    if (ligne.isEmpty) {
      if (donnees.isNotEmpty) {
        yield EvenementSse(type.isEmpty ? 'message' : type, donnees.join('\n'));
      }
      type = '';
      donnees.clear();
      continue;
    }
    // Commentaire (« : ping ») : ignoré.
    if (ligne.startsWith(':')) continue;
    final i = ligne.indexOf(':');
    final champ = i < 0 ? ligne : ligne.substring(0, i);
    var valeur = i < 0 ? '' : ligne.substring(i + 1);
    if (valeur.startsWith(' ')) valeur = valeur.substring(1);
    switch (champ) {
      case 'event':
        type = valeur;
      case 'data':
        donnees.add(valeur);
    }
  }
}
