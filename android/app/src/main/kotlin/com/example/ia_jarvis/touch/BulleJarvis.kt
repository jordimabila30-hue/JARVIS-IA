package com.example.ia_jarvis.touch

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator

/**
 * Rendu de la bulle. Phase 1 : rendu simplifié ; un futur rendu PIM
 * (particules) n'aura qu'à implémenter cette interface.
 */
interface RenduBulle {
    val vue: View

    /** Bulle sollicitée : animation discrète. */
    fun eveiller()

    /** Bulle au repos : aucune animation (aucun coût). */
    fun reposer()

    fun liberer()

    /** Vocal flottant réduit : la session continue, la bulle le montre. */
    fun marquerVocal(oui: Boolean)
}

/**
 * Bulle JARVIS dessinée à la main : disque sombre translucide, anneau
 * fin, cœur lumineux qui évoque la particule PIM (respiration lente
 * seulement quand la bulle est sollicitée).
 */
class BulleJarvis(context: Context) : View(context), RenduBulle {

    override val vue: View get() = this

    private val densite = resources.displayMetrics.density

    private val fond = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(214, 28, 26, 38) }
    private val anneau = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = densite
        color = Color.argb(70, 255, 255, 255)
    }
    private val anneauInterieur = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * densite
        color = Color.argb(60, 221, 213, 239)
    }
    private val halo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val marqueVocal = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.5f * densite
        color = Color.rgb(0x7D, 0x8D, 0xF5)
    }
    private var vocal = false
    private val coeur = Paint(Paint.ANTI_ALIAS_FLAG)

    private var phase = 0f
    private val respiration = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1600
        repeatMode = ValueAnimator.REVERSE
        repeatCount = ValueAnimator.INFINITE
        interpolator = AccelerateDecelerateInterpolator()
        addUpdateListener {
            phase = it.animatedValue as Float
            invalidate()
        }
    }

    init {
        contentDescription = "JARVIS Touch"
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        val r = minOf(w, h) / 2f
        halo.shader = RadialGradient(
            w / 2f, h / 2f, r * 0.62f,
            intArrayOf(Color.argb(150, 140, 122, 210), Color.argb(60, 85, 89, 184), Color.TRANSPARENT),
            floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
        )
        coeur.shader = RadialGradient(
            w / 2f, h / 2f, r * 0.34f,
            intArrayOf(Color.WHITE, Color.argb(255, 236, 232, 250), Color.argb(0, 221, 213, 239)),
            floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
        )
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val r = minOf(width, height) / 2f
        canvas.drawCircle(cx, cy, r - densite, fond)
        canvas.drawCircle(cx, cy, r - densite, anneau)
        canvas.drawCircle(cx, cy, r * 0.56f, anneauInterieur)
        val s = 0.9f + 0.14f * phase
        canvas.save()
        canvas.scale(s, s, cx, cy)
        canvas.drawCircle(cx, cy, r * 0.62f, halo)
        canvas.restore()
        canvas.drawCircle(cx, cy, r * 0.34f, coeur)
        if (vocal) canvas.drawCircle(cx, cy, r - 2.5f * densite, marqueVocal)
    }

    override fun marquerVocal(oui: Boolean) {
        vocal = oui
        contentDescription = if (oui) "JARVIS Touch : vocal en cours (toucher pour l’ouvrir)" else "JARVIS Touch"
        invalidate()
    }

    override fun eveiller() {
        if (!respiration.isStarted) respiration.start()
    }

    override fun reposer() {
        respiration.cancel()
        phase = 0f
        invalidate()
    }

    override fun liberer() {
        respiration.removeAllUpdateListeners()
        respiration.cancel()
    }
}
