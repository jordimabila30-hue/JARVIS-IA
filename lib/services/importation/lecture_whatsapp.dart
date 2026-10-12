import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../models/importation/conversation_whatsapp.dart';
import '../../models/importation/export_whatsapp.dart';
import 'analyseur_whatsapp.dart';
import 'export_local.dart';
import 'selection_export_whatsapp.dart';

/// Raisons d'un échec de lecture (messages pour l'utilisateur).
enum ErreurLecture {
  fichierVide('Ce fichier ne contient aucun message.'),
  formatNonReconnu(
    'Aucun message WhatsApp n’a été reconnu dans ce fichier. Exportez la '
    'discussion depuis WhatsApp (Menu › Plus › Exporter la discussion).',
  ),
  aucuneConversation(
    'Cette archive ne contient pas de discussion WhatsApp (aucun fichier '
    'texte).',
  ),
  archiveEndommagee(
    'Cette archive est endommagée ou incomplète. Exportez à nouveau la '
    'discussion.',
  ),
  archiveSuspecte(
    'Cette archive a été refusée : son contenu se décompresse bien au-delà '
    'de ce qu’elle annonce.',
  ),
  tropVolumineux('Cette discussion est trop volumineuse pour être lue.'),
  accesImpossible(
    'Le fichier n’est plus accessible. Choisissez-le ou partagez-le à '
    'nouveau.',
  );

  const ErreurLecture(this.message);
  final String message;
}

/// Étape en cours (texte court affiché sous l'indicateur).
enum EtapeLecture {
  copie('Ouverture du fichier'),
  archive('Ouverture de l’archive'),
  messages('Préparation des messages');

  const EtapeLecture(this.libelle);
  final String libelle;
}

/// Progression : [fraction] entre 0 et 1 quand elle est mesurable
/// (octets lus), null sinon (indicateur indéterminé).
typedef SurProgression = void Function(EtapeLecture etape, double? fraction);

/// Demande d'arrêt, vérifiée entre deux morceaux.
class Annulation {
  bool _annulee = false;
  bool get annulee => _annulee;
  void annuler() => _annulee = true;
}

sealed class ResultatLecture {
  const ResultatLecture();
}

final class LectureReussie extends ResultatLecture {
  const LectureReussie(this.conversation);
  final ConversationWhatsApp conversation;
}

/// Plusieurs fichiers texte plausibles dans l'archive : l'utilisateur
/// choisit (rien n'est choisi au hasard).
final class ChoixFichierRequis extends ResultatLecture {
  const ChoixFichierRequis(this.candidats);
  final List<EntreeArchive> candidats;
}

final class LectureEchouee extends ResultatLecture {
  const LectureEchouee(this.erreur);
  final ErreurLecture erreur;
}

final class LectureAnnulee extends ResultatLecture {
  const LectureAnnulee();
}

class _Arret implements Exception {
  const _Arret();
}

/// Lecture réelle d'un export : copie locale privée, puis TXT lu ligne à
/// ligne, ou ZIP dont seul le fichier de discussion est décompressé.
/// Aucune limite sur le nombre de messages ; limites seulement contre les
/// fichiers démesurés ou malveillants.
class LecteurWhatsApp {
  LecteurWhatsApp(this.export, {Future<ExportLocal> Function()? creerLocal})
    : _creerLocal = creerLocal ?? ExportLocal.creer;

  final ExportWhatsAppChoisi export;
  final Future<ExportLocal> Function() _creerLocal;
  ExportLocal? _local;

  /// Taille maximale du texte d'une discussion (décompressé).
  static const limiteTexte = 512 * 1024 * 1024;

  /// Au-delà d'autant d'entrées, l'archive n'est pas un export WhatsApp.
  static const maxEntrees = 200000;

  /// Rend la main à l'interface toutes les [_paquet] lignes.
  static const _paquet = 2000;

  Future<ResultatLecture> lire({
    SurProgression? progression,
    Annulation? annulation,
    String? entreeChoisie,
  }) async {
    final annule = annulation ?? Annulation();
    void verifier() {
      if (annule.annulee) throw const _Arret();
    }

    try {
      final local = _local ?? await _copier(progression, verifier);
      _local = local;
      final fichier = export.fichier;
      final ConversationWhatsApp conversation;
      if (fichier.format == FormatExportWhatsApp.txt) {
        conversation = await _analyser(
          local.lire(),
          local.taille,
          nomFichier: fichier.nom,
          progression: progression,
          verifier: verifier,
        );
      } else {
        progression?.call(EtapeLecture.archive, null);
        final entrees = await local.listerArchive();
        verifier();
        // Aucune entrée : index illisible (archive tronquée).
        if (entrees.isEmpty || entrees.length > maxEntrees) {
          return const LectureEchouee(ErreurLecture.archiveEndommagee);
        }
        final candidats = entrees.where(estCandidat).toList();
        final EntreeArchive entree;
        if (entreeChoisie != null) {
          entree = candidats.firstWhere((e) => e.nom == entreeChoisie);
        } else if (candidats.isEmpty) {
          return const LectureEchouee(ErreurLecture.aucuneConversation);
        } else if (candidats.length == 1) {
          entree = candidats.single;
        } else {
          final probables = candidats.where(estNomDeDiscussion).toList();
          if (probables.length != 1) return ChoixFichierRequis(candidats);
          entree = probables.single;
        }
        if (_semblableABombe(entree)) {
          return const LectureEchouee(ErreurLecture.archiveSuspecte);
        }
        final texte = await local.extraire(entree.nom, limite: limiteTexte);
        verifier();
        conversation = await _analyser(
          _tranches(texte),
          texte.length,
          nomFichier: entree.nom,
          nomExport: fichier.nom,
          progression: progression,
          verifier: verifier,
        );
      }
      if (conversation.messages.isEmpty) {
        return LectureEchouee(
          conversation.nombreLignesNonRattachees == 0
              ? ErreurLecture.fichierVide
              : ErreurLecture.formatNonReconnu,
        );
      }
      // La conversation est reconstruite : la copie de l'export ne sert
      // plus (rien n'est gardé au-delà du nécessaire).
      await liberer();
      return LectureReussie(conversation);
    } on _Arret {
      return const LectureAnnulee();
    } on _Erreur catch (e) {
      return LectureEchouee(e.erreur);
    } on ArchiveDemesuree {
      return const LectureEchouee(ErreurLecture.archiveSuspecte);
    } catch (_) {
      // Archive illisible (signature, index, données corrompues…).
      return LectureEchouee(
        export.fichier.format == FormatExportWhatsApp.zip
            ? ErreurLecture.archiveEndommagee
            : ErreurLecture.accesImpossible,
      );
    }
  }

  /// Efface la copie locale (page quittée, lecture terminée).
  Future<void> liberer() async {
    final local = _local;
    _local = null;
    await local?.supprimer();
  }

  /// Fichier texte plausible pour une discussion : extension .txt, chemin
  /// sûr, pas un fichier système (macOS) ni vide.
  static bool estCandidat(EntreeArchive e) {
    final nom = e.nom.replaceAll('\\', '/');
    if (!nom.toLowerCase().endsWith('.txt') || e.taille <= 0) return false;
    if (nom.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(nom)) {
      return false;
    }
    final parties = nom.split('/');
    if (parties.contains('..')) return false;
    if (parties.any((p) => p == '__MACOSX' || p.startsWith('._'))) {
      return false;
    }
    return true;
  }

  /// « _chat.txt » (iOS) ou « Discussion WhatsApp avec … .txt » (Android).
  static bool estNomDeDiscussion(EntreeArchive e) {
    final base = e.nom.replaceAll('\\', '/').split('/').last;
    return base.toLowerCase() == '_chat.txt' ||
        AnalyseurWhatsApp.titreDepuisNom(base) != null;
  }

  // Texte énorme et compressé à l'extrême : signature d'une « bombe ».
  static bool _semblableABombe(EntreeArchive e) =>
      e.taille > (64 << 20) && e.taille > e.tailleCompressee * 200;

  Future<ExportLocal> _copier(
    SurProgression? progression,
    void Function() verifier,
  ) async {
    final local = await _creerLocal();
    final total = export.fichier.tailleOctets;
    progression?.call(EtapeLecture.copie, total == null ? null : 0);
    try {
      await for (final morceau in export.lireContenu()) {
        verifier();
        await local.ecrire(morceau);
        if (local.taille > SelectionExportWhatsApp.tailleMaximale) {
          throw const _Erreur(ErreurLecture.tropVolumineux);
        }
        if (total != null && total > 0) {
          progression?.call(
            EtapeLecture.copie,
            (local.taille / total).clamp(0.0, 1.0),
          );
        }
      }
      await local.fermerEcriture();
      return local;
    } on StateError {
      // Contenu déjà lu (fichier partagé qui ne se relit pas).
      await local.supprimer();
      throw const _Erreur(ErreurLecture.accesImpossible);
    } on _Arret {
      await local.supprimer();
      rethrow;
    } on _Erreur {
      await local.supprimer();
      rethrow;
    } catch (_) {
      await local.supprimer();
      throw const _Erreur(ErreurLecture.accesImpossible);
    }
  }

  static Stream<List<int>> _tranches(Uint8List octets) async* {
    const tranche = 256 * 1024;
    for (var i = 0; i < octets.length; i += tranche) {
      final fin = i + tranche < octets.length ? i + tranche : octets.length;
      yield Uint8List.sublistView(octets, i, fin);
    }
  }

  /// Texte → messages, ligne par ligne, en rendant la main à l'interface.
  static Future<ConversationWhatsApp> _analyser(
    Stream<List<int>> flux,
    int total, {
    required String nomFichier,
    String? nomExport,
    SurProgression? progression,
    required void Function() verifier,
  }) async {
    final analyseur = AnalyseurWhatsApp();
    var lus = 0;
    progression?.call(EtapeLecture.messages, total > 0 ? 0 : null);
    final compte = flux.map((m) {
      lus += m.length;
      return m;
    });
    await for (final ligne in _lignes(compte)) {
      analyseur.ajouterLigne(ligne);
      if (analyseur.lignes % _paquet == 0) {
        verifier();
        if (total > 0) {
          progression?.call(EtapeLecture.messages, (lus / total).clamp(0, 1));
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
    verifier();
    return analyseur.terminer(nomFichier: nomFichier, nomExport: nomExport);
  }

  /// Lignes du texte : UTF-8 (cas courant, octets invalides tolérés) ou
  /// UTF-16 (marque d'ordre des octets).
  static Stream<String> _lignes(Stream<List<int>> flux) async* {
    final iterateur = StreamIterator(flux);
    if (!await iterateur.moveNext()) return;
    final premier = iterateur.current;
    final utf16 =
        premier.length >= 2 &&
        ((premier[0] == 0xFF && premier[1] == 0xFE) ||
            (premier[0] == 0xFE && premier[1] == 0xFF));
    Stream<List<int>> reste() async* {
      yield premier;
      while (await iterateur.moveNext()) {
        yield iterateur.current;
      }
    }

    if (utf16) {
      final tout = BytesBuilder(copy: false);
      await for (final m in reste()) {
        tout.add(m);
      }
      yield* Stream.fromIterable(
        const LineSplitter().convert(_decoderUtf16(tout.takeBytes())),
      );
      return;
    }
    yield* reste()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }

  static String _decoderUtf16(Uint8List o) {
    final petitBoutiste = o[0] == 0xFF;
    final unites = Uint16List((o.length - 2) ~/ 2);
    for (var i = 0; i < unites.length; i++) {
      final a = o[2 + 2 * i], b = o[3 + 2 * i];
      unites[i] = petitBoutiste ? a | (b << 8) : (a << 8) | b;
    }
    return String.fromCharCodes(unites);
  }
}

class _Erreur implements Exception {
  const _Erreur(this.erreur);
  final ErreurLecture erreur;
}
