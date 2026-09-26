package eu.kanade.presentation.theme.colorscheme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

/**
 * Colors for the Nw theme — iOS-inspired system palette.
 *
 * Light: grouped background #F2F2F7, iOS blue #007AFF.
 * Dark: true black background with elevated #1C1C1E surfaces, iOS blue #0A84FF.
 */
internal object NwColorScheme : BaseColorScheme() {

    override val darkScheme = darkColorScheme(
        primary = Color(0xFF0A84FF),
        onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFF004E8C),
        onPrimaryContainer = Color(0xFFB3DAFF),
        inversePrimary = Color(0xFF007AFF),
        secondary = Color(0xFF7D7AFF),
        onSecondary = Color(0xFFFFFFFF),
        secondaryContainer = Color(0xFF2E2E70),
        onSecondaryContainer = Color(0xFFD8D8FF),
        tertiary = Color(0xFFFFB340),
        onTertiary = Color(0xFF3F2D00),
        tertiaryContainer = Color(0xFF5A3D00),
        onTertiaryContainer = Color(0xFFFFDFA6),
        background = Color(0xFF000000),
        onBackground = Color(0xFFF2F2F7),
        surface = Color(0xFF1C1C1E),
        onSurface = Color(0xFFF2F2F7),
        surfaceVariant = Color(0xFF2C2C2E),
        onSurfaceVariant = Color(0xFFAEAEB2),
        surfaceTint = Color(0xFF0A84FF),
        inverseSurface = Color(0xFFF2F2F7),
        inverseOnSurface = Color(0xFF2C2C2E),
        outline = Color(0xFF48484A),
        outlineVariant = Color(0xFF3A3A3C),
        error = Color(0xFFFF453A),
        onError = Color(0xFFFFFFFF),
        errorContainer = Color(0xFF670003),
        onErrorContainer = Color(0xFFFFDAD6),
    )

    override val lightScheme = lightColorScheme(
        primary = Color(0xFF007AFF),
        onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFFD6E9FF),
        onPrimaryContainer = Color(0xFF003B71),
        inversePrimary = Color(0xFF0A84FF),
        secondary = Color(0xFF5856D6),
        onSecondary = Color(0xFFFFFFFF),
        secondaryContainer = Color(0xFFE5E4FA),
        onSecondaryContainer = Color(0xFF1B1A5E),
        tertiary = Color(0xFFFF9500),
        onTertiary = Color(0xFFFFFFFF),
        tertiaryContainer = Color(0xFFFFE8CC),
        onTertiaryContainer = Color(0xFF5A3D00),
        background = Color(0xFFF2F2F7),
        onBackground = Color(0xFF1C1C1E),
        surface = Color(0xFFFFFFFF),
        onSurface = Color(0xFF1C1C1E),
        surfaceVariant = Color(0xFFE5E5EA),
        onSurfaceVariant = Color(0xFF6D6D72),
        surfaceTint = Color(0xFF007AFF),
        inverseSurface = Color(0xFF3A3A3C),
        inverseOnSurface = Color(0xFFF2F2F7),
        outline = Color(0xFFC6C6C8),
        outlineVariant = Color(0xFFE5E5EA),
        error = Color(0xFFFF3B30),
        onError = Color(0xFFFFFFFF),
        errorContainer = Color(0xFFFFDAD6),
        onErrorContainer = Color(0xFF410002),
    )
}
