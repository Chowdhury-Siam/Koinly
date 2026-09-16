package com.koinly.siam

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

private const val updatePreferencesFile = "FlutterSharedPreferences"
private const val updatePreferencePrefix = "flutter."
private const val automaticUpdatesKey = "automaticUpdatePopupEnabled"
private const val lastNotifiedVersionKey = "lastNotifiedUpdateVersion"
private const val nativeUpdatePeriodicWork = "koinly-native-periodic-update-check"
private const val nativeUpdateImmediateWork = "koinly-native-immediate-update-check"
private const val nativeUpdateTag = "koinly-native-updates"
private const val updateChannelId = "koinly_app_updates"
private const val updateNotificationId = 902
private const val githubLatestReleaseUrl = "https://api.github.com/repos/Chowdhury-Siam/Koinly/releases/latest"

/**
 * Native Android updater scheduler.
 *
 * The release check deliberately runs outside the Flutter engine. This allows
 * Android WorkManager to check GitHub and post the update notification while
 * Koinly's UI process is not running. The old Dart WorkManager task depended on
 * a headless Flutter isolate and could be deferred or fail to initialize plugin
 * state on some devices.
 */
internal object NativeUpdateCheckScheduler {
    fun sync(context: Context, enabledOverride: Boolean? = null) {
        val appContext = context.applicationContext
        val preferences = appContext.getSharedPreferences(updatePreferencesFile, Context.MODE_PRIVATE)
        val enabled = enabledOverride
            ?: preferences.getBoolean(updatePreferencePrefix + automaticUpdatesKey, true)
        val manager = WorkManager.getInstance(appContext)

        if (!enabled) {
            manager.cancelUniqueWork(nativeUpdatePeriodicWork)
            manager.cancelUniqueWork(nativeUpdateImmediateWork)
            cancelNotification(appContext)
            return
        }

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val periodic = PeriodicWorkRequestBuilder<UpdateCheckWorker>(15, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .addTag(nativeUpdateTag)
            .build()
        manager.enqueueUniquePeriodicWork(
            nativeUpdatePeriodicWork,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodic,
        )

        // Run one native check as soon as the scheduler is installed/updated,
        // then periodic WorkManager checks continue even after the UI closes.
        val immediate = OneTimeWorkRequestBuilder<UpdateCheckWorker>()
            .setConstraints(constraints)
            .addTag(nativeUpdateTag)
            .build()
        manager.enqueueUniqueWork(nativeUpdateImmediateWork, ExistingWorkPolicy.REPLACE, immediate)
    }

    private fun cancelNotification(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(updateNotificationId)
    }
}

class UpdateCheckWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(updatePreferencesFile, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(updatePreferencePrefix + automaticUpdatesKey, true)) {
            return Result.success()
        }

        return try {
            val release = fetchLatestStableRelease() ?: return Result.success()
            @Suppress("DEPRECATION")
            val installedVersion = applicationContext.packageManager
                .getPackageInfo(applicationContext.packageName, 0)
                .versionName ?: return Result.success()
            val installed = SemanticVersion.parse(installedVersion) ?: return Result.success()
            val latest = SemanticVersion.parse(release.version) ?: return Result.success()
            if (latest <= installed) return Result.success()

            val previous = prefs.getString(updatePreferencePrefix + lastNotifiedVersionKey, "") ?: ""
            if (previous == release.version) return Result.success()

            if (postUpdateNotification(release)) {
                prefs.edit()
                    .putString(updatePreferencePrefix + lastNotifiedVersionKey, release.version)
                    .apply()
            }
            Result.success()
        } catch (_: IOException) {
            Result.retry()
        } catch (_: Exception) {
            // A malformed release should not create an endless WorkManager
            // retry loop. The next periodic check will try again normally.
            Result.success()
        }
    }

    private fun fetchLatestStableRelease(): ReleaseInfo? {
        val connection = (URL(githubLatestReleaseUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12_000
            readTimeout = 12_000
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "Koinly-Android-Background-Updater")
            instanceFollowRedirects = true
        }
        try {
            val status = connection.responseCode
            if (status == 403 || status == 429 || status == 404) return null
            if (status >= 500) throw IOException("GitHub returned HTTP $status")
            if (status !in 200..299) return null

            val json = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val payload = JSONObject(json)
            if (payload.optBoolean("draft", false) || payload.optBoolean("prerelease", false)) return null
            val tag = payload.optString("tag_name", "").trim()
            if (tag.isEmpty()) return null
            val version = tag.removePrefix("v").removePrefix("V")
            val name = payload.optString("name", "").trim()
            return ReleaseInfo(version = version, name = name)
        } finally {
            connection.disconnect()
        }
    }

    private fun postUpdateNotification(release: ReleaseInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    updateChannelId,
                    "Koinly updates",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notifications when a newer Koinly release is available."
                },
            )
        }

        val launchIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("koinly_update_version", release.version)
            }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                applicationContext,
                updateNotificationId,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val body = if (release.name.isBlank()) {
            "A new update is ready. Open Koinly to review what changed."
        } else {
            "${release.name} is ready. Open Koinly to review what changed."
        }
        val notification = NotificationCompat.Builder(applicationContext, updateChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Koinly ${release.version} is available")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()
        manager.notify(updateNotificationId, notification)
        return true
    }

    private data class ReleaseInfo(val version: String, val name: String)

    private data class SemanticVersion(
        val major: Int,
        val minor: Int,
        val patch: Int,
        val preRelease: String,
    ) : Comparable<SemanticVersion> {
        override fun compareTo(other: SemanticVersion): Int {
            if (major != other.major) return major.compareTo(other.major)
            if (minor != other.minor) return minor.compareTo(other.minor)
            if (patch != other.patch) return patch.compareTo(other.patch)
            if (preRelease.isEmpty() && other.preRelease.isNotEmpty()) return 1
            if (preRelease.isNotEmpty() && other.preRelease.isEmpty()) return -1
            return preRelease.compareTo(other.preRelease)
        }

        companion object {
            fun parse(rawValue: String): SemanticVersion? {
                var raw = rawValue.trim().removePrefix("v").removePrefix("V").substringBefore('+')
                val preRelease = raw.substringAfter('-', "")
                raw = raw.substringBefore('-')
                val parts = raw.split('.')
                if (parts.isEmpty() || parts.size > 3) return null
                val major = parts.getOrNull(0)?.toIntOrNull() ?: return null
                val minor = parts.getOrNull(1)?.toIntOrNull() ?: 0
                val patch = parts.getOrNull(2)?.toIntOrNull() ?: 0
                return SemanticVersion(major, minor, patch, preRelease)
            }
        }
    }
}
