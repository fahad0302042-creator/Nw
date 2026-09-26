package eu.kanade.presentation.more

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.GetApp
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.QueryStats
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.VideoSettings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.unit.dp
import eu.kanade.domain.ui.model.NavStyle
import eu.kanade.presentation.more.settings.widget.SwitchPreferenceWidget
import eu.kanade.presentation.more.settings.widget.TextPreferenceWidget
import eu.kanade.tachiyomi.R
import eu.kanade.tachiyomi.core.common.Constants
import eu.kanade.tachiyomi.ui.more.DownloadQueueState
import tachiyomi.i18n.MR
import tachiyomi.i18n.aniyomi.AYMR
import tachiyomi.presentation.core.components.ScrollbarLazyColumn
import tachiyomi.presentation.core.components.material.Scaffold
import tachiyomi.presentation.core.i18n.pluralStringResource
import tachiyomi.presentation.core.i18n.stringResource

@Composable
fun MoreScreen(
    downloadQueueStateProvider: () -> DownloadQueueState,
    downloadedOnly: Boolean,
    onDownloadedOnlyChange: (Boolean) -> Unit,
    incognitoMode: Boolean,
    onIncognitoModeChange: (Boolean) -> Unit,
    navStyle: NavStyle,
    onClickAlt: () -> Unit,
    onClickDownloadQueue: () -> Unit,
    onClickCategories: () -> Unit,
    onClickStats: () -> Unit,
    onClickStorage: () -> Unit,
    onClickDataAndStorage: () -> Unit,
    onClickPlayerSettings: () -> Unit,
    onClickSettings: () -> Unit,
    onClickAbout: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current

    Scaffold { contentPadding ->
        ScrollbarLazyColumn(
            modifier = Modifier.padding(contentPadding),
            contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp),
        ) {
            item {
                LogoHeader()
            }
            item {
                SettingsGroupCard {
                    SwitchPreferenceWidget(
                        title = stringResource(MR.strings.label_downloaded_only),
                        subtitle = stringResource(MR.strings.downloaded_only_summary),
                        icon = Icons.Outlined.CloudOff,
                        checked = downloadedOnly,
                        onCheckedChanged = onDownloadedOnlyChange,
                    )
                    SettingsGroupCardDivider()
                    SwitchPreferenceWidget(
                        title = stringResource(MR.strings.pref_incognito_mode),
                        subtitle = stringResource(AYMR.strings.pref_incognito_mode_summary),
                        icon = ImageVector.vectorResource(R.drawable.ic_glasses_24dp),
                        checked = incognitoMode,
                        onCheckedChanged = onIncognitoModeChange,
                    )
                }
            }
            item {
                SettingsGroupCard {
                    TextPreferenceWidget(
                        title = navStyle.moreTab.options.title,
                        icon = navStyle.moreIcon,
                        onPreferenceClick = onClickAlt,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.label_download_queue),
                        subtitle = when (val downloadQueueState = downloadQueueStateProvider()) {
                            DownloadQueueState.Stopped -> null
                            is DownloadQueueState.Paused -> {
                                val pending = downloadQueueState.pending
                                if (pending == 0) {
                                    stringResource(MR.strings.paused)
                                } else {
                                    "${stringResource(MR.strings.paused)} • ${
                                        pluralStringResource(
                                            MR.plurals.download_queue_summary,
                                            count = pending,
                                            pending,
                                        )
                                    }"
                                }
                            }

                            is DownloadQueueState.Downloading -> {
                                val pending = downloadQueueState.pending
                                pluralStringResource(
                                    MR.plurals.download_queue_summary,
                                    count = pending,
                                    pending,
                                )
                            }
                        },
                        icon = Icons.Outlined.GetApp,
                        onPreferenceClick = onClickDownloadQueue,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(AYMR.strings.general_categories),
                        icon = Icons.AutoMirrored.Outlined.Label,
                        onPreferenceClick = onClickCategories,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.label_stats),
                        icon = Icons.Outlined.QueryStats,
                        onPreferenceClick = onClickStats,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.label_data_storage),
                        icon = Icons.Outlined.Storage,
                        onPreferenceClick = onClickDataAndStorage,
                    )
                }
            }
            item {
                SettingsGroupCard {
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.label_settings),
                        icon = Icons.Outlined.Settings,
                        onPreferenceClick = onClickSettings,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(AYMR.strings.label_player_settings),
                        icon = Icons.Outlined.VideoSettings,
                        onPreferenceClick = onClickPlayerSettings,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.pref_category_about),
                        icon = Icons.Outlined.Info,
                        onPreferenceClick = onClickAbout,
                    )
                    SettingsGroupCardDivider()
                    TextPreferenceWidget(
                        title = stringResource(MR.strings.label_help),
                        icon = Icons.AutoMirrored.Outlined.HelpOutline,
                        onPreferenceClick = { uriHandler.openUri(Constants.URL_HELP) },
                    )
                }
            }
        }
    }
}

/**
 * Nw fork: iOS-style grouped inset card for groups of preference rows.
 */
@Composable
private fun SettingsGroupCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(content = content)
    }
}

@Composable
private fun SettingsGroupCardDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(start = 72.dp),
        color = MaterialTheme.colorScheme.outlineVariant,
    )
}
