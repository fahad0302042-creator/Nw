package eu.kanade.presentation.util

import androidx.compose.foundation.focusable
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import eu.kanade.presentation.components.rememberTvFocusIndication

/**
 * Makes a non-interactive element reachable with a TV remote (D-pad) and gives it the TV
 * focus indicator (accent border + subtle scale/highlight).
 *
 * On non-TV devices this modifier is a no-op.
 *
 * Prefer this over plain [focusable] on TV-only composables: interactive elements that
 * already use `clickable`/`selectable` get their focus indicator from
 * `LocalIndication` (see `eu.kanade.presentation.theme.TachiyomiTheme`), so this is only
 * needed for otherwise-static content that must be D-pad reachable.
 */
fun Modifier.tvFocusable(enabled: Boolean = true): Modifier = composed {
    if (!isTvUi()) return@composed this

    val interactionSource = remember { MutableInteractionSource() }
    val indication = rememberTvFocusIndication()

    this
        .indication(indication = indication, interactionSource = interactionSource)
        .focusable(interactionSource = interactionSource, enabled = enabled)
}
