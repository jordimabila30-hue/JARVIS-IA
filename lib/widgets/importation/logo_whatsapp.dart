import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/conversations/source_conversation.dart';

/// Logo officiel WhatsApp (SVG local, voir `assets/logos/SOURCES.md`).
class LogoWhatsApp extends StatelessWidget {
  const LogoWhatsApp({super.key, this.taille = 24});

  final double taille;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: taille,
    child: SvgPicture.asset(
      SourceConversation.whatsapp.logo!,
      fit: BoxFit.contain,
      semanticsLabel: 'WhatsApp',
    ),
  );
}

/// Logo d'une messagerie (SVG local) ; sans logo : une icône d'enveloppe.
class LogoSource extends StatelessWidget {
  const LogoSource(this.source, {super.key, this.taille = 24});

  final SourceConversation source;
  final double taille;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: taille,
    child: switch (source.logo) {
      final logo? => SvgPicture.asset(
        logo,
        fit: BoxFit.contain,
        semanticsLabel: source.libelle,
      ),
      null => Icon(Icons.mail_outline_rounded, size: taille),
    },
  );
}
