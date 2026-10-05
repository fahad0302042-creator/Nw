package eu.kanade.presentation.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalContext
import eu.kanade.tachiyomi.util.system.isTelevision

/**
 * Whether the app is currently running on an Android TV device and should present its
 * D-pad friendly TV experience (always-visible navigation rail, visible focus indication,
 * remote-key handling, etc.).
 *
 * Unlike [isTabletUi], this is driven by the device UI mode rather than screen size:
 * 1080p televisions also report a large smallestScreenWidthDp, so the two usually agree,
 * but only this one guarantees leanback behavior.
 *
 * The result (from [isTelevision]) is cached for the process, so calling this during
 * composition is cheap.
 */
@Composable
@ReadOnlyComposable
fun isTvUi(): Boolean {
    return LocalContext.current.isTelevision()
}
