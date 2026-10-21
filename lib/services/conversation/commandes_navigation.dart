import '../applications_externes.dart';
import 'detecteur_intention.dart';

/// Commandes de navigation que JARVIS exécute LOCALEMENT, sans appel à
/// l'IA (écrit et vocal). Seulement des actions déjà présentes dans
/// l'application, jamais irréversibles : « Nouvelle conversation » met la
/// conversation de côté (rien n'est effacé), ouvrir une application ne
/// donne accès à aucun message.
enum CommandeNavigation {
  nouvelleConversation('Nouvelle conversation.'),
  afficherConversations('Voici vos conversations.'),
  ouvrirParametres('J’ouvre les paramètres.'),
  ouvrirOutils('J’ouvre les outils.'),
  ouvrirAgenda('J’ouvre l’Agenda.'),
  ouvrirApprendre('J’ouvre Apprendre.'),
  ouvrirWhatsApp('J’ouvre WhatsApp.'),
  ouvrirInstagram('J’ouvre Instagram.'),
  ouvrirMessenger('J’ouvre Messenger.'),
  ouvrirMail('J’ouvre votre messagerie.'),
  retourChatEcrit('Retour au chat écrit.'),
  arreterParole('D’accord, je me tais.');

  const CommandeNavigation(this.confirmation);

  /// Courte confirmation (dite en vocal, affichée en écrit si besoin).
  final String confirmation;

  /// Application externe ouverte par la commande (null : écran de JARVIS).
  ApplicationExterne? get application => switch (this) {
    ouvrirWhatsApp => ApplicationExterne.whatsapp,
    ouvrirInstagram => ApplicationExterne.instagram,
    ouvrirMessenger => ApplicationExterne.messenger,
    ouvrirMail => ApplicationExterne.mail,
    _ => null,
  };
}

/// Détection STRICTE : toute la demande doit être la commande (avec, au
/// plus, une formule de politesse : « JARVIS », « s'il te plaît », « tu
/// peux »…). « Comment ouvrir Instagram sur ordinateur ? » ou « parle-moi
/// des paramètres » restent des questions pour JARVIS : aucune activation
/// accidentelle.
class CommandesNavigation {
  const CommandesNavigation._();

  static const _politesse = [
    'jarvis',
    'hey jarvis',
    'ok jarvis',
    's il te plait',
    's il vous plait',
    'stp',
    'svp',
    'tu peux',
    'peux tu',
    'pourrais tu',
    'tu pourrais',
    'est ce que tu peux',
    'vous pouvez',
    'pouvez vous',
    'merci',
    'je veux',
    'je voudrais',
    'j aimerais',
  ];

  static const _ouvrir = [
    'ouvre',
    'ouvrir',
    'ouvres',
    'lance',
    'lancer',
    'affiche',
    'afficher',
    'montre',
    'montre moi',
    'va dans',
    'va sur',
    'aller dans',
    'aller sur',
    'ouvre moi',
    'demarre',
  ];

  static const _articles = [
    '',
    'le ',
    'la ',
    'les ',
    'l ',
    'mes ',
    'mon ',
    'ma ',
  ];

  static final Map<String, CommandeNavigation> _phrases = _construire();

  static Map<String, CommandeNavigation> _construire() {
    final m = <String, CommandeNavigation>{};
    void ouvrir(List<String> cibles, CommandeNavigation c) {
      for (final v in _ouvrir) {
        for (final a in _articles) {
          for (final cible in cibles) {
            m['$v $a$cible'] = c;
          }
        }
      }
    }

    ouvrir(['parametres', 'reglages'], CommandeNavigation.ouvrirParametres);
    ouvrir(['outils'], CommandeNavigation.ouvrirOutils);
    ouvrir(['agenda', 'calendrier'], CommandeNavigation.ouvrirAgenda);
    ouvrir([
      'apprendre',
      'apprentissage',
      'kelasi',
      'module apprendre',
    ], CommandeNavigation.ouvrirApprendre);
    ouvrir([
      'conversations',
      'historique',
      'menu',
      'discussions',
    ], CommandeNavigation.afficherConversations);
    ouvrir(['whatsapp'], CommandeNavigation.ouvrirWhatsApp);
    ouvrir(['instagram', 'insta'], CommandeNavigation.ouvrirInstagram);
    ouvrir(['messenger'], CommandeNavigation.ouvrirMessenger);
    ouvrir([
      'mail',
      'mails',
      'e mail',
      'e mails',
      'email',
      'messagerie',
      'boite mail',
      'gmail',
    ], CommandeNavigation.ouvrirMail);
    for (final p in [
      'nouvelle conversation',
      'nouvelle discussion',
      'nouveau chat',
      'commence une nouvelle conversation',
      'ouvre une nouvelle conversation',
      'demarre une nouvelle conversation',
      'on recommence a zero',
    ]) {
      m[p] = CommandeNavigation.nouvelleConversation;
    }
    for (final p in [
      'retour au chat',
      'retour au chat ecrit',
      'reviens au chat',
      'reviens au chat ecrit',
      'revenir au chat ecrit',
      'retourne au chat ecrit',
      'passe en mode ecrit',
      'mode ecrit',
    ]) {
      m[p] = CommandeNavigation.retourChatEcrit;
    }
    for (final p in [
      'arrete de parler',
      'arrete la lecture',
      'arrete la parole',
      'tais toi',
      'silence',
      'stop lecture',
    ]) {
      m[p] = CommandeNavigation.arreterParole;
    }
    return m;
  }

  /// Commande reconnue, ou null (la demande part normalement).
  static CommandeNavigation? detecter(String demande) {
    var t = ' ${DetecteurIntention.normaliser(demande)} ';
    // Formules de politesse en tête ou en fin, retirées une à une.
    var change = true;
    while (change) {
      change = false;
      for (final p in _politesse) {
        if (t.startsWith(' $p ')) {
          t = t.substring(p.length + 1);
          change = true;
        }
        if (t.endsWith(' $p ')) {
          t = t.substring(0, t.length - p.length - 1);
          change = true;
        }
      }
    }
    return _phrases[t.trim()];
  }
}
