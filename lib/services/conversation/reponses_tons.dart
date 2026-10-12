import '../../models/message_conversation.dart';
import 'analyse_conversation.dart';

/// Réponses de démonstration, par situation et par ton (prototype local :
/// une IA les générera plus tard à partir de la vraie conversation).
String reponseLocale(AnalyseConversation analyse, TonReponse ton) {
  return switch (analyse.situation) {
    Situation.reproche => switch (ton) {
      TonReponse.naturel =>
        'Tu as raison, j’aurais dû te prévenir. Désolé, je comprends que ça '
            'ait pu te déranger.',
      TonReponse.amical =>
        'Oui je comprends, j’aurais dû te prévenir. Désolé, ce n’était '
            'vraiment pas contre toi.',
      TonReponse.bienveillant =>
        'Tu as raison, j’aurais dû prendre le temps de te prévenir. Je '
            'comprends que ça ait pu te blesser et je suis désolé.',
      TonReponse.direct =>
        'Tu as raison. J’aurais dû te prévenir. Désolé pour ça.',
      TonReponse.poli =>
        'Je comprends votre réaction. J’aurais effectivement dû prévenir plus '
            'tôt et je m’en excuse.',
      TonReponse.professionnel =>
        'Je reconnais que j’aurais dû communiquer cette information plus tôt. '
            'Je m’en excuse et je veillerai à mieux anticiper ce type de '
            'situation.',
    },
    Situation.invitation => switch (ton) {
      TonReponse.naturel => 'Oui, avec plaisir ! Tu penses à quelle heure ?',
      TonReponse.amical =>
        'Grave, ça me ferait trop plaisir ! On se cale une heure ?',
      TonReponse.bienveillant =>
        'C’est gentil de penser à moi, avec plaisir. Dis-moi ce qui '
            't’arrange le mieux.',
      TonReponse.direct => 'Oui, je viens. À quelle heure ?',
      TonReponse.poli =>
        'Merci pour l’invitation, ce sera avec plaisir. À quelle heure '
            'souhaitez-vous que l’on se retrouve ?',
      TonReponse.professionnel =>
        'Merci pour votre proposition. Je suis disponible ; pouvez-vous me '
            'confirmer l’horaire et le lieu ?',
    },
    Situation.remerciement => switch (ton) {
      TonReponse.naturel => 'Avec plaisir, c’était normal !',
      TonReponse.amical => 'Mais de rien, ça m’a fait plaisir !',
      TonReponse.bienveillant =>
        'Avec plaisir, je suis content que ça ait pu t’aider.',
      TonReponse.direct => 'De rien.',
      TonReponse.poli => 'Je vous en prie, c’était avec plaisir.',
      TonReponse.professionnel =>
        'Je vous en prie. N’hésitez pas si vous avez besoin d’autre chose.',
    },
    Situation.question => switch (ton) {
      TonReponse.naturel =>
        'Bonne question ! Je regarde ça et je te redis rapidement.',
      TonReponse.amical =>
        'Ah bonne question ! Laisse-moi vérifier et je te tiens au courant.',
      TonReponse.bienveillant =>
        'Merci de me demander. Je prends le temps de vérifier pour te '
            'répondre correctement.',
      TonReponse.direct => 'Je vérifie et je te réponds.',
      TonReponse.poli =>
        'Merci pour votre question. Je me renseigne et je reviens vers vous '
            'au plus vite.',
      TonReponse.professionnel =>
        'Merci pour votre question. Je vérifie les éléments et je vous '
            'apporte une réponse précise dans les meilleurs délais.',
    },
    Situation.salutation => switch (ton) {
      TonReponse.naturel => 'Salut ! Ça va bien, et toi ?',
      TonReponse.amical => 'Coucou ! Ça va super, et toi, quoi de neuf ?',
      TonReponse.bienveillant =>
        'Salut, ça me fait plaisir d’avoir de tes nouvelles. Ça va bien, et '
            'toi ?',
      TonReponse.direct => 'Salut, ça va. Et toi ?',
      TonReponse.poli => 'Bonjour, je vais bien, merci. Et vous ?',
      TonReponse.professionnel =>
        'Bonjour, merci pour votre message. Je vais bien ; que puis-je faire '
            'pour vous ?',
    },
    Situation.neutre => switch (ton) {
      TonReponse.naturel => 'Ça marche, merci pour ton message !',
      TonReponse.amical => 'Top, merci ! Je te redis vite.',
      TonReponse.bienveillant =>
        'Merci pour ton message, je prends bien note et je reviens vers toi.',
      TonReponse.direct => 'Bien reçu.',
      TonReponse.poli => 'Merci pour votre message, j’en prends bonne note.',
      TonReponse.professionnel =>
        'Merci pour votre message. J’en prends note et je reviens vers vous '
            'rapidement.',
    },
  };
}
