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
      SourceConversation.whatsapp.logo,
      fit: BoxFit.contain,
      semanticsLabel: 'WhatsApp',
    ),
  );
}
