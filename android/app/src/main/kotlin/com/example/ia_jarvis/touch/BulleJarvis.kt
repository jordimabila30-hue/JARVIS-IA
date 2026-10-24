package com.example.ia_jarvis.touch

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
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
 * Bulle JARVIS dessinée à la main, à l'identité de JARVIS (K1-07) : disque
 * plein dégradé indigo → lavande (couleurs de l'application), trois arcs
 * lumineux façon réacteur (forme « Réacteur Arc » de PIM) et la perle
 * au centre. Rien qui rappelle les anneaux gris d'AssistiveTouch. Respiration
 * lente seulement quand la bulle est sollicitée.
 */
class BulleJarvis(context: Context) : View(context), RenduBulle {

    override val vue: View get() = this

    private val densite = resources.displayMetrics.density

    private val fond = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bord = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = densite
        color = Color.argb(150, 255, 255, 255)
    }
    private val arcs = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.6f * densite
        strokeCap = Paint.Cap.ROUND
        color = Color.argb(235, 236, 232, 255)
    }
    private val cadreArcs = RectF()
    private val halo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val marqueVocal = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2.5f * densite
        color = Color.WHITE
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
        fond.shader = LinearGradient(
            0f, 0f, w.toFloat(), h.toFloat(),
            intArrayOf(Color.rgb(0x4B, 0x4F, 0xB0), Color.rgb(0x8C, 0x7A, 0xD2)),
            null, Shader.TileMode.CLAMP,
        )
        val a = r * 0.6f
        cadreArcs.set(w / 2f - a, h / 2f - a, w / 2f + a, h / 2f + a)
        halo.shader = RadialGradient(
            w / 2f, h / 2f, r * 0.62f,
            intArrayOf(Color.argb(120, 255, 255, 255), Color.argb(40, 236, 232, 255), Color.TRANSPARENT),
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
        canvas.drawCircle(cx, cy, r - densite, bord)
        for (i in 0 until 3) canvas.drawArc(cadreArcs, -90f + 20f + i * 120f, 80f, false, arcs)
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
