package eu.kanade.tachiyomi.ui.feed

import androidx.compose.runtime.Immutable
import cafe.adriel.voyager.core.model.StateScreenModel
import cafe.adriel.voyager.core.model.screenModelScope
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import logcat.LogPriority
import tachiyomi.core.common.util.lang.launchIO
import tachiyomi.core.common.util.system.logcat
import tachiyomi.domain.entries.anime.model.AnimeCover
import tachiyomi.domain.history.anime.interactor.GetAnimeHistory
import tachiyomi.domain.history.anime.model.AnimeHistoryWithRelations
import tachiyomi.domain.updates.anime.interactor.GetAnimeUpdates
import tachiyomi.domain.updates.anime.model.AnimeUpdatesWithRelations
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

/**
 * Screen model for the Home feed. Reads existing history and updates data
 * to build "Continue Watching" and "New Episodes" sections. No data is
 * created or modified here.
 */
class FeedScreenModel(
    private val getHistory: GetAnimeHistory = Injekt.get(),
    private val getUpdates: GetAnimeUpdates = Injekt.get(),
) : StateScreenModel<FeedScreenModel.State>(State()) {

    init {
        screenModelScope.launchIO {
            val updatesSince = Instant.now().minus(30, ChronoUnit.DAYS)
            combine(
                getHistory.subscribe(""),
                getUpdates.subscribe(updatesSince),
            ) { history, updates -> history to updates }
                .distinctUntilChanged()
                .catch { error ->
                    logcat(LogPriority.ERROR, error)
                    mutableState.update { it.copy(isLoading = false) }
                }
                .collect { (history, updates) ->
                    mutableState.update {
                        it.copy(
                            isLoading = false,
                            continueWatching = history.toContinueWatching(),
                            newEpisodes = updates.toNewEpisodes(),
                        )
                    }
                }
        }
    }

    /**
     * The most recently watched entry per anime, newest first.
     */
    private fun List<AnimeHistoryWithRelations>.toContinueWatching(): ImmutableList<AnimeHistoryWithRelations> {
        return sortedByDescending { it.seenAt?.time ?: 0L }
            .distinctBy { it.animeId }
            .take(15)
            .toImmutableList()
    }

    /**
     * Unseen episodes from the last month, grouped per anime with a count badge.
     */
    private fun List<AnimeUpdatesWithRelations>.toNewEpisodes(): ImmutableList<FeedNewEpisodesItem> {
        return asSequence()
            .filter { !it.seen }
            .groupBy { it.animeId }
            .map { (animeId, episodes) ->
                FeedNewEpisodesItem(
                    animeId = animeId,
                    title = episodes.first().animeTitle,
                    coverData = episodes.first().coverData,
                    latestEpisodeName = episodes.first().episodeName,
                    count = episodes.size,
                    latestDate = episodes.maxOf { it.dateFetch },
                )
            }
            .sortedByDescending { it.latestDate }
            .take(15)
            .toImmutableList()
    }

    @Immutable
    data class State(
        val isLoading: Boolean = true,
        val continueWatching: ImmutableList<AnimeHistoryWithRelations> = persistentListOf(),
        val newEpisodes: ImmutableList<FeedNewEpisodesItem> = persistentListOf(),
    ) {
        val isEmpty: Boolean
            get() = continueWatching.isEmpty() && newEpisodes.isEmpty()
    }
}

@Immutable
data class FeedNewEpisodesItem(
    val animeId: Long,
    val title: String,
    val coverData: AnimeCover,
    val latestEpisodeName: String?,
    val count: Int,
    val latestDate: Long,
)
