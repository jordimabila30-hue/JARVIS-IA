package com.example.ia_jarvis

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Import WhatsApp, côté Android : partages reçus (« Exporter la
 * discussion » → JARVIS) et sélecteur de documents.
 *
 * Les fichiers restent des URI `content://`, lus en flux à la demande de
 * Flutter : aucun chemin, aucune copie, aucune permission de stockage. Le
 * droit de lecture temporaire accordé par l'application qui partage (ou
 * par le sélecteur) suffit. Rien du contenu n'est journalisé.
 */
class PontImportation(
    private val activite: Activity,
    messager: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CODE_SELECTEUR = 0x4A41
        private const val TAILLE_MORCEAU = 256 * 1024
    }

    private val canal = MethodChannel(messager, "jarvis/importation")
    private val lecteur = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    // Références temporaires données à Flutter (jamais l'URI elle-même).
    private val references = ConcurrentHashMap<String, Uri>()
    private val lectures = ConcurrentHashMap<Int, InputStream>()
    private var prochaineRef = 0
    private var prochaineLecture = 0
    private var prochainPartage = 0

    // Un seul partage en attente : le plus récent remplace l'ancien.
    private var partageEnAttente: Pair<String, List<Pair<Uri, String?>>>? = null
    private var selectionEnCours: MethodChannel.Result? = null

    init {
        canal.setMethodCallHandler(this)
    }

    /** Intent reçu au lancement ou alors que JARVIS est déjà ouvert. */
    fun recevoir(intent: Intent?) {
        if (intent == null) return
        // Relancé depuis les applications récentes : déjà traité.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val uris = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(flux(intent))
            Intent.ACTION_SEND_MULTIPLE -> fluxMultiples(intent)
            else -> return
        }
        // Seules les URI content:// sont lues : un file:// pourrait
        // désigner les fichiers privés de JARVIS.
        val fichiers = uris.filter { it.scheme == "content" }.distinct()
        val typeAnnonce = intent.type?.takeUnless { it.contains('*') }
        partageEnAttente = Pair(
            "partage-${System.currentTimeMillis()}-${prochainPartage++}",
            fichiers.map { Pair(it, if (fichiers.size == 1) typeAnnonce else null) },
        )
        // L'intent ne doit pas être retraité (rotation, retour).
        intent.action = null
        canal.invokeMethod("partageDisponible", null)
    }

    /** Résultat du sélecteur ; true s'il était pour nous. */
    fun surResultat(code: Int, resultat: Int, donnees: Intent?): Boolean {
        if (code != CODE_SELECTEUR) return false
        val reponse = selectionEnCours ?: return true
        selectionEnCours = null
        val uri = donnees?.data
        if (resultat != Activity.RESULT_OK || uri == null) {
            reponse.success(null)
            return true
        }
        lecteur.execute {
            val description = decrire(uri, null)
            principal.post { reponse.success(description) }
        }
        return true
    }

    fun fermer() {
        canal.setMethodCallHandler(null)
        selectionEnCours?.success(null)
        selectionEnCours = null
        lecteur.execute {
            lectures.values.forEach { runCatching { it.close() } }
            lectures.clear()
        }
        lecteur.shutdown()
    }

    override fun onMethodCall(appel: MethodCall, reponse: MethodChannel.Result) {
        when (appel.method) {
            "prendrePartage" -> {
                val partage = partageEnAttente
                partageEnAttente = null
                if (partage == null) {
                    reponse.success(null)
                    return
                }
                lecteur.execute {
                    val fichiers = partage.second.map { (uri, type) -> decrire(uri, type) }
                    val donnees = mapOf("id" to partage.first, "fichiers" to fichiers)
                    principal.post { reponse.success(donnees) }
                }
            }

            "choisirFichier" -> choisirFichier(reponse)

            // Copie temporaire d'un export pendant sa lecture (privée,
            // effacée par Flutter ensuite).
            "dossierTemporaire" -> reponse.success(activite.cacheDir.absolutePath)

            // Ouvre WhatsApp (ou WhatsApp Business) : l'export se lance
            // là-bas, puis revient par le partage. false s'il est absent.
            "ouvrirWhatsApp" -> {
                val pm = activite.packageManager
                val intent = listOf("com.whatsapp", "com.whatsapp.w4b")
                    .firstNotNullOfOrNull { pm.getLaunchIntentForPackage(it) }
                if (intent == null) {
                    reponse.success(false)
                } else {
                    try {
                        activite.startActivity(intent)
                        reponse.success(true)
                    } catch (e: ActivityNotFoundException) {
                        reponse.success(false)
                    }
                }
            }

            // Menu « + » : Instagram, Messenger (paquets), Mail (appli e-mail
            // par défaut). false : absente, l'appelant ouvre le site.
            "ouvrirApplication" -> {
                val pm = activite.packageManager
                val cible = appel.arguments as? String
                val intent = if (cible == "mail") {
                    Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_EMAIL)
                        .takeIf { it.resolveActivity(pm) != null }
                } else {
                    cible?.let { pm.getLaunchIntentForPackage(it) }
                }
                if (intent == null) {
                    reponse.success(false)
                } else {
                    try {
                        activite.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        reponse.success(true)
                    } catch (e: ActivityNotFoundException) {
                        reponse.success(false)
                    }
                }
            }

            "ouvrirLecture" -> {
                val uri = references[appel.arguments as String]
                if (uri == null) {
                    reponse.error("inconnu", "Fichier introuvable.", null)
                    return
                }
                lecteur.execute {
                    try {
                        val flux = activite.contentResolver.openInputStream(uri)
                            ?: throw IllegalStateException()
                        val id = prochaineLecture++
                        lectures[id] = flux
                        principal.post { reponse.success(id) }
                    } catch (e: Exception) {
                        principal.post { reponse.error("acces", "Lecture impossible.", null) }
                    }
                }
            }

            "lire" -> {
                val id = appel.arguments as Int
                lecteur.execute {
                    val flux = lectures[id]
                    if (flux == null) {
                        principal.post { reponse.success(null) }
                        return@execute
                    }
                    try {
                        val tampon = ByteArray(TAILLE_MORCEAU)
                        val n = flux.read(tampon)
                        val morceau = if (n < 0) null else tampon.copyOf(n)
                        principal.post { reponse.success(morceau) }
                    } catch (e: Exception) {
                        principal.post { reponse.error("acces", "Lecture interrompue.", null) }
                    }
                }
            }

            "fermerLecture" -> {
                val id = appel.arguments as Int
                lecteur.execute {
                    lectures.remove(id)?.let { runCatching { it.close() } }
                    principal.post { reponse.success(null) }
                }
            }

            else -> reponse.notImplemented()
        }
    }

    private fun choisirFichier(reponse: MethodChannel.Result) {
        if (selectionEnCours != null) {
            reponse.error("occupe", "Un sélecteur est déjà ouvert.", null)
            return
        }
        // Aucun filtre de type : les exports mal étiquetés (octet-stream,
        // x-zip-compressed…) restent sélectionnables ; Flutter reconnaît
        // le format d'après le contenu.
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            selectionEnCours = reponse
            activite.startActivityForResult(intent, CODE_SELECTEUR)
        } catch (e: ActivityNotFoundException) {
            selectionEnCours = null
            reponse.error("aucun_selecteur", "Aucun sélecteur de fichiers.", null)
        }
    }

    /** Nom, taille et type, quand le fournisseur les donne. */
    private fun decrire(uri: Uri, typeAnnonce: String?): Map<String, Any?> {
        var nom: String? = null
        var taille: Long? = null
        try {
            activite.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst()) {
                    val iNom = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (iNom >= 0 && !c.isNull(iNom)) nom = c.getString(iNom)
                    val iTaille = c.getColumnIndex(OpenableColumns.SIZE)
                    if (iTaille >= 0 && !c.isNull(iTaille)) taille = c.getLong(iTaille)
                }
            }
        } catch (e: Exception) {
            // Fournisseur muet ou droit retiré : la lecture le dira.
        }
        val mime = try {
            activite.contentResolver.getType(uri)
        } catch (e: Exception) {
            null
        } ?: typeAnnonce
        val ref = "ref-${prochaineRef++}"
        references[ref] = uri
        return mapOf(
            "ref" to ref,
            "nom" to (nom ?: uri.lastPathSegment),
            "taille" to taille?.takeIf { it > 0 },
            "mime" to mime,
        )
    }

    @Suppress("DEPRECATION")
    private fun flux(intent: Intent): Uri? {
        val uri = if (Build.VERSION.SDK_INT >= 34) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
        return uri ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    }

    @Suppress("DEPRECATION")
    private fun fluxMultiples(intent: Intent): List<Uri> {
        val liste: List<Uri>? = if (Build.VERSION.SDK_INT >= 34) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
        if (!liste.isNullOrEmpty()) return liste
        val clip = intent.clipData ?: return emptyList()
        return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
    }
}
