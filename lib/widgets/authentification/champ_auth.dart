import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_jarvis.dart';

/// Champ de formulaire d'authentification : libellé au-dessus, champ blanc
/// à contour discret, erreur dessous. En mode [motDePasse], un bouton
/// affiche ou masque le contenu (seul ce champ se reconstruit).
class ChampAuth extends StatefulWidget {
  const ChampAuth({
    super.key,
    required this.libelle,
    required this.controleur,
    this.focus,
    this.indice,
    this.validateur,
    this.motDePasse = false,
    this.clavier = TextInputType.text,
    this.action = TextInputAction.next,
    this.surValidation,
    this.autofill,
    this.majuscules = TextCapitalization.none,
  });

  final String libelle;
  final TextEditingController controleur;
  final FocusNode? focus;
  final String? indice;
  final FormFieldValidator<String>? validateur;
  final bool motDePasse;
  final TextInputType clavier;
  final TextInputAction action;
  final ValueChanged<String>? surValidation;
  final Iterable<String>? autofill;
  final TextCapitalization majuscules;

  @override
  State<ChampAuth> createState() => _ChampAuthState();
}

class _ChampAuthState extends State<ChampAuth> {
  bool _masque = true;
  // Hors de l'ordre de tabulation : Tab passe directement au champ suivant.
  final _focusOeil = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusOeil.dispose();
    super.dispose();
  }

  static OutlineInputBorder _bord(Color couleur, [double largeur = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: couleur, width: largeur),
      );

  @override
  Widget build(BuildContext context) {
    final mdp = widget.motDePasse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            widget.libelle,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
              color: CouleursJarvis.texte,
            ),
          ),
        ),
        TextFormField(
          controller: widget.controleur,
          focusNode: widget.focus,
          validator: widget.validateur,
          obscureText: mdp && _masque,
          enableSuggestions: !mdp,
          autocorrect: false,
          keyboardType: mdp ? TextInputType.visiblePassword : widget.clavier,
          textInputAction: widget.action,
          textCapitalization: widget.majuscules,
          onFieldSubmitted: widget.surValidation,
          autofillHints: widget.autofill,
          // Pas de retour à la ligne dans un identifiant.
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp('\n'))],
          style: const TextStyle(fontSize: 15.5, color: CouleursJarvis.texte),
          cursorColor: CouleursJarvis.signal,
          decoration: InputDecoration(
            hintText: widget.indice,
            hintStyle: TextStyle(
              fontSize: 15.5,
              color: CouleursJarvis.texteSecondaire.withValues(alpha: 0.7),
            ),
            filled: true,
            fillColor: CouleursJarvis.coque,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            errorMaxLines: 2,
            errorStyle: const TextStyle(fontSize: 12.5, height: 1.3),
            border: _bord(CouleursJarvis.trait),
            enabledBorder: _bord(CouleursJarvis.trait),
            focusedBorder: _bord(CouleursJarvis.signal, 1.4),
            errorBorder: _bord(const Color(0xFFC2525C)),
            focusedErrorBorder: _bord(const Color(0xFFC2525C), 1.4),
            suffixIcon: mdp
                ? IconButton(
                    focusNode: _focusOeil,
                    tooltip: _masque
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                    onPressed: () => setState(() => _masque = !_masque),
                    icon: Icon(
                      _masque
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: CouleursJarvis.texteSecondaire,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
