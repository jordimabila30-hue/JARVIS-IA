/// Interruption de la parole de JARVIS (vocal principal et JARVIS Touch).
/// Le bouton « Arrêter la parole » existe dans les deux modes ;
/// l'automatique (voix de l'utilisateur détectée pendant la réponse) reste
/// indisponible tant que sa fiabilité n'est pas démontrée
/// ([disponible] faux).
enum ModeInterruption {
  manuelle('Manuelle', true),
  automatique('Automatique', false);

  const ModeInterruption(this.libelle, this.disponible);

  final String libelle;
  final bool disponible;
}

/// Profils vocaux : des préréglages de débit et de hauteur.
enum ProfilVocal {
  classique('Classique', 'Posé, légèrement grave'),
  naturel('Naturel', 'Rythme de conversation'),
  clair('Clair', 'Un peu plus lent, bien articulé'),
  dynamique('Dynamique', 'Plus vif, plus d’énergie'),

  /// Vitesse ou hauteur modifiée à la main.
  personnalise('Personnalisé', 'Réglé à la main');

  const ProfilVocal(this.libelle, this.description);

  final String libelle;
  final String description;

  /// Profils proposés à l'utilisateur (« Personnalisé » est un résultat).
  static const predefinis = [classique, naturel, clair, dynamique];
}

/// Valeurs d'un profil prédéfini.
class PresetVocal {
  const PresetVocal({required this.vitesse, required this.hauteur});

  final double vitesse;
  final double hauteur;
}

/// Réglages du chat vocal : la source de vérité unique, lue par la synthèse
/// vocale, la session vocale et le panneau Paramètres.
///
/// Les valeurs sont indépendantes de la plateforme :
/// - [vitesse] : multiplicateur du débit normal (1.0 = débit normal) ;
/// - [hauteur] : écart relatif à la hauteur normale (0.1 = +10 %) ;
/// - [volume] : 0 à 1.
/// La conversion vers chaque moteur se fait dans `TtsService`.
class VoiceSettings {
  const VoiceSettings({
    this.profil = ProfilVocal.naturel,
    this.locale = 'fr-FR',
    this.voix,
    this.vitesse = 1.0,
    this.hauteur = 0.0,
    this.volume = 1.0,
    this.microphoneId,
    this.reponseAutomatique = true,
    this.interruption = ModeInterruption.manuelle,
  });

  final ProfilVocal profil;

  /// Langue / accent de la voix (« fr-FR », « fr-CA »…).
  final String locale;

  /// Nom de la voix choisie ; null = choix automatique pour la [locale].
  final String? voix;

  final double vitesse;
  final double hauteur;
  final double volume;

  /// Micro choisi (identifiant du périphérique) ; null = micro par défaut.
  final String? microphoneId;

  /// Vrai : JARVIS répond dès la fin de la phrase. Faux : la phrase
  /// reconnue attend une validation.
  final bool reponseAutomatique;

  /// Interruption de la parole (manuelle par défaut, jamais supprimable).
  final ModeInterruption interruption;

  // --- Bornes : une voix toujours utilisable, jamais caricaturale --------

  static const vitesseMin = 0.75;
  static const vitesseMax = 1.35;
  static const hauteurMin = -0.15;
  static const hauteurMax = 0.15;

  static const defaut = VoiceSettings();

  /// Valeurs de chaque profil prédéfini. Pour ajouter un profil : une
  /// valeur dans [ProfilVocal] et une entrée ici.
  static const presets = <ProfilVocal, PresetVocal>{
    ProfilVocal.classique: PresetVocal(vitesse: 0.92, hauteur: -0.05),
    ProfilVocal.naturel: PresetVocal(vitesse: 1.0, hauteur: 0),
    ProfilVocal.clair: PresetVocal(vitesse: 0.88, hauteur: 0.04),
    ProfilVocal.dynamique: PresetVocal(vitesse: 1.12, hauteur: 0.03),
  };

  VoiceSettings copyWith({
    ProfilVocal? profil,
    String? locale,
    String? Function()? voix,
    double? vitesse,
    double? hauteur,
    double? volume,
    String? Function()? microphoneId,
    bool? reponseAutomatique,
    ModeInterruption? interruption,
  }) => VoiceSettings(
    profil: profil ?? this.profil,
    locale: locale ?? this.locale,
    voix: voix != null ? voix() : this.voix,
    vitesse: (vitesse ?? this.vitesse).clamp(vitesseMin, vitesseMax),
    hauteur: (hauteur ?? this.hauteur).clamp(hauteurMin, hauteurMax),
    volume: (volume ?? this.volume).clamp(0.0, 1.0),
    microphoneId: microphoneId != null ? microphoneId() : this.microphoneId,
    reponseAutomatique: reponseAutomatique ?? this.reponseAutomatique,
    interruption: interruption ?? this.interruption,
  );

  /// Applique un profil prédéfini (vitesse et hauteur ; le volume reste
  /// celui de l'utilisateur).
  VoiceSettings avecProfil(ProfilVocal p) {
    final preset = presets[p];
    if (preset == null) return copyWith(profil: p);
    return copyWith(
      profil: p,
      vitesse: preset.vitesse,
      hauteur: preset.hauteur,
    );
  }

  /// Vitesse ou hauteur réglée à la main : le profil devient
  /// « Personnalisé », sauf si les valeurs retombent sur un profil.
  VoiceSettings avecReglageManuel({double? vitesse, double? hauteur}) {
    final r = copyWith(vitesse: vitesse, hauteur: hauteur);
    return r.copyWith(profil: r.profilCorrespondant);
  }

  /// Profil prédéfini dont les valeurs correspondent, sinon Personnalisé.
  ProfilVocal get profilCorrespondant {
    for (final e in presets.entries) {
      if ((e.value.vitesse - vitesse).abs() < 0.005 &&
          (e.value.hauteur - hauteur).abs() < 0.005) {
        return e.key;
      }
    }
    return ProfilVocal.personnalise;
  }

  Map<String, Object?> toJson() => {
    'profil': profil.name,
    'locale': locale,
    'voix': voix,
    'vitesse': vitesse,
    'hauteur': hauteur,
    'volume': volume,
    'microphoneId': microphoneId,
    'reponseAutomatique': reponseAutomatique,
    'interruption': interruption.name,
  };

  /// Lecture tolérante : une valeur absente ou invalide reprend sa valeur
  /// par défaut, les nombres sont ramenés dans leurs bornes.
  factory VoiceSettings.fromJson(Map<String, Object?> json) {
    double nombre(String cle, double defaut) {
      final v = json[cle];
      return v is num && v.isFinite ? v.toDouble() : defaut;
    }

    String? texte(String cle) {
      final v = json[cle];
      return v is String && v.isNotEmpty ? v : null;
    }

    final profil = ProfilVocal.values.firstWhere(
      (p) => p.name == json['profil'],
      orElse: () => defaut.profil,
    );
    final auto = json['reponseAutomatique'];
    // Un mode encore indisponible n'est jamais relu comme actif.
    final interruption = ModeInterruption.values.firstWhere(
      (m) => m.name == json['interruption'] && m.disponible,
      orElse: () => defaut.interruption,
    );
    return const VoiceSettings().copyWith(
      profil: profil,
      locale: texte('locale') ?? defaut.locale,
      voix: () => texte('voix'),
      vitesse: nombre('vitesse', defaut.vitesse),
      hauteur: nombre('hauteur', defaut.hauteur),
      volume: nombre('volume', defaut.volume),
      microphoneId: () => texte('microphoneId'),
      reponseAutomatique: auto is bool ? auto : defaut.reponseAutomatique,
      interruption: interruption,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceSettings &&
      other.profil == profil &&
      other.locale == locale &&
      other.voix == voix &&
      other.vitesse == vitesse &&
      other.hauteur == hauteur &&
      other.volume == volume &&
      other.microphoneId == microphoneId &&
      other.reponseAutomatique == reponseAutomatique &&
      other.interruption == interruption;

  @override
  int get hashCode => Object.hash(
    profil,
    locale,
    voix,
    vitesse,
    hauteur,
    volume,
    microphoneId,
    reponseAutomatique,
    interruption,
  );
}

/// Une voix de synthèse disponible sur l'appareil ou le navigateur.
class VoixDisponible {
  const VoixDisponible({
    required this.nom,
    required this.locale,
    this.enLigne = false,
    this.qualite,
  });

  final String nom;

  /// Locale normalisée (« fr-FR »).
  final String locale;

  /// Vrai si la voix nécessite Internet (quand la plateforme le dit).
  final bool enLigne;

  /// Qualité annoncée par la plateforme (« enhanced »…), si connue.
  final String? qualite;
}

/// Un micro disponible.
class MicroDisponible {
  const MicroDisponible({
    required this.id,
    required this.nom,
    this.nomConnu = true,
  });

  final String id;
  final String nom;

  /// Faux quand le navigateur cache le vrai nom (accès au micro pas encore
  /// accordé) : [nom] est alors « Microphone 1 », « Microphone 2 »…
  final bool nomConnu;
}
