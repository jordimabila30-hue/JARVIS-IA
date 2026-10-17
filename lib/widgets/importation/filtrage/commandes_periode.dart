import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/importation/filtre_whatsapp.dart';
import '../../../services/importation/selection_whatsapp.dart';
import '../../../theme/theme_jarvis.dart';
import '../../../utils/local_date_time.dart';
import '../lecture_whatsapp_widgets.dart';
import 'calendrier_whatsapp.dart';
import 'selecteur_mode_filtrage.dart';

/// Commandes du mode « Par période » : capsules (défilement horizontal),
/// puis le nombre de « Derniers messages » ou la période personnalisée.
class CommandesPeriode extends StatelessWidget {
  const CommandesPeriode({super.key, required this.selection});

  final SelectionWhatsApp selection;

  static String tous(int n) => 'Tous (${nombreEnFrancais(n)})';

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final capsule = s.capsule;
    final filtre = s.filtre;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CapsulePeriode.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = CapsulePeriode.values[i];
              return Center(
                child: CapsuleChoix(
                  libelle: c.libelle,
                  icone: c == CapsulePeriode.personnalise
                      ? Icons.event_note_outlined
                      : null,
                  actif: c == capsule,
                  surAppui: () => s.choisirCapsule(c),
                ),
              );
            },
          ),
        ),
        if (capsule == CapsulePeriode.derniers) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in s.nombresDerniers)
                CapsuleChoix(
                  souple: true,
                  libelle: n >= s.index.nombre && n > 0
                      ? tous(n)
                      : nombreEnFrancais(n),
                  actif: filtre is FiltreDerniers && filtre.nombre == n,
                  surAppui: () => s.choisirDerniers(n),
                ),
            ],
          ),
        ],
        if (capsule == CapsulePeriode.personnalise) ...[
          const SizedBox(height: 10),
          PeriodePersonnalisee(selection: s),
        ],
      ],
    );
  }
}

/// Début et fin (date, heure, minute ; bornes comprises), le calendrier,
/// et le nombre de messages de la période.
class PeriodePersonnalisee extends StatelessWidget {
  const PeriodePersonnalisee({super.key, required this.selection});

  static const debut = 'Début';
  static const fin = 'Fin';
  static const aucunMessageDate = 'Aucun message daté dans cette conversation.';
  static const toucherJour =
      'Touchez un jour pour le choisir, puis un autre pour étendre la période.';
  static const toucherSecond = 'Touchez un autre jour pour étendre la période.';

  final SelectionWhatsApp selection;

  static String resume(SelectionWhatsApp s) {
    final p = s.periode;
    if (p == null || !p.valide) return '';
    final n = s.index.nombreEntre(p.debut, p.finExclue);
    final messages = '${nombreEnFrancais(n)} message${n > 1 ? 's' : ''}';
    if (p.estJourEntier) {
      return '$messages le ${jourDeLaSemaine(p.debut)} ${jourEnFrancais(p.debut)}';
    }
    return '$messages dans la période';
  }

  @override
  Widget build(BuildContext context) {
    final s = selection;
    final p = s.periode;
    if (p == null) {
      return const Text(
        aucunMessageDate,
        style: TextStyle(fontSize: 13, color: CouleursJarvis.texteSecondaire),
      );
    }
    final erreur = s.erreurPeriode;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: CouleursJarvis.coque.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursJarvis.trait.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: CouleursJarvis.texte.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Borne(
            libelle: debut,
            moment: p.debut,
            cible: s.cible == BornePeriode.debut,
            surDate: () => s.ciblerDate(
              s.cible == BornePeriode.debut ? null : BornePeriode.debut,
            ),
            surHeure: () async {
              final h = await choisirHeure(context, p.debut, debut);
              if (h == null) return;
              s.modifierDebut(_avecHeure(s.periode?.debut ?? p.debut, h));
            },
          ),
          const SizedBox(height: 6),
          _Borne(
            libelle: fin,
            moment: p.fin,
            cible: s.cible == BornePeriode.fin,
            surDate: () => s.ciblerDate(
              s.cible == BornePeriode.fin ? null : BornePeriode.fin,
            ),
            surHeure: () async {
              final h = await choisirHeure(context, p.fin, fin);
              if (h == null) return;
              s.modifierFin(_avecHeure(s.periode?.fin ?? p.fin, h));
            },
          ),
          if (erreur != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: Color(0xFFB3261E),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    erreur,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: CouleursJarvis.trait.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 4),
          CalendrierWhatsApp(selection: s),
          const SizedBox(height: 6),
          Text(
            s.cible != null
                ? 'Touchez le jour de ${s.cible == BornePeriode.debut ? 'début' : 'fin'}.'
                : s.calendrierAttendFin
                ? toucherSecond
                : toucherJour,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
          if (resume(s) case final r when r.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              r,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: CouleursJarvis.signal,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static DateTime _avecHeure(DateTime jour, TimeOfDay h) =>
      DateTime(jour.year, jour.month, jour.day, h.hour, h.minute);
}

/// « Début  [8 octobre 2026] [14:30] ».
class _Borne extends StatelessWidget {
  const _Borne({
    required this.libelle,
    required this.moment,
    required this.cible,
    required this.surDate,
    required this.surHeure,
  });

  final String libelle;
  final DateTime moment;
  final bool cible;
  final VoidCallback surDate;
  final VoidCallback surHeure;

  @override
  Widget build(BuildContext context) {
    // Libellé, puis date et heure : sur une ligne si la place suffit,
    // sinon les unes sous les autres (petit écran, grande police).
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44),
          child: Text(
            libelle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CouleursJarvis.texteSecondaire,
            ),
          ),
        ),
        CapsuleChoix(
          libelle: jourEnFrancais(moment),
          icone: Icons.calendar_today_outlined,
          actif: cible,
          surAppui: surDate,
          souple: true,
        ),
        CapsuleChoix(
          libelle: heureCourte(moment),
          icone: Icons.schedule_rounded,
          actif: false,
          surAppui: surHeure,
          souple: true,
        ),
      ],
    );
  }
}

/// Heure et minute, avec le sélecteur de la plateforme : roues sur
/// téléphone, saisie au clavier sur ordinateur et dans le navigateur.
Future<TimeOfDay?> choisirHeure(
  BuildContext context,
  DateTime initial,
  String titre,
) {
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final depart = TimeOfDay(hour: initial.hour, minute: initial.minute);
  if (mobile) {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: CouleursJarvis.coque,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RouesHeure(titre: titre, initial: depart),
    );
  }
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _SaisieHeure(titre: titre, initial: depart),
  );
}

String _deux(int v) => v.toString().padLeft(2, '0');

class _RouesHeure extends StatefulWidget {
  const _RouesHeure({required this.titre, required this.initial});

  final String titre;
  final TimeOfDay initial;

  @override
  State<_RouesHeure> createState() => _RouesHeureState();
}

class _RouesHeureState extends State<_RouesHeure> {
  late int _heure = widget.initial.hour;
  late int _minute = widget.initial.minute;

  Widget _roue(int nombre, int initial, ValueChanged<int> surChoix) {
    return Expanded(
      child: CupertinoPicker(
        itemExtent: 38,
        scrollController: FixedExtentScrollController(initialItem: initial),
        selectionOverlay: Container(
          decoration: BoxDecoration(
            color: CouleursJarvis.lavande.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onSelectedItemChanged: surChoix,
        children: [
          for (var i = 0; i < nombre; i++)
            Center(
              child: Text(
                _deux(i),
                style: const TextStyle(
                  fontSize: 22,
                  color: CouleursJarvis.texte,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Heure de ${widget.titre.toLowerCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: policeAffichage,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CouleursJarvis.texte,
              ),
            ),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  _roue(24, _heure, (v) => _heure = v),
                  const Text(
                    ':',
                    style: TextStyle(fontSize: 22, color: CouleursJarvis.texte),
                  ),
                  _roue(60, _minute, (v) => _minute = v),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(TimeOfDay(hour: _heure, minute: _minute)),
              style: FilledButton.styleFrom(
                backgroundColor: CouleursJarvis.signal,
                foregroundColor: CouleursJarvis.ivoire,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaisieHeure extends StatefulWidget {
  const _SaisieHeure({required this.titre, required this.initial});

  final String titre;
  final TimeOfDay initial;

  @override
  State<_SaisieHeure> createState() => _SaisieHeureState();
}

class _SaisieHeureState extends State<_SaisieHeure> {
  late final _heure = TextEditingController(text: _deux(widget.initial.hour));
  late final _minute = TextEditingController(
    text: _deux(widget.initial.minute),
  );
  String? _erreur;

  @override
  void dispose() {
    _heure.dispose();
    _minute.dispose();
    super.dispose();
  }

  void _valider() {
    final h = int.tryParse(_heure.text), m = int.tryParse(_minute.text);
    if (h == null || m == null || h > 23 || m > 59) {
      setState(() => _erreur = 'Heure de 00 à 23, minute de 00 à 59.');
      return;
    }
    Navigator.of(context).pop(TimeOfDay(hour: h, minute: m));
  }

  Widget _champ(TextEditingController c, String libelle, {bool focus = false}) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: c,
        autofocus: focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        onSubmitted: (_) => _valider(),
        style: const TextStyle(
          fontSize: 22,
          color: CouleursJarvis.texte,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          labelText: libelle,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CouleursJarvis.coque,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Heure de ${widget.titre.toLowerCase()}',
        style: const TextStyle(
          fontFamily: policeAffichage,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: CouleursJarvis.texte,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _champ(_heure, 'Heure', focus: true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':', style: TextStyle(fontSize: 22)),
              ),
              _champ(_minute, 'Minute'),
            ],
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Text(
              _erreur!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB3261E)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          style: FilledButton.styleFrom(
            backgroundColor: CouleursJarvis.signal,
            foregroundColor: CouleursJarvis.ivoire,
          ),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
