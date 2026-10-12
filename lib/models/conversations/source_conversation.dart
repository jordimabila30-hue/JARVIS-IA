/// Messagerie d'où vient une conversation, dans l'ordre du sélecteur du
/// menu latéral.
///
/// Ajouter une source (SMS…) : une valeur ici, son logo dans
/// `assets/logos/`, et son fournisseur de conversations ; le panneau n'a
/// rien d'autre à connaître.
enum SourceConversation {
  jarvis('JARVIS', 'assets/logos/jarvis.png'),
  whatsapp('WhatsApp', 'assets/logos/whatsapp.svg'),
  gmail('Gmail', 'assets/logos/gmail.svg'),
  messenger('Messenger', 'assets/logos/messenger.svg'),
  instagram('Instagram', 'assets/logos/instagram.svg');

  const SourceConversation(this.libelle, this.logo);

  /// Nom affiché sous le logo.
  final String libelle;

  /// Logo local (SVG officiel, ou image du logo JARVIS).
  final String logo;
}
