package app.nw.tv.model

import androidx.compose.ui.graphics.Color

/** A source-agnostic manga entry shared by the TV UI and future Mihon data adapter. */
data class Manga(
    val title: String,
    val subtitle: String,
    val color: Color,
    val progress: String = ""
) {
    val progressPercent: Int
        get() = progress.removeSuffix("%").toIntOrNull()?.coerceIn(0, 100) ?: 0
}

/** Keeps the reader's resume action deterministic and easy to test. */
fun Manga.isResumable(): Boolean = progressPercent in 1..99
