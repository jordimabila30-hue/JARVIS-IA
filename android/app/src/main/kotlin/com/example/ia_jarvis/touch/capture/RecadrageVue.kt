package com.example.ia_jarvis.touch.capture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Sélection rectangulaire sur une capture, active dès l'ouverture : l'image
 * est affichée entière (proportions gardées), la zone retenue reste nette,
 * le reste est assombri. Glisser un coin ou un bord ajuste la zone, glisser
 * l'intérieur la déplace ; une grille 3 × 3 n'apparaît que pendant le geste.
 * Double-toucher (sans glisser) : retour à l'image entière.
 *
 * La zone est tenue en pixels de l'IMAGE (jamais hors d'elle, jamais plus
 * petite que [minimum]) ; seul le dessin bouge pendant le geste : aucune
 * image n'est recadrée ni allouée avant la validation.
 * Un geste complet = UNE modification ([surModification], pour
 * l'historique Annuler / Rétablir).
 */
@SuppressLint("ViewConstructor")
class RecadrageVue(contexte: Context, private val image: Bitmap) : View(contexte) {

    /** Fin d'un geste qui a changé la zone : (avant, après), en pixels de l'image. */
    var surModification: ((RectF, RectF) -> Unit)? = null

    private val densite = resources.displayMetrics.density
    private val marge = 18 * densite
    private val portee = 28 * densite
    private val seuil = ViewConfiguration.get(contexte).scaledTouchSlop

    private val entiere = RectF(0f, 0f, image.width.toFloat(), image.height.toFloat())
    private val zone = RectF(entiere)
    private val zoneAuDepart = RectF()
    private val cadre = RectF()
    private val s = RectF() // zone à l'écran, réutilisée (aucune allocation au dessin)
    private var echelle = 1f

    private val peintureImage = Paint(Paint.FILTER_BITMAP_FLAG)
    private val voile = Paint().apply { color = Color.argb(165, 6, 5, 12) }
    private val bord = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * densite
        color = Color.argb(230, 255, 255, 255)
    }
    private val grille = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = densite
        color = Color.argb(110, 255, 255, 255)
    }
    private val poignee = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 4 * densite
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }

    // Côtés saisis (gauche, haut, droite, bas) ; tous : déplacement.
    private var g = false
    private var h = false
    private var d = false
    private var b = false
    private var enGeste = false
    private var aBouge = false
    private var departX = 0f
    private var departY = 0f
    private var dernierX = 0f
    private var dernierY = 0f

    private val doubleToucher = GestureDetector(contexte, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTapEvent(e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_UP && !aBouge) reinitialiser()
            return true
        }
    })

    /** Plus petite zone, en pixels de l'image (≈ 48 dp à l'écran, au moins 16 px). */
    private val minimum: Float get() = maxOf(16f, 48 * densite / echelle)

    /** Zone choisie, en pixels entiers de l'image. */
    fun zoneChoisie(): Rect = Rect(
        zone.left.roundToInt().coerceIn(0, image.width - 1),
        zone.top.roundToInt().coerceIn(0, image.height - 1),
        zone.right.roundToInt().coerceIn(1, image.width),
        zone.bottom.roundToInt().coerceIn(1, image.height),
    )

    /** Zone imposée (Annuler / Rétablir) : aucune modification signalée. */
    fun definir(r: RectF) {
        zone.set(r)
        invalidate()
    }

    /** Double-toucher : image entière (une modification, si elle change quelque chose). */
    private fun reinitialiser() {
        if (zone == entiere) return
        val avant = RectF(zone)
        zone.set(entiere)
        invalidate()
        surModification?.invoke(avant, RectF(zone))
    }

    override fun onSizeChanged(w: Int, hauteur: Int, ow: Int, oh: Int) {
        val dispoL = w - 2 * marge
        val dispoH = hauteur - 2 * marge
        echelle = minOf(dispoL / image.width, dispoH / image.height).coerceAtLeast(0.0001f)
        val lw = image.width * echelle
        val lh = image.height * echelle
        cadre.set((w - lw) / 2, (hauteur - lh) / 2, (w + lw) / 2, (hauteur + lh) / 2)
    }

    override fun onDraw(canvas: Canvas) {
        if (image.isRecycled) return
        canvas.drawBitmap(image, null, cadre, peintureImage)
        versEcran()
        // Voile hors de la zone (quatre bandes : aucun calque hors écran).
        canvas.drawRect(cadre.left, cadre.top, cadre.right, s.top, voile)
        canvas.drawRect(cadre.left, s.bottom, cadre.right, cadre.bottom, voile)
        canvas.drawRect(cadre.left, s.top, s.left, s.bottom, voile)
        canvas.drawRect(s.right, s.top, cadre.right, s.bottom, voile)
        if (enGeste) {
            for (i in 1..2) {
                val x = s.left + s.width() * i / 3
                val y = s.top + s.height() * i / 3
                canvas.drawLine(x, s.top, x, s.bottom, grille)
                canvas.drawLine(s.left, y, s.right, y, grille)
            }
        }
        canvas.drawRect(s, bord)
        val l = minOf(20 * densite, s.width() / 3, s.height() / 3)
        coin(canvas, s.left, s.top, l, l)
        coin(canvas, s.right, s.top, -l, l)
        coin(canvas, s.left, s.bottom, l, -l)
        coin(canvas, s.right, s.bottom, -l, -l)
        // Repères au milieu des bords (ajustement d'un seul côté).
        val m = minOf(12 * densite, s.width() / 6, s.height() / 6)
        canvas.drawLine(s.centerX() - m, s.top, s.centerX() + m, s.top, poignee)
        canvas.drawLine(s.centerX() - m, s.bottom, s.centerX() + m, s.bottom, poignee)
        canvas.drawLine(s.left, s.centerY() - m, s.left, s.centerY() + m, poignee)
        canvas.drawLine(s.right, s.centerY() - m, s.right, s.centerY() + m, poignee)
    }

    private fun coin(c: Canvas, x: Float, y: Float, dx: Float, dy: Float) {
        c.drawLine(x, y, x + dx, y, poignee)
        c.drawLine(x, y, x, y + dy, poignee)
    }

    private fun versEcran() {
        s.set(
            cadre.left + zone.left * echelle, cadre.top + zone.top * echelle,
            cadre.left + zone.right * echelle, cadre.top + zone.bottom * echelle,
        )
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        doubleToucher.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                versEcran()
                val x = e.x
                val y = e.y
                val dansY = y > s.top - portee && y < s.bottom + portee
                val dansX = x > s.left - portee && x < s.right + portee
                g = dansY && abs(x - s.left) < portee
                d = dansY && !g && abs(x - s.right) < portee
                h = dansX && abs(y - s.top) < portee
                b = dansX && !h && abs(y - s.bottom) < portee
                if (!(g || d || h || b)) {
                    // Intérieur : déplacement ; dehors : rien (le double-toucher reste possible).
                    val dedans = s.contains(x, y)
                    g = dedans; d = dedans; h = dedans; b = dedans
                }
                aBouge = false
                departX = x
                departY = y
                dernierX = x
                dernierY = y
                zoneAuDepart.set(zone)
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (!aBouge && hypot(e.x - departX, e.y - departY) > seuil) {
                    aBouge = true
                    // On reprend depuis le point de départ : rien n'est perdu sous le seuil.
                    dernierX = departX
                    dernierY = departY
                }
                if (!aBouge || !(g || d || h || b)) return true
                enGeste = true
                val dx = (e.x - dernierX) / echelle
                val dy = (e.y - dernierY) / echelle
                dernierX = e.x
                dernierY = e.y
                if (g && d && h && b) deplacer(dx, dy) else ajuster(dx, dy)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val modifiee = aBouge && zone != zoneAuDepart
                g = false; d = false; h = false; b = false
                if (enGeste) {
                    enGeste = false
                    invalidate()
                }
                if (modifiee) surModification?.invoke(RectF(zoneAuDepart), RectF(zone))
                return true
            }
        }
        return true
    }

    private fun deplacer(dx: Float, dy: Float) {
        val mx = dx.coerceIn(-zone.left, image.width - zone.right)
        val my = dy.coerceIn(-zone.top, image.height - zone.bottom)
        zone.offset(mx, my)
    }

    private fun ajuster(dx: Float, dy: Float) {
        val m = minOf(minimum, image.width.toFloat(), image.height.toFloat())
        if (g) zone.left = (zone.left + dx).coerceIn(0f, zone.right - m)
        if (d) zone.right = (zone.right + dx).coerceIn(zone.left + m, image.width.toFloat())
        if (h) zone.top = (zone.top + dy).coerceIn(0f, zone.bottom - m)
        if (b) zone.bottom = (zone.bottom + dy).coerceIn(zone.top + m, image.height.toFloat())
    }
}
