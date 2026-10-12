/// États du mode vocal, partagés par la session vocale et PIM.
enum VoiceState {
  /// JARVIS ne fait rien : PIM respire lentement.
  idle,

  /// Le microphone écoute : PIM réagit à l'amplitude de la voix.
  listening,

  /// Une phrase a été reconnue : PIM se concentre.
  thinking,

  /// JARVIS parle (synthèse vocale) : PIM ondule.
  speaking,
}
