import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Vrai sur le Web : Maj+Entrée est laissé au navigateur (retour à la
/// ligne natif dans le champ), le raccourci Flutter ne s'applique pas.
const retourLigneParLeNavigateur = true;

bool _installe = false;

/// Sur le Web, Flutter envoie le message dès que le champ HTML reçoit
/// Entrée, Maj enfoncée ou non. Un écouteur en phase de capture arrête la
/// PROPAGATION de Maj+Entrée vers Flutter (sans empêcher l'action par
/// défaut) : le navigateur insère lui-même le retour à la ligne, que
/// Flutter relit comme une frappe ordinaire. Entrée seule, la composition
/// IME en cours et les autres éléments de la page ne sont pas touchés.
void installerRetourLigneWeb() {
  if (_installe) return;
  _installe = true;
  web.window.addEventListener(
    'keydown',
    ((web.KeyboardEvent e) {
      if (e.key != 'Enter' || !e.shiftKey || e.isComposing) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      // Seulement dans un champ multiligne (textarea) de Flutter.
      final cible = e.target as web.Element?;
      if (cible?.tagName != 'TEXTAREA') return;
      e.stopPropagation();
    }).toJS,
    web.AddEventListenerOptions(capture: true),
  );
}
