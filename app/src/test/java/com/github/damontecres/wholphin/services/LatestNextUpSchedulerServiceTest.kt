package com.github.damontecres.wholphin.services

import androidx.appcompat.app.AppCompatActivity
import androidx.arch.core.executor.testing.InstantTaskExecutorRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.github.damontecres.wholphin.data.CurrentUser
import com.github.damontecres.wholphin.data.ServerRepository
import com.github.damontecres.wholphin.data.model.JellyfinServer
import com.github.damontecres.wholphin.data.model.JellyfinUser
import com.github.damontecres.wholphin.util.WholphinDispatchers
import com.github.damontecres.wholphin.util.configure
import com.github.damontecres.wholphin.util.reset
import com.google.common.util.concurrent.ListenableFuture
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.util.UUID

@OptIn(ExperimentalCoroutinesApi::class)
class LatestNextUpSchedulerServiceTest {
    @get:Rule val instantTaskExecutorRule = InstantTaskExecutorRule()
    private val testDispatcher = StandardTestDispatcher()
    private val currentUser = MutableStateFlow<CurrentUser?>(null)
    private val mockActivity = mockk<AppCompatActivity>(relaxed = true)
    private val mockServerRepository = mockk<ServerRepository>(relaxed = true)
    private val mockWorkManager = mockk<WorkManager>(relaxed = true)
    private val lifecycleRegistry = LifecycleRegistry(mockk<LifecycleOwner>(relaxed = true))

    @Before
    fun setUp() {
        WholphinDispatchers.configure(testDispatcher)
        every { mockActivity.lifecycle } returns lifecycleRegistry
        every { mockServerRepository.current } returns currentUser
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
    }

    @After
    fun tearDown() = WholphinDispatchers.reset()

    private fun createService() =
        LatestNextUpSchedulerService(
            context = mockActivity,
            serverRepository = mockServerRepository,
            workManager = mockWorkManager,
        ).also {
            it.dispatcher = testDispatcher
        }

    @Test
    fun cancels_latestNextUp_work_when_user_null() =
        runTest(testDispatcher) {
            createService()

            currentUser.value = null
            advanceUntilIdle()

            verify { mockWorkManager.cancelUniqueWork(LatestNextUpWorker.WORK_NAME) }
            verify(exactly = 0) { mockWorkManager.cancelUniqueWork(SuggestionsWorker.WORK_NAME) }
        }

    private fun mockWorkInfos(infos: List<WorkInfo>) {
        val future = mockk<ListenableFuture<List<WorkInfo>>>()
        every { future.get() } returns infos
        every { mockWorkManager.getWorkInfosForUniqueWork(LatestNextUpWorker.WORK_NAME) } returns future
    }

    private fun currentUser(userId: UUID) =
        CurrentUser(
            user = JellyfinUser(id = userId, name = "User", serverId = UUID.randomUUID(), accessToken = "token"),
            server = JellyfinServer(id = UUID.randomUUID(), name = "Server", url = "http://localhost", version = null),
        )

    @Test
    fun schedules_work_when_user_present() =
        runTest(testDispatcher) {
            mockWorkInfos(emptyList())
            createService()

            currentUser.value = currentUser(UUID.randomUUID())
            advanceUntilIdle()

            verify(exactly = 1) { mockWorkManager.enqueueUniquePeriodicWork(LatestNextUpWorker.WORK_NAME, any(), any()) }
        }

    @Test
    fun does_not_reschedule_when_already_scheduled_for_user() =
        runTest(testDispatcher) {
            val userId = UUID.randomUUID()
            val info = mockk<WorkInfo>()
            every { info.state } returns WorkInfo.State.ENQUEUED
            every { info.tags } returns setOf("user:$userId")
            mockWorkInfos(listOf(info))
            createService()

            currentUser.value = currentUser(userId)
            advanceUntilIdle()

            verify(exactly = 0) { mockWorkManager.enqueueUniquePeriodicWork(LatestNextUpWorker.WORK_NAME, any(), any()) }
        }
}
