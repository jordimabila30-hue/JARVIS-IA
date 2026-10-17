import 'package:ia_jarvis/models/importation/conversation_whatsapp.dart';

/// Conversations WhatsApp construites directement (sans fichier) pour les
/// tests du filtrage.

/// Message de test : [date] null pour une date illisible.
MessageWhatsApp msg(
  int ordre,
  DateTime? date, {
  String auteur = 'Ada',
  String? texte,
  TypeMessageWhatsApp type = TypeMessageWhatsApp.texte,
}) => MessageWhatsApp(
  ordre: ordre,
  auteur: type == TypeMessageWhatsApp.systeme ? null : auteur,
  date: date,
  dateBrute: date?.toIso8601String() ?? '32/13/2026 25:61',
  texte: texte ?? 'message $ordre',
  type: type,
  typeMedia: type == TypeMessageWhatsApp.media ? TypeMediaWhatsApp.image : null,
);

ConversationWhatsApp conv(List<MessageWhatsApp> messages) =>
    ConversationWhatsApp(
      titre: 'Test',
      messages: messages,
      participants: const [
        ParticipantWhatsApp(nom: 'Ada', messages: 1),
        ParticipantWhatsApp(nom: 'Alan', messages: 1),
      ],
      ordreDate: OrdreDate.jourMoisAnnee,
      dateIncertaine: false,
      lignesNonRattachees: const [],
      nombreLignesNonRattachees: 0,
      nomFichier: 'chat.txt',
    );

/// Une conversation régulière : [n] messages, un toutes les [pas].
ConversationWhatsApp reguliere(int n, DateTime debut, Duration pas) => conv([
  for (var i = 0; i < n; i++)
    msg(i, debut.add(pas * i), auteur: i.isEven ? 'Ada' : 'Alan'),
]);
