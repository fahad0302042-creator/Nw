package eu.kanade.presentation.feed

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import eu.kanade.presentation.entries.components.ItemCover
import eu.kanade.presentation.util.formatEpisodeNumber
import eu.kanade.tachiyomi.ui.feed.FeedNewEpisodesItem
import eu.kanade.tachiyomi.ui.feed.FeedScreenModel
import tachiyomi.domain.history.anime.model.AnimeHistoryWithRelations
import tachiyomi.i18n.aniyomi.AYMR
import tachiyomi.presentation.core.i18n.stringResource
import tachiyomi.presentation.core.screens.EmptyScreen
import tachiyomi.presentation.core.screens.LoadingScreen

@Composable
fun FeedScreen(
    state: FeedScreenModel.State,
    onAnimeClick: (Long) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
    ) {
        Text(
            text = stringResource(AYMR.strings.label_home_feed),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 20.dp, top = 12.dp, bottom = 4.dp),
        )

        when {
            state.isLoading -> LoadingScreen()
            state.isEmpty -> EmptyScreen(message = stringResource(AYMR.strings.feed_empty_home))
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                if (state.continueWatching.isNotEmpty()) {
                    item(key = "continue-header") {
                        SectionHeader(text = stringResource(AYMR.strings.feed_continue_watching))
                    }
                    item(key = "continue-row") {
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(state.continueWatching) { history ->
                                ContinueWatchingCard(
                                    history = history,
                                    onClick = { onAnimeClick(history.animeId) },
                                )
                            }
                        }
                    }
                }
                if (state.newEpisodes.isNotEmpty()) {
                    item(key = "episodes-header") {
                        SectionHeader(text = stringResource(AYMR.strings.feed_new_episodes))
                    }
                    item(key = "episodes-row") {
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(state.newEpisodes) { item ->
                                NewEpisodesCard(
                                    item = item,
                                    onClick = { onAnimeClick(item.animeId) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 12.dp),
    )
}

@Composable
private fun ContinueWatchingCard(
    history: AnimeHistoryWithRelations,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(220.dp)
            .clip(MaterialTheme.shapes.large)
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
    ) {
        ItemCover.Thumb(
            data = history.coverData,
            contentDescription = history.title,
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth(),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp, start = 4.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.padding(3.dp),
                )
            }
            Text(
                text = stringResource(
                    AYMR.strings.feed_up_next,
                    if (history.episodeNumber > -1) formatEpisodeNumber(history.episodeNumber) else "",
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 6.dp),
            )
        }
        Text(
            text = history.title,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp, start = 4.dp, end = 4.dp),
        )
    }
}

@Composable
private fun NewEpisodesCard(
    item: FeedNewEpisodesItem,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(116.dp)
            .clip(MaterialTheme.shapes.large)
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
    ) {
        ItemCover.Book(
            data = item.coverData,
            contentDescription = item.title,
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = item.title,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 8.dp, start = 4.dp, end = 4.dp),
        )
        Row(
            modifier = Modifier.padding(top = 2.dp, start = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (item.count > 1) {
                Badge { Text(text = "+${item.count}") }
                Spacer(modifier = Modifier.width(4.dp))
            }
            Text(
                text = item.latestEpisodeName ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
