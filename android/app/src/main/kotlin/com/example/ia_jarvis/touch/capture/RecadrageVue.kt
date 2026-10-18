package com.example.ia_jarvis.touch.capture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Sélection rectangulaire sur une capture : l'image est affichée entière
 * (proportions gardées), la zone retenue reste claire, le reste est voilé.
 * Glisser un coin ou un bord ajuste la zone, glisser l'intérieur la
 * déplace. La zone est tenue en pixels de l'IMAGE (jamais hors d'elle,
 * jamais plus petite que [minimum]) : le recadrage se fait en pleine
 * résolution, quelle que soit la taille d'affichage.
 */
@SuppressLint("ViewConstructor")
class RecadrageVue(contexte: Context, private val image: Bitmap, depart: Rect?) : View(contexte) {

    private val densite = resources.displayMetrics.density
    private val marge = 14 * densite
    private val portee = 26 * densite

    /** Zone en pixels de l'image. */
    private val zone = RectF(depart ?: Rect(0, 0, image.width, image.height))
    private val cadre = RectF()
    private var echelle = 1f

    private val peintureImage = Paint(Paint.FILTER_BITMAP_FLAG)
    private val voile = Paint().apply { color = Color.argb(150, 12, 10, 20) }
    private val bord = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2 * densite
        color = Color.WHITE
    }
    private val grille = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = densite
        color = Color.argb(90, 255, 255, 255)
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
    private var dernierX = 0f
    private var dernierY = 0f

    /** Plus petite zone, en pixels de l'image (≈ 40 dp à l'écran, au moins 16 px). */
    private val minimum: Float get() = maxOf(16f, 40 * densite / echelle)

    /** Zone choisie, en pixels entiers de l'image. */
    fun zoneChoisie(): Rect = Rect(
        zone.left.roundToInt().coerceIn(0, image.width - 1),
        zone.top.roundToInt().coerceIn(0, image.height - 1),
        zone.right.roundToInt().coerceIn(1, image.width),
        zone.bottom.roundToInt().coerceIn(1, image.height),
    )

    /** « Tout » : l'image entière. */
    fun toutSelectionner() {
        zone.set(0f, 0f, image.width.toFloat(), image.height.toFloat())
        invalidate()
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
        val s = ecran(zone)
        // Voile hors de la zone (quatre bandes : aucun calque hors écran).
        canvas.drawRect(cadre.left, cadre.top, cadre.right, s.top, voile)
        canvas.drawRect(cadre.left, s.bottom, cadre.right, cadre.bottom, voile)
        canvas.drawRect(cadre.left, s.top, s.left, s.bottom, voile)
        canvas.drawRect(s.right, s.top, cadre.right, s.bottom, voile)
        // Tiers, bord, coins.
        for (i in 1..2) {
            val x = s.left + s.width() * i / 3
            val y = s.top + s.height() * i / 3
            canvas.drawLine(x, s.top, x, s.bottom, grille)
            canvas.drawLine(s.left, y, s.right, y, grille)
        }
        canvas.drawRect(s, bord)
        val l = minOf(18 * densite, s.width() / 3, s.height() / 3)
        coin(canvas, s.left, s.top, l, l)
        coin(canvas, s.right, s.top, -l, l)
        coin(canvas, s.left, s.bottom, l, -l)
        coin(canvas, s.right, s.bottom, -l, -l)
    }

    private fun coin(c: Canvas, x: Float, y: Float, dx: Float, dy: Float) {
        c.drawLine(x, y, x + dx, y, poignee)
        c.drawLine(x, y, x, y + dy, poignee)
    }

    private fun ecran(r: RectF) = RectF(
        cadre.left + r.left * echelle, cadre.top + r.top * echelle,
        cadre.left + r.right * echelle, cadre.top + r.bottom * echelle,
    )

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val s = ecran(zone)
                val x = e.x
                val y = e.y
                val dansY = y > s.top - portee && y < s.bottom + portee
                val dansX = x > s.left - portee && x < s.right + portee
                g = dansY && abs(x - s.left) < portee
                d = dansY && !g && abs(x - s.right) < portee
                h = dansX && abs(y - s.top) < portee
                b = dansX && !h && abs(y - s.bottom) < portee
                if (!(g || d || h || b)) {
                    // Intérieur : déplacement ; dehors : rien.
                    val dedans = s.contains(x, y)
                    g = dedans; d = dedans; h = dedans; b = dedans
                    if (!dedans) return false
                }
                dernierX = x
                dernierY = y
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = (e.x - dernierX) / echelle
                val dy = (e.y - dernierY) / echelle
                dernierX = e.x
                dernierY = e.y
                if (g && d && h && b) deplacer(dx, dy) else ajuster(dx, dy)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                g = false; d = false; h = false; b = false
                return true
            }
        }
        return false
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
