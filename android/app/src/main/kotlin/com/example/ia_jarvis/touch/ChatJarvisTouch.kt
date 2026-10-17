package com.example.ia_jarvis.touch

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.SystemClock
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import com.example.ia_jarvis.R
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Mini-chat de JARVIS Touch : vue native compacte de LA conversation de
 * l'accueil (aucun historique ici, seulement ce qui est affiché). Dart
 * envoie un instantané quand ce qui est affiché change (`etat`) et le
 * texte du message en réception (`fragment`, regroupé) ; seule la bulle
 * concernée est mise à jour.
 *
 * Fenêtre en haut de l'écran (le clavier reste dessous), focalisable pour
 * écrire ; un toucher ailleurs lui retire le focus (clavier rendu à
 * l'application de dessous). Retour = réduire.
 */
class ChatJarvisTouch(
    private val contexte: Context,
    private val wm: WindowManager,
    private val zone: Rect,
    private val surReduire: () -> Unit,
    private val surOuvrirJarvis: () -> Unit,
) {
    private companion object {
        const val TAG = "JarvisTouch"
        val IVOIRE = Color.rgb(0xFF, 0xFD, 0xF9)
        val TRAIT = Color.rgb(0xDC, 0xD3, 0xC4)
        val SIGNAL = Color.rgb(0x55, 0x59, 0xB8)
        val TEXTE = Color.rgb(0x27, 0x29, 0x32)
        val SECONDAIRE = Color.rgb(0x6F, 0x6A, 0x72)
        val ERREUR = Color.rgb(0xA6, 0x3D, 0x40)
    }

    private val densite = contexte.resources.displayMetrics.density
    private fun dp(v: Number) = (v.toFloat() * densite).roundToInt()

    private class Message(
        val id: Int,
        val moi: Boolean,
        var texte: String,
        val redaction: Boolean,
        val incident: String?,
        val note: String?,
    )

    private val messages = ArrayList<Message>()
    private var idConversation: String? = null
    private var plusAnciens = false
    private var chargementAnciens = false
    private var defileParUtilisateur = false
    private var forcerBas = true
    private var ferme = false

    // Mesures (aucun contenu journalisé).
    private val ouvertA = SystemClock.elapsedRealtime()
    private var premierAffichage = false
    private var nbFragments = 0
    private var latenceTotale = 0L
    private var latenceMax = 0L

    private val racine = object : FrameLayout(contexte) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (event.keyCode == KeyEvent.KEYCODE_BACK) {
                if (event.action == KeyEvent.ACTION_UP) surReduire()
                return true
            }
            return super.dispatchKeyEvent(event)
        }
    }
    private val titre = TextView(contexte)
    private val liste = ListView(contexte)
    private val vide = TextView(contexte)
    private val statut = TextView(contexte)
    private val saisie = EditText(contexte)
    private val envoyer = ImageView(contexte)
    private val adaptateur = Adaptateur()
    private var pulsation: ObjectAnimator? = null

    private val largeur = minOf(zone.width() - dp(24), dp(440))
    private val hauteurBase = minOf((zone.height() * 0.56f).roundToInt(), dp(560))
        .coerceAtLeast(minOf(dp(300), zone.height()))
    private var reductionClavier = 0
    private val params = WindowManager.LayoutParams(
        largeur, hauteurBase,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        },
        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = zone.left + (zone.width() - largeur) / 2
        y = zone.top + dp(8)
        softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING or
            WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN
    }

    init {
        construire()
    }

    // ── Cycle de vie ────────────────────────────────────────────────────

    fun afficher() {
        wm.addView(racine, params)
        CanalMiniChat.recepteur = { methode, args -> recevoir(methode, args) }
        CanalMiniChat.appeler("ouvrir", null, { appliquer(it) }, { injoignable(it) })
    }

    fun retirer() {
        if (ferme) return
        ferme = true
        if (CanalMiniChat.recepteur != null) CanalMiniChat.recepteur = null
        CanalMiniChat.appeler("fermer", null, {}, {})
        pulsation?.cancel()
        cacherClavier()
        try {
            wm.removeViewImmediate(racine)
        } catch (_: Exception) {
        }
        if (nbFragments > 0) {
            Log.i(TAG, "mini-chat : $nbFragments fragments, latence moyenne " +
                "${latenceTotale / nbFragments} ms, max $latenceMax ms")
        }
    }

    // ── Données venues de Dart ──────────────────────────────────────────

    private fun recevoir(methode: String, args: Any?) {
        if (ferme) return
        when (methode) {
            "etat" -> appliquer(args)
            "fragment" -> fragment(args as? Map<*, *> ?: return)
        }
    }

    private fun appliquer(etat: Any?) {
        if (ferme) return
        val e = etat as? Map<*, *> ?: return injoignable(null)
        val conversation = e["idConversation"] as? String
        val autreConversation = conversation != idConversation
        idConversation = conversation
        titre.text = e["titre"] as? String ?: "Conversation"
        plusAnciens = e["plusAnciens"] == true
        val reflexion = e["reflexion"] == true
        val chargement = e["chargement"] == true

        // Position de lecture : en bas (suivre), ou ancrée sur un message.
        val enBas = forcerBas || autreConversation || estEnBas()
        val premier = liste.firstVisiblePosition
        val ancre = messages.getOrNull(premier)?.id
        val decalage = liste.getChildAt(0)?.top ?: 0

        messages.clear()
        (e["messages"] as? List<*>)?.forEach { m ->
            val d = m as? Map<*, *> ?: return@forEach
            messages.add(
                Message(
                    id = (d["id"] as Number).toInt(),
                    moi = d["moi"] == true,
                    texte = d["texte"] as? String ?: "",
                    redaction = d["redaction"] == true,
                    incident = d["incident"] as? String,
                    note = d["note"] as? String,
                )
            )
        }
        adaptateur.notifyDataSetChanged()
        vide.text = if (chargement) "Chargement de la conversation…" else "Écrivez à JARVIS : la conversation continue ici et dans l’application."
        montrerStatut(
            when {
                reflexion -> "JARVIS prépare sa réponse…"
                chargement && messages.isNotEmpty() -> "Chargement…"
                else -> null
            },
            pulser = reflexion,
        )
        if (enBas) {
            allerEnBas()
        } else if (ancre != null) {
            val i = messages.indexOfFirst { it.id == ancre }
            if (i >= 0) liste.setSelectionFromTop(i, decalage)
        }
        forcerBas = false
        if (!premierAffichage) {
            premierAffichage = true
            racine.post {
                Log.i(TAG, "mini-chat affiché en ${SystemClock.elapsedRealtime() - ouvertA} ms " +
                    "(${messages.size} messages)")
            }
        }
    }

    /** Texte du message en réception : seule sa bulle change. */
    private fun fragment(d: Map<*, *>) {
        val id = (d["id"] as? Number)?.toInt() ?: return
        val texte = d["texte"] as? String ?: return
        val i = messages.indexOfLast { it.id == id }
        if (i < 0) return
        val enBas = estEnBas()
        messages[i].texte = texte
        val vue = liste.getChildAt(i - liste.firstVisiblePosition)
        (vue?.tag as? Porteur)?.texte?.text = texte.ifEmpty { "…" }
        if (enBas) allerEnBas()
        (d["t"] as? Number)?.toLong()?.let { t ->
            racine.post {
                val l = System.currentTimeMillis() - t
                nbFragments++
                latenceTotale += l
                if (l > latenceMax) latenceMax = l
            }
        }
    }

    private fun injoignable(raison: String?) {
        if (ferme) return
        montrerStatut(
            raison ?: "JARVIS n’est pas disponible ici : ouvrez l’application (connexion requise).",
            pulser = false,
            erreur = true,
        )
    }

    // ── Envoi ───────────────────────────────────────────────────────────

    private fun envoyerMessage() {
        val texte = saisie.text.toString().trim()
        if (texte.isEmpty()) return
        saisie.setText("")
        // Mot encore « en composition » dans le clavier : oublié, sinon il
        // reviendrait dans le champ vidé.
        contexte.getSystemService(InputMethodManager::class.java)?.restartInput(saisie)
        forcerBas = true
        val args = mapOf("texte" to texte, "idEnvoi" to UUID.randomUUID().toString())
        CanalMiniChat.appeler("envoyer", args, { ok ->
            if (ok != true) rendre(texte, "Message non envoyé.")
        }, { raison ->
            // Jamais perdu : il revient dans le champ, rien n'est renvoyé
            // automatiquement.
            rendre(texte, raison ?: "JARVIS n’est pas joignable : ouvrez l’application, puis réessayez.")
        })
    }

    private fun rendre(texte: String, erreur: String) {
        if (ferme) return
        if (saisie.text.isEmpty()) saisie.setText(texte)
        saisie.setSelection(saisie.text.length)
        montrerStatut(erreur, pulser = false, erreur = true)
    }

    // ── Défilement ──────────────────────────────────────────────────────

    private fun estEnBas(): Boolean {
        val n = adaptateur.count
        if (n == 0 || liste.childCount == 0) return true
        if (liste.lastVisiblePosition < n - 1) return false
        val dernier = liste.getChildAt(liste.childCount - 1) ?: return true
        return dernier.bottom <= liste.height - liste.paddingBottom + dp(24)
    }

    private fun allerEnBas() {
        liste.post {
            val n = adaptateur.count
            if (n == 0) return@post
            if (liste.lastVisiblePosition < n - 1) liste.setSelection(n - 1)
            liste.post {
                val v = liste.getChildAt(liste.childCount - 1) ?: return@post
                val d = v.bottom - (liste.height - liste.paddingBottom)
                if (d > 0) liste.scrollListBy(d)
            }
        }
    }

    private fun chargerAnciens() {
        if (chargementAnciens || !plusAnciens) return
        chargementAnciens = true
        CanalMiniChat.appeler("plusAnciens", null, {
            chargementAnciens = false
            appliquer(it)
        }, {
            chargementAnciens = false
        })
    }

    // ── Clavier et focus ────────────────────────────────────────────────

    private fun prendreFocus() {
        if (params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0) {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            mettreAJour()
        }
        // Fenêtre de nouveau focalisable : le champ et le clavier suivent
        // (sinon le premier toucher ne ferait que rendre le focus).
        saisie.post {
            if (ferme) return@post
            saisie.requestFocus()
            contexte.getSystemService(InputMethodManager::class.java)
                ?.showSoftInput(saisie, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /** Toucher hors de la fenêtre : le clavier revient à l'autre appli. */
    private fun rendreFocus() {
        cacherClavier()
        if (params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0) return
        params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        mettreAJour()
    }

    private fun cacherClavier() {
        contexte.getSystemService(InputMethodManager::class.java)
            ?.hideSoftInputFromWindow(saisie.windowToken, 0)
        saisie.clearFocus()
    }

    /** Clavier visible : la fenêtre se raccourcit au-dessus de lui. */
    private fun surEncarts(encarts: WindowInsets) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val visible = encarts.isVisible(WindowInsets.Type.ime())
        val chevauchement = encarts.getInsets(WindowInsets.Type.ime()).bottom
        val avant = reductionClavier
        if (!visible) {
            reductionClavier = 0
        } else if (chevauchement > 0) {
            reductionClavier = (reductionClavier + chevauchement)
                .coerceAtMost(hauteurBase - dp(180))
        }
        if (reductionClavier != avant) {
            val enBas = estEnBas()
            params.height = hauteurBase - reductionClavier
            mettreAJour()
            if (enBas) allerEnBas()
        }
    }

    private fun mettreAJour() {
        if (ferme) return
        try {
            wm.updateViewLayout(racine, params)
        } catch (_: Exception) {
        }
    }

    // ── Interface ───────────────────────────────────────────────────────

    private fun construire() {
        val panneau = LinearLayout(contexte).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(IVOIRE)
                setStroke(dp(1), TRAIT)
            }
            clipToOutline = true
        }
        racine.addView(panneau, FrameLayout.LayoutParams(MATCH, MATCH))
        racine.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_OUTSIDE) rendreFocus()
            false
        }
        racine.setOnApplyWindowInsetsListener { _, encarts ->
            surEncarts(encarts)
            encarts
        }

        panneau.addView(entete(), LinearLayout.LayoutParams(MATCH, WRAP))
        panneau.addView(View(contexte).apply { setBackgroundColor(TRAIT) }, LinearLayout.LayoutParams(MATCH, 1))

        val centre = FrameLayout(contexte)
        liste.apply {
            divider = null
            dividerHeight = 0
            selector = GradientDrawable().apply { setColor(Color.TRANSPARENT) }
            isStackFromBottom = true
            transcriptMode = AbsListView.TRANSCRIPT_MODE_DISABLED
            clipToPadding = false
            setPadding(dp(14), dp(10), dp(14), dp(10))
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            adapter = adaptateur
            setOnScrollListener(object : AbsListView.OnScrollListener {
                override fun onScrollStateChanged(v: AbsListView, etat: Int) {
                    if (etat == AbsListView.OnScrollListener.SCROLL_STATE_TOUCH_SCROLL) {
                        defileParUtilisateur = true
                    }
                }

                override fun onScroll(v: AbsListView, premier: Int, visibles: Int, total: Int) {
                    if (defileParUtilisateur && premier == 0 && total > 0) chargerAnciens()
                }
            })
        }
        vide.apply {
            setTextColor(SECONDAIRE)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(dp(28), 0, dp(28), 0)
        }
        centre.addView(liste, FrameLayout.LayoutParams(MATCH, MATCH))
        centre.addView(vide, FrameLayout.LayoutParams(MATCH, MATCH))
        liste.emptyView = vide
        panneau.addView(centre, LinearLayout.LayoutParams(MATCH, 0, 1f))

        statut.apply {
            textSize = 12.5f
            setPadding(dp(18), dp(4), dp(18), dp(4))
            visibility = View.GONE
        }
        panneau.addView(statut, LinearLayout.LayoutParams(MATCH, WRAP))
        panneau.addView(barreSaisie(), LinearLayout.LayoutParams(MATCH, WRAP))
    }

    private fun entete(): View {
        val ligne = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(8), dp(6), dp(8))
        }
        ligne.addView(View(contexte).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(SIGNAL)
            }
        }, LinearLayout.LayoutParams(dp(9), dp(9)).apply { marginEnd = dp(10) })
        val textes = LinearLayout(contexte).apply { orientation = LinearLayout.VERTICAL }
        textes.addView(TextView(contexte).apply {
            text = "JARVIS"
            textSize = 11f
            letterSpacing = 0.16f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(SIGNAL)
        })
        titre.apply {
            textSize = 14.5f
            setTextColor(TEXTE)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        textes.addView(titre)
        ligne.addView(textes, LinearLayout.LayoutParams(0, WRAP, 1f))
        ligne.addView(bouton(R.drawable.touch_ouvrir, "Ouvrir dans JARVIS") { surOuvrirJarvis() })
        ligne.addView(bouton(R.drawable.touch_reduire, "Réduire") { surReduire() })
        return ligne
    }

    private fun bouton(icone: Int, description: String, action: () -> Unit) =
        ImageView(contexte).apply {
            setImageResource(icone)
            contentDescription = description
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(12), dp(12), dp(12), dp(12))
            isClickable = true
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(dp(46), dp(46))
        }

    private fun barreSaisie(): View {
        val ligne = LinearLayout(contexte).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
            setPadding(dp(10), dp(6), dp(10), dp(10))
        }
        saisie.apply {
            hint = "Écrire à JARVIS…"
            setHintTextColor(SECONDAIRE)
            setTextColor(TEXTE)
            textSize = 15f
            minLines = 1
            maxLines = 4
            isVerticalScrollBarEnabled = false
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setPadding(dp(16), dp(10), dp(16), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(22).toFloat()
                setColor(Color.rgb(0xF3, 0xEE, 0xE4))
            }
            setOnTouchListener { _, e ->
                if (e.actionMasked == MotionEvent.ACTION_DOWN) prendreFocus()
                false
            }
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
                override fun afterTextChanged(s: Editable?) = activerEnvoi()
            })
        }
        ligne.addView(saisie, LinearLayout.LayoutParams(0, WRAP, 1f))
        envoyer.apply {
            setImageResource(R.drawable.touch_envoyer)
            contentDescription = "Envoyer"
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(11), dp(11), dp(9), dp(11))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(SIGNAL)
            }
            setOnClickListener { envoyerMessage() }
        }
        ligne.addView(envoyer, LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginStart = dp(8) })
        activerEnvoi()
        return ligne
    }

    private fun activerEnvoi() {
        val oui = saisie.text.isNotBlank()
        envoyer.isEnabled = oui
        envoyer.alpha = if (oui) 1f else 0.35f
    }

    private fun montrerStatut(texte: String?, pulser: Boolean, erreur: Boolean = false) {
        pulsation?.cancel()
        pulsation = null
        statut.alpha = 1f
        if (texte == null) {
            statut.visibility = View.GONE
            return
        }
        statut.text = texte
        statut.setTextColor(if (erreur) ERREUR else SECONDAIRE)
        statut.visibility = View.VISIBLE
        // Seule animation du mini-chat, et seulement pendant la réflexion.
        if (pulser) {
            pulsation = ObjectAnimator.ofFloat(statut, View.ALPHA, 1f, 0.4f).apply {
                duration = 700
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                start()
            }
        }
    }

    // ── Liste ───────────────────────────────────────────────────────────

    private class Porteur(val texte: TextView, val note: TextView?, val incident: TextView?)

    private inner class Adaptateur : BaseAdapter() {
        override fun getCount() = messages.size
        override fun getItem(position: Int) = messages[position]
        override fun getItemId(position: Int) = messages[position].id.toLong()
        override fun hasStableIds() = true
        override fun getViewTypeCount() = 2
        override fun getItemViewType(position: Int) = if (messages[position].moi) 0 else 1
        override fun isEnabled(position: Int) = false

        override fun getView(position: Int, recyclee: View?, parent: ViewGroup): View {
            val m = messages[position]
            val vue = recyclee ?: if (m.moi) vueMoi() else vueJarvis()
            val p = vue.tag as Porteur
            p.texte.text = m.texte.ifEmpty { if (m.redaction) "…" else "" }
            p.texte.visibility = if (m.texte.isEmpty() && !m.redaction) View.GONE else View.VISIBLE
            p.note?.apply {
                text = m.note
                visibility = if (m.note == null) View.GONE else View.VISIBLE
            }
            p.incident?.apply {
                text = m.incident
                visibility = if (m.incident == null) View.GONE else View.VISIBLE
            }
            return vue
        }

        private fun vueMoi(): View {
            val cadre = LinearLayout(contexte).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.END
                setPadding(dp(40), dp(6), 0, dp(6))
            }
            val note = petitTexte(SECONDAIRE).apply { gravity = Gravity.END }
            cadre.addView(note, LinearLayout.LayoutParams(WRAP, WRAP).apply { gravity = Gravity.END })
            val bulle = TextView(contexte).apply {
                setTextColor(Color.WHITE)
                textSize = 15f
                setPadding(dp(14), dp(9), dp(14), dp(9))
                background = GradientDrawable().apply {
                    cornerRadius = dp(18).toFloat()
                    setColor(SIGNAL)
                }
            }
            cadre.addView(bulle, LinearLayout.LayoutParams(WRAP, WRAP).apply { gravity = Gravity.END })
            cadre.tag = Porteur(bulle, note, null)
            return cadre
        }

        private fun vueJarvis(): View {
            val cadre = LinearLayout(contexte).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, dp(6), dp(12), dp(8))
            }
            val note = petitTexte(SECONDAIRE)
            cadre.addView(note)
            val texte = TextView(contexte).apply {
                setTextColor(TEXTE)
                textSize = 15f
                setLineSpacing(0f, 1.18f)
            }
            cadre.addView(texte)
            val incident = petitTexte(ERREUR)
            cadre.addView(incident)
            cadre.tag = Porteur(texte, note, incident)
            return cadre
        }

        private fun petitTexte(couleur: Int) = TextView(contexte).apply {
            setTextColor(couleur)
            textSize = 12.5f
            setPadding(0, dp(2), 0, dp(2))
        }
    }
}

private const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
private const val WRAP = ViewGroup.LayoutParams.WRAP_CONTENT
