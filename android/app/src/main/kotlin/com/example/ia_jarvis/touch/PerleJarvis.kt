package com.example.ia_jarvis.touch

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.max

/**
 * Perle JARVIS, la même que dans l'application (Dart :
 * `lib/widgets/conversation/signature_jarvis.dart`, `_PerleJarvis`) :
 * halo ivoire-lavande, sphère bleu-violet éclairée en haut à gauche avec
 * un reflet pêche, anneau blanc ouvert. Identité de JARVIS Touch (bulle,
 * vocal flottant) à la place de tout symbole générique.
 */
class PerleJarvis {
    private val halo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val sphere = Paint(Paint.ANTI_ALIAS_FLAG)
    private val anneau = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.argb(0xF2, 0xFF, 0xFF, 0xFF)
    }
    private val arc = RectF()
    private var cx = Float.NaN
    private var cy = Float.NaN
    private var r = Float.NaN

    /** Dessine la perle de rayon [rayon] centrée en ([x], [y]). */
    fun dessiner(c: Canvas, x: Float, y: Float, rayon: Float, avecHalo: Boolean = true) {
        if (x != cx || y != cy || rayon != r) preparer(x, y, rayon)
        if (avecHalo) c.drawCircle(x, y, rayon, halo)
        val rs = rayon * 0.68f
        c.drawCircle(x, y, rs, sphere)
        val ra = rs * 0.48f
        anneau.strokeWidth = max(0.8f, rayon * 0.13f)
        arc.set(x - ra, y - ra, x + ra, y + ra)
        // −0,42 π puis 1,4 π (radians) → degrés.
        c.drawArc(arc, -75.6f, 252f, false, anneau)
    }

    private fun preparer(x: Float, y: Float, rayon: Float) {
        cx = x
        cy = y
        r = rayon
        halo.shader = RadialGradient(
            x, y, rayon,
            intArrayOf(Color.argb(0xF2, 0xFB, 0xF8, 0xFF), Color.argb(0xCC, 0xF1, 0xEC, 0xFA), Color.argb(0, 0xF1, 0xEC, 0xFA)),
            floatArrayOf(0.55f, 0.8f, 1f), Shader.TileMode.CLAMP,
        )
        val rs = rayon * 0.68f
        sphere.shader = RadialGradient(
            x - 0.45f * rs, y - 0.5f * rs, 1.15f * rs,
            intArrayOf(
                Color.rgb(0xDC, 0xE6, 0xFE), Color.rgb(0xAA, 0xB6, 0xF8), Color.rgb(0x93, 0x98, 0xEC),
                Color.rgb(0xB9, 0xAD, 0xEE), Color.rgb(0xF6, 0xDE, 0xD8),
            ),
            floatArrayOf(0f, 0.32f, 0.62f, 0.86f, 1f), Shader.TileMode.CLAMP,
        )
    }
}
