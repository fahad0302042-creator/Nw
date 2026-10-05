package eu.kanade.presentation.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.HoverInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * Indication used on Android TV devices in place of the default touch ripple.
 *
 * Touch ripples are meaningless for D-pad input, which makes remote navigation impossible
 * to follow. Instead, the focused element gets an accent border, a subtle background
 * highlight, and a slight scale-up so the current focus position is obvious from
 * across the room.
 *
 * Applied app-wide through [androidx.compose.foundation.LocalIndication] on TV devices,
 * so every `clickable` / `selectable` / toggleable becomes D-pad friendly without
 * touching its call site.
 */
class TvFocusIndication(
    private val focusColor: Color,
    private val cornerRadius: Dp = 8.dp,
    private val borderWidth: Dp = 3.dp,
) : IndicationNodeFactory {

    override fun create(interactionSource: InteractionSource): Modifier.DelegatingNode {
        return TvFocusIndicationNode(
            interactionSource = interactionSource,
            focusColor = focusColor,
            cornerRadius = cornerRadius,
            borderWidth = borderWidth,
        )
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TvFocusIndication) return false
        return focusColor == other.focusColor &&
            cornerRadius == other.cornerRadius &&
            borderWidth == other.borderWidth
    }

    override fun hashCode(): Int {
        var result = focusColor.hashCode()
        result = 31 * result + cornerRadius.hashCode()
        result = 31 * result + borderWidth.hashCode()
        return result
    }

    private class TvFocusIndicationNode(
        private val interactionSource: InteractionSource,
        private val focusColor: Color,
        private val cornerRadius: Dp,
        private val borderWidth: Dp,
    ) : Modifier.Node(), DrawModifierNode {

        private val animatedScale = Animatable(DefaultScale)
        private var isFocused = false
        private var isPressed = false
        private var isHovered = false

        override fun onAttach() {
            coroutineScope.launch {
                interactionSource.interactions.collect { interaction ->
                    when (interaction) {
                        is FocusInteraction.Focus -> {
                            isFocused = true
                            launch { animatedScale.animateTo(FocusScale, FocusAnimationSpec) }
                            invalidateDraw()
                        }
                        is FocusInteraction.Unfocus -> {
                            isFocused = false
                            launch { animatedScale.animateTo(DefaultScale, FocusAnimationSpec) }
                            invalidateDraw()
                        }
                        is PressInteraction.Press -> {
                            isPressed = true
                            invalidateDraw()
                        }
                        is PressInteraction.Release, is PressInteraction.Cancel -> {
                            isPressed = false
                            invalidateDraw()
                        }
                        is HoverInteraction.Enter -> {
                            isHovered = true
                            invalidateDraw()
                        }
                        is HoverInteraction.Exit -> {
                            isHovered = false
                            invalidateDraw()
                        }
                    }
                }
            }
        }

        override fun ContentDrawScope.draw() {
            val scale = animatedScale.value
            if (scale != DefaultScale) {
                withTransform(
                    transformBlock = {
                        scale(scaleX = scale, scaleY = scale, pivot = center)
                    },
                ) {
                    this@draw.drawContent()
                }
            } else {
                drawContent()
            }

            val corner = CornerRadius(cornerRadius.toPx(), cornerRadius.toPx())
            when {
                isFocused -> {
                    val strokeWidthPx = borderWidth.toPx()
                    val inset = strokeWidthPx / 2f

                    // Soft fill so the focused element stands out from neighbours
                    drawRoundRect(
                        color = focusColor.copy(alpha = FocusFillAlpha),
                        size = size,
                        cornerRadius = corner,
                    )
                    drawRoundRect(
                        color = focusColor,
                        topLeft = Offset(inset, inset),
                        size = Size(size.width - strokeWidthPx, size.height - strokeWidthPx),
                        cornerRadius = corner,
                        style = Stroke(width = strokeWidthPx),
                    )
                }
                isPressed -> {
                    drawRoundRect(
                        color = focusColor.copy(alpha = PressFillAlpha),
                        size = size,
                        cornerRadius = corner,
                    )
                }
                isHovered -> {
                    drawRoundRect(
                        color = focusColor.copy(alpha = HoverFillAlpha),
                        size = size,
                        cornerRadius = corner,
                    )
                }
            }
        }
    }
}

/**
 * Remembers a [TvFocusIndication] tinted with the current theme's accent color.
 */
@Composable
fun rememberTvFocusIndication(color: Color = MaterialTheme.colorScheme.primary): TvFocusIndication {
    return remember(color) { TvFocusIndication(focusColor = color) }
}

private const val DefaultScale = 1f
private const val FocusScale = 1.05f
private const val FocusFillAlpha = 0.12f
private const val PressFillAlpha = 0.16f
private const val HoverFillAlpha = 0.08f
private val FocusAnimationSpec = tween<Float>(durationMillis = 120)
