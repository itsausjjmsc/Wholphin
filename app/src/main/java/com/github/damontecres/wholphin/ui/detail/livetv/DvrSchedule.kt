package com.github.damontecres.wholphin.ui.detail.livetv

import android.text.format.DateUtils
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.tv.material3.ListItem
import androidx.tv.material3.ListItemDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.tv.material3.surfaceColorAtElevation
import com.github.damontecres.wholphin.R
import com.github.damontecres.wholphin.data.model.BaseItem
import com.github.damontecres.wholphin.services.NavigationManager
import com.github.damontecres.wholphin.ui.SlimItemFields
import com.github.damontecres.wholphin.ui.components.ErrorMessage
import com.github.damontecres.wholphin.ui.components.LoadingPage
import com.github.damontecres.wholphin.ui.launchIO
import com.github.damontecres.wholphin.ui.nav.Destination
import com.github.damontecres.wholphin.ui.seasonEpisode
import com.github.damontecres.wholphin.ui.tryRequestFocus
import com.github.damontecres.wholphin.util.DataLoadingState
import com.github.damontecres.wholphin.util.ExceptionHandler
import com.github.damontecres.wholphin.util.LoadingState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.jellyfin.sdk.api.client.ApiClient
import org.jellyfin.sdk.api.client.extensions.liveTvApi
import timber.log.Timber
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import javax.inject.Inject

@HiltViewModel
class DvrScheduleViewModel
    @Inject
    constructor(
        private val api: ApiClient,
        val navigationManager: NavigationManager,
    ) : ViewModel() {
        private val _state = MutableStateFlow(DvrScheduleState())
        val state: StateFlow<DvrScheduleState> = _state

        init {
            init()
        }

        fun init() {
            viewModelScope.launchIO {
                try {
                    val active =
                        api.liveTvApi
                            .getRecordings(
                                isInProgress = true,
                                fields = SlimItemFields,
                                limit = 100,
                            ).content.items
                            .map { BaseItem.from(it, api, true) }
                    val scheduled =
                        api.liveTvApi
                            .getTimers(
                                isActive = false,
                                isScheduled = true,
                            ).content.items
                            .mapNotNull { timer ->
                                timer.startDate?.let { startDate ->
                                    timer.id?.toString()?.let { timerId ->
                                        ScheduledRecording(
                                            timerId = timerId,
                                            seriesTimerId = timer.seriesTimerId?.toString(),
                                            name = timer.name,
                                            startDate = startDate,
                                            endDate = timer.endDate,
                                            program = timer.programInfo?.let { BaseItem.from(it, api, true) },
                                        )
                                    }
                                }
                            }.groupBy { it.startDate.toLocalDate() }

                    _state.update {
                        it.copy(
                            loading = LoadingState.Success,
                            active = active,
                            scheduled = scheduled,
                        )
                    }
                } catch (ex: Exception) {
                    Timber.e(ex, "Error fetching DVR schedule")
                    _state.update { it.copy(loading = LoadingState.Error(ex)) }
                }
            }
        }

        fun cancelRecording(
            timerId: String,
            series: Boolean,
        ) {
            viewModelScope.launchIO(ExceptionHandler(autoToast = true)) {
                if (series) {
                    api.liveTvApi.cancelSeriesTimer(timerId)
                } else {
                    api.liveTvApi.cancelTimer(timerId)
                }
                init()
            }
        }
    }

data class ScheduledRecording(
    val timerId: String,
    val seriesTimerId: String?,
    val name: String?,
    val startDate: LocalDateTime,
    val endDate: LocalDateTime?,
    val program: BaseItem?,
)

data class DvrScheduleState(
    val loading: LoadingState = LoadingState.Loading,
    val active: List<BaseItem> = emptyList(),
    val scheduled: Map<LocalDate, List<ScheduledRecording>> = emptyMap(),
)

@Composable
fun DvrSchedule(
    requestFocusAfterLoading: Boolean,
    focusRequesterOnEmpty: FocusRequester,
    modifier: Modifier = Modifier,
    viewModel: DvrScheduleViewModel = hiltViewModel(),
) {
    LaunchedEffect(Unit) {
        viewModel.init()
    }
    val state by viewModel.state.collectAsState()
    when (val st = state.loading) {
        is LoadingState.Error -> {
            ErrorMessage(st, modifier)
        }

        LoadingState.Loading,
        LoadingState.Pending,
        -> {
            LoadingPage(modifier)
        }

        LoadingState.Success -> {
            var showDialog by remember { mutableStateOf<ScheduledRecording?>(null) }
            val focusRequester = remember { FocusRequester() }
            if (requestFocusAfterLoading) {
                LaunchedEffect(Unit) {
                    if (state.active.isNotEmpty() || state.scheduled.isNotEmpty()) {
                        focusRequester.tryRequestFocus()
                    } else {
                        focusRequesterOnEmpty.tryRequestFocus()
                    }
                }
            }
            DvrScheduleContent(
                activeRecordings = state.active,
                scheduledRecordings = state.scheduled,
                onClickItem = {
                    if (it.program != null) {
                        showDialog = it
                    } else {
                        viewModel.cancelRecording(
                            it.seriesTimerId ?: it.timerId,
                            it.seriesTimerId != null,
                        )
                    }
                },
                modifier =
                    modifier
                        .focusRequester(focusRequester),
            )
            showDialog?.let { recording ->
                val context = LocalContext.current
                val program = recording.program ?: return@let
                ProgramDialog(
                    state = DataLoadingState.Success(program),
                    canRecord = true,
                    onDismissRequest = {
                        showDialog = null
                    },
                    onWatch = { program ->
                        val channelId = program.data.channelId
                        if (channelId != null) {
                            viewModel.navigationManager.navigateTo(
                                Destination.Playback(
                                    itemId = channelId,
                                    positionMs = 0L,
                                ),
                            )
                        } else {
                            Toast
                                .makeText(context, "Program has no channel ID", Toast.LENGTH_LONG)
                                .show()
                        }
                    },
                    onRecord = { _, _ ->
                        // no-op
                    },
                    onCancelRecord = { _, series ->
                        showDialog = null
                        viewModel.cancelRecording(
                            if (series) recording.seriesTimerId ?: recording.timerId else recording.timerId,
                            series,
                        )
                    },
                )
            }
        }
    }
}

@Composable
fun DvrScheduleContent(
    activeRecordings: List<BaseItem>,
    scheduledRecordings: Map<LocalDate, List<ScheduledRecording>>,
    onClickItem: (ScheduledRecording) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Box(
        contentAlignment = Alignment.TopCenter,
        modifier = modifier,
    ) {
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier =
                Modifier
                    .fillMaxWidth(.6f)
                    .background(MaterialTheme.colorScheme.surface),
        ) {
            if (activeRecordings.isEmpty() && scheduledRecordings.isEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.no_scheduled_recordings),
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (activeRecordings.isNotEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.active_recordings),
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                items(activeRecordings) { item ->
                    Recording(
                        recording = ScheduledRecording(
                            timerId = item.data.timerId ?: "",
                            seriesTimerId = item.data.seriesTimerId,
                            name = item.title,
                            startDate = item.data.startDate ?: LocalDateTime.now(),
                            endDate = item.data.endDate,
                            program = item,
                        ),
                        onClick = {
                            onClickItem.invoke(
                                ScheduledRecording(
                                    timerId = item.data.timerId ?: "",
                                    seriesTimerId = item.data.seriesTimerId,
                                    name = item.title,
                                    startDate = item.data.startDate ?: LocalDateTime.now(),
                                    endDate = item.data.endDate,
                                    program = item,
                                ),
                            )
                        },
                        modifier = Modifier,
                    )
                }
            }
            scheduledRecordings.keys.sorted().forEach { date ->
                val formattedDate =
                    DateUtils.formatDateTime(
                        context,
                        date
                            .atStartOfDay(ZoneId.systemDefault())
                            .toInstant()
                            .epochSecond * 1000,
                        DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_DATE,
                    )
                item {
                    Text(
                        text = formattedDate,
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                val programs = scheduledRecordings[date].orEmpty()
                items(programs) { recording ->
                    Recording(
                        recording = recording,
                        onClick = { onClickItem.invoke(recording) },
                        modifier = Modifier,
                    )
                }
            }
        }
    }
}

@Composable
fun Recording(
    recording: ScheduledRecording,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val item = recording.program
    ListItem(
        selected = false,
        onClick = onClick,
        modifier = modifier,
        colors =
            ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceColorAtElevation(1.dp),
            ),
        leadingContent = {
            // TODO
//                        AsyncImage(
//                            model = item.imageUrl,
//                            contentDescription = null,
//                        )
        },
        headlineContent = {
            Text(
                text = item?.title ?: recording.name ?: "",
            )
        },
        supportingContent = {
            if (item?.data?.isSeries ?: false) {
                listOfNotNull(
                    item.data.seasonEpisode,
                    item.data.episodeTitle,
                ).joinToString(" - ")
                    .ifBlank { null }
                    ?.let {
                        Text(
                            text = it,
                            modifier = Modifier,
                        )
                    }
            }
        },
        trailingContent = {
            val time =
                DateUtils.formatDateRange(
                    context,
                    recording.startDate
                        .atZone(ZoneId.systemDefault())
                        .toInstant()
                        .epochSecond * 1000,
                    recording.endDate
                        ?.atZone(ZoneId.systemDefault())
                        ?.toInstant()
                        ?.epochSecond
                        ?.times(1000)
                        ?: recording.startDate
                            .atZone(ZoneId.systemDefault())
                            .toInstant()
                            .epochSecond * 1000,
                    DateUtils.FORMAT_SHOW_TIME,
                )
            Text(
                text = time,
            )
        },
    )
}
