package eu.kanade.tachiyomi.util.system

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration

/**
 * Whether the app is running on an Android TV / Google TV device (leanback UI mode).
 *
 * TV UI mode never changes at runtime, so results may safely be cached by callers.
 */
fun Context.isTelevision(): Boolean {
    val uiModeManager = getSystemService(UiModeManager::class.java)
        ?: return false
    return uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
}
