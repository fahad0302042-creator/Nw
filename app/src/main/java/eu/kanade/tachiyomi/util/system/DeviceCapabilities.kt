package eu.kanade.tachiyomi.util.system

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration

private var cachedIsTelevision: Boolean? = null

/**
 * Whether the app is running on an Android TV / Google TV device (leanback UI mode).
 *
 * TV UI mode never changes at runtime, so the result is cached for the process
 * (this gets called during composition).
 */
fun Context.isTelevision(): Boolean {
    cachedIsTelevision?.let { return it }

    val uiModeManager = getSystemService(UiModeManager::class.java)
        ?: return false

    val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    cachedIsTelevision = isTv
    return isTv
}
