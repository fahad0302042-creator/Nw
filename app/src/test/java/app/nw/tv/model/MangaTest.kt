package app.nw.tv.model

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MangaTest {
    private val color = Color(0xFF000000)

    @Test
    fun progressIsClampedAndParsed() {
        assertEquals(62, Manga("A", "", color, "62%").progressPercent)
        assertEquals(0, Manga("A", "", color, "unknown").progressPercent)
        assertEquals(100, Manga("A", "", color, "140%").progressPercent)
    }

    @Test
    fun onlyPartiallyReadEntriesAreResumable() {
        assertTrue(Manga("A", "", color, "62%").isResumable())
        assertFalse(Manga("B", "", color).isResumable())
        assertFalse(Manga("C", "", color, "100%").isResumable())
    }
}
