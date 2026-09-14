package com.koinly.siam

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.TimeUnit

private const val flutterPreferencesFile = "FlutterSharedPreferences"
private const val flutterPrefix = "flutter."
private const val backupPassword = "YOUR_SECRET_PASSWORD"
private const val automaticBackupPrefix = "koinly_auto_"

internal data class AutomaticBackupSettings(
    val enabled: Boolean,
    val frequency: String,
    val hour: Int,
    val minute: Int,
    val weekday: Int,
    val monthDay: Int,
    val deleteOlderBackups: Boolean,
    val directoryUri: String,
    val directoryLabel: String,
) {
    companion object {
        fun read(context: Context): AutomaticBackupSettings {
            val prefs = context.getSharedPreferences(flutterPreferencesFile, Context.MODE_PRIVATE)
            return AutomaticBackupSettings(
                enabled = prefs.boolValue("autoBackupEnabled", false),
                frequency = prefs.stringValue("autoBackupFrequency", "daily").lowercase(Locale.US),
                hour = prefs.intValue("autoBackupHour", 2).coerceIn(0, 23),
                minute = prefs.intValue("autoBackupMinute", 0).coerceIn(0, 59),
                weekday = prefs.intValue("autoBackupWeekday", 7).coerceIn(1, 7),
                monthDay = prefs.intValue("autoBackupMonthDay", 1).coerceIn(1, 28),
                deleteOlderBackups = prefs.boolValue("autoBackupDeleteOlder", true),
                directoryUri = prefs.stringValue("autoBackupDirectoryUri", "").trim(),
                directoryLabel = prefs.stringValue("autoBackupDirectoryLabel", "").trim(),
            )
        }
    }
}

private fun SharedPreferences.rawValue(key: String): Any? = all[flutterPrefix + key]

private fun SharedPreferences.stringValue(key: String, fallback: String): String =
    (rawValue(key) as? String) ?: fallback

private fun SharedPreferences.boolValue(key: String, fallback: Boolean): Boolean =
    (rawValue(key) as? Boolean) ?: fallback

private fun SharedPreferences.intValue(key: String, fallback: Int): Int =
    (rawValue(key) as? Number)?.toInt() ?: fallback

private fun SharedPreferences.stringListValue(key: String): List<String> {
    return when (val raw = rawValue(key)) {
        is Set<*> -> raw.mapNotNull { it?.toString() }
        is String -> {
            // shared_preferences_android stores modern List<String> values as
            // JSON with an implementation prefix. Parsing from the first '['
            // also remains compatible with already-migrated legacy values.
            val start = raw.indexOf('[')
            if (start < 0) return emptyList()
            try {
                val array = JSONArray(raw.substring(start))
                List(array.length()) { index -> array.optString(index) }
            } catch (_: Exception) {
                emptyList()
            }
        }
        else -> emptyList()
    }
}

internal object AutomaticBackupScheduler {
    private const val uniqueWorkName = "koinly-native-automatic-local-backup"
    private const val workTag = "koinly-automatic-local-backup"
    private const val intervalMinutes = 15L

    fun sync(context: Context) {
        val appContext = context.applicationContext
        val settings = AutomaticBackupSettings.read(appContext)
        val manager = WorkManager.getInstance(appContext)
        if (!settings.enabled || settings.directoryUri.isBlank()) {
            manager.cancelUniqueWork(uniqueWorkName)
            return
        }

        val prefs = appContext.getSharedPreferences(flutterPreferencesFile, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val initialDelay = if (isDue(settings, prefs, now)) {
            0L
        } else {
            (nextSlotMillis(settings, now) - now).coerceAtLeast(0L)
        }
        val request = PeriodicWorkRequestBuilder<AutomaticBackupWorker>(intervalMinutes, TimeUnit.MINUTES)
            .setInitialDelay(initialDelay, TimeUnit.MILLISECONDS)
            .addTag(workTag)
            .build()
        @Suppress("DEPRECATION")
        manager.enqueueUniquePeriodicWork(uniqueWorkName, ExistingPeriodicWorkPolicy.REPLACE, request)
    }

    fun isDue(
        settings: AutomaticBackupSettings,
        prefs: SharedPreferences,
        nowMillis: Long = System.currentTimeMillis(),
    ): Boolean {
        if (!settings.enabled || settings.directoryUri.isBlank()) return false
        val latestSlot = mostRecentSlotMillis(settings, nowMillis)
        val last = parseStoredDateTimeMillis(prefs.stringValue("lastAutoBackupAt", ""))
        return last == null || last < latestSlot
    }

    private fun mostRecentSlotMillis(settings: AutomaticBackupSettings, nowMillis: Long): Long {
        val now = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val slot = Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, settings.hour)
            set(Calendar.MINUTE, settings.minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        when (settings.frequency) {
            "weekly" -> {
                val currentDartWeekday = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
                val daysBack = (currentDartWeekday - settings.weekday + 7) % 7
                slot.add(Calendar.DAY_OF_YEAR, -daysBack)
                if (slot.timeInMillis > nowMillis) slot.add(Calendar.DAY_OF_YEAR, -7)
            }
            "monthly" -> {
                slot.set(Calendar.DAY_OF_MONTH, settings.monthDay)
                if (slot.timeInMillis > nowMillis) slot.add(Calendar.MONTH, -1)
                slot.set(Calendar.DAY_OF_MONTH, settings.monthDay)
            }
            else -> {
                if (slot.timeInMillis > nowMillis) slot.add(Calendar.DAY_OF_YEAR, -1)
            }
        }
        return slot.timeInMillis
    }

    private fun nextSlotMillis(settings: AutomaticBackupSettings, nowMillis: Long): Long {
        val slot = Calendar.getInstance().apply { timeInMillis = mostRecentSlotMillis(settings, nowMillis) }
        when (settings.frequency) {
            "weekly" -> slot.add(Calendar.DAY_OF_YEAR, 7)
            "monthly" -> {
                slot.add(Calendar.MONTH, 1)
                slot.set(Calendar.DAY_OF_MONTH, settings.monthDay)
            }
            else -> slot.add(Calendar.DAY_OF_YEAR, 1)
        }
        return slot.timeInMillis
    }

    private fun parseStoredDateTimeMillis(raw: String): Long? {
        if (raw.isBlank()) return null
        return try {
            Instant.parse(raw).toEpochMilli()
        } catch (_: Exception) {
            try {
                OffsetDateTime.parse(raw).toInstant().toEpochMilli()
            } catch (_: Exception) {
                try {
                    LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                } catch (_: Exception) {
                    null
                }
            }
        }
    }
}

class AutomaticBackupWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(flutterPreferencesFile, Context.MODE_PRIVATE)
        val settings = AutomaticBackupSettings.read(applicationContext)
        if (!AutomaticBackupScheduler.isDue(settings, prefs)) return Result.success()

        return try {
            val createdAt = OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
            val fileName = automaticBackupFileName()
            val payload = JSONObject().apply {
                put("version", 7)
                put("backup_type", "automatic")
                put("created_at", createdAt)
                put("database", exportDatabase())
                put("preferences", exportPreferences(prefs))
            }
            val encrypted = encrypt(payload.toString()).toByteArray(StandardCharsets.UTF_8)
            val treeUri = Uri.parse(settings.directoryUri)
            val location = AndroidBackgroundBackupStorage.writeBackup(
                applicationContext,
                treeUri,
                fileName,
                encrypted,
                settings.directoryLabel,
            )
            if (settings.deleteOlderBackups) {
                AndroidBackgroundBackupStorage.pruneOlderAutomaticBackups(applicationContext, treeUri, fileName)
            }
            prefs.edit()
                .putString(flutterPrefix + "lastAutoBackupPath", location)
                .putString(flutterPrefix + "lastAutoBackupAt", createdAt)
                .putString(flutterPrefix + "autoBackupBackgroundError", "")
                .apply()
            Result.success()
        } catch (error: Exception) {
            val message = error.message?.trim().takeUnless { it.isNullOrEmpty() }
                ?: "Automatic background backup failed."
            prefs.edit()
                .putString(flutterPrefix + "autoBackupBackgroundError", message)
                .apply()
            Result.success()
        }
    }

    private fun exportDatabase(): JSONObject {
        val databaseFile = applicationContext.getDatabasePath("koinly_flutter.db")
        if (!databaseFile.exists()) throw IllegalStateException("Koinly database is not available yet.")
        val database = SQLiteDatabase.openDatabase(databaseFile.path, null, SQLiteDatabase.OPEN_READONLY)
        return try {
            val output = JSONObject()
            val tables = listOf(
                "accounts",
                "categories",
                "planned_purchases",
                "subscriptions",
                "transactions",
                "budgets",
                "budget_accounts",
                "budget_categories",
                "loan_contacts",
                "loans",
                "loan_payments",
            )
            for (table in tables) {
                output.put(table, queryTable(database, table))
            }
            output
        } finally {
            database.close()
        }
    }

    private fun queryTable(database: SQLiteDatabase, table: String): JSONArray {
        val rows = JSONArray()
        val cursor = try {
            database.rawQuery("SELECT * FROM `$table`", null)
        } catch (_: Exception) {
            return rows
        }
        cursor.use {
            while (it.moveToNext()) rows.put(cursorRowToJson(it))
        }
        return rows
    }

    private fun cursorRowToJson(cursor: Cursor): JSONObject {
        val row = JSONObject()
        for (index in 0 until cursor.columnCount) {
            val name = cursor.getColumnName(index)
            when (cursor.getType(index)) {
                Cursor.FIELD_TYPE_NULL -> row.put(name, JSONObject.NULL)
                Cursor.FIELD_TYPE_INTEGER -> row.put(name, cursor.getLong(index))
                Cursor.FIELD_TYPE_FLOAT -> row.put(name, cursor.getDouble(index))
                Cursor.FIELD_TYPE_BLOB -> row.put(name, Base64.encodeToString(cursor.getBlob(index), Base64.NO_WRAP))
                else -> row.put(name, cursor.getString(index))
            }
        }
        return row
    }

    private fun exportPreferences(prefs: SharedPreferences): JSONObject {
        fun list(key: String) = JSONArray(prefs.stringListValue(key))
        return JSONObject().apply {
            put("themePreference", prefs.stringValue("themePreference", "system"))
            put("currencySymbol", prefs.stringValue("currencySymbol", "৳"))
            put("currencyCode", prefs.stringValue("currencyCode", "BDT"))
            put("currencyPosition", prefs.stringValue("currencyPosition", "suffix"))
            put("useSeparators", prefs.boolValue("useSeparators", true))
            put("amountsHidden", prefs.boolValue("amountsHidden", false))
            put("profileDisplayName", prefs.stringValue("profileDisplayName", ""))
            put("dismissedFinancialHealthSummaryKeys", list("dismissedFinancialHealthSummaryKeys"))
            put("dateRangeType", prefs.stringValue("dateRangeType", "thisMonth"))
            put("customStart", prefs.stringValue("customStart", ""))
            put("customEnd", prefs.stringValue("customEnd", ""))
            put("filterAccountIds", list("filterAccountIds"))
            put("filterCategoryIds", list("filterCategoryIds"))
            put("filterTypes", list("filterTypes"))
            put("defaultAccountId", prefs.stringValue("defaultAccountId", ""))
            put("defaultExpenseCategoryId", prefs.stringValue("defaultExpenseCategoryId", ""))
            put("defaultIncomeCategoryId", prefs.stringValue("defaultIncomeCategoryId", ""))
            put("compactHomeSummary", prefs.boolValue("compactHomeSummary", false))
            put("reminderEnabled", prefs.boolValue("reminderEnabled", false))
            put("reminderHour", prefs.intValue("reminderHour", 21))
            put("reminderMinute", prefs.intValue("reminderMinute", 0))
            put("loanRecordTransactionsByDefault", prefs.boolValue("loanRecordTransactionsByDefault", true))
            put("loanRemindersEnabled", prefs.boolValue("loanRemindersEnabled", true))
            put("loanShowWrittenOff", prefs.boolValue("loanShowWrittenOff", false))
            put("loanTransactionsVisibleInTransactionList", prefs.boolValue("loanTransactionsVisibleInTransactionList", true))
            put("syncDatabaseProvider", prefs.stringValue("syncDatabaseProvider", "mongoDb"))
            put("syncMongoDatabaseName", prefs.stringValue("syncMongoDatabaseName", "koinly"))
            put("syncMongoCollectionName", prefs.stringValue("syncMongoCollectionName", "koinly_sync_snapshots"))
        }
    }

    private fun automaticBackupFileName(): String {
        val now = Calendar.getInstance()
        return String.format(
            Locale.US,
            "%s%04d%02d%02d_%02d%02d%02d.koinlybackup",
            automaticBackupPrefix,
            now.get(Calendar.YEAR),
            now.get(Calendar.MONTH) + 1,
            now.get(Calendar.DAY_OF_MONTH),
            now.get(Calendar.HOUR_OF_DAY),
            now.get(Calendar.MINUTE),
            now.get(Calendar.SECOND),
        )
    }

    private fun encrypt(source: String): String {
        val sourceBytes = source.toByteArray(StandardCharsets.UTF_8)
        val keyBytes = backupPassword.toByteArray(StandardCharsets.UTF_8)
        val output = ByteArray(sourceBytes.size)
        for (index in sourceBytes.indices) {
            output[index] = (sourceBytes[index].toInt() xor keyBytes[index % keyBytes.size].toInt()).toByte()
        }
        return Base64.encodeToString(output, Base64.NO_WRAP)
    }
}

private object AndroidBackgroundBackupStorage {
    private data class BackupDocument(val uri: Uri, val name: String, val modified: Long)

    fun writeBackup(
        context: Context,
        treeUri: Uri,
        fileName: String,
        bytes: ByteArray,
        directoryLabel: String,
    ): String {
        if (!canWrite(context, treeUri)) {
            throw SecurityException("Koinly no longer has permission to write to the selected backup folder. Choose the folder again.")
        }
        val resolver = context.contentResolver
        val backupDirectory = ensureKoinlyBackupDirectory(context, treeUri)
        val fileUri = findChild(context, treeUri, backupDirectory, fileName, directoryOnly = false)
            ?: DocumentsContract.createDocument(resolver, backupDirectory, "application/octet-stream", fileName)
            ?: throw IllegalStateException("Android could not create the automatic backup file.")
        resolver.openOutputStream(fileUri, "wt")?.use { stream ->
            stream.write(bytes)
            stream.flush()
        } ?: throw IllegalStateException("Android could not open the automatic backup file for writing.")
        val label = directoryLabel.ifBlank { "Koinly/Backup" }
        return "$label/$fileName"
    }

    fun pruneOlderAutomaticBackups(context: Context, treeUri: Uri, keepFileName: String) {
        val backupDirectory = ensureKoinlyBackupDirectory(context, treeUri)
        val documents = listChildren(context, treeUri, backupDirectory)
            .filter { it.name.startsWith(automaticBackupPrefix) && it.name.endsWith(".koinlybackup", ignoreCase = true) }
        for (document in documents) {
            if (document.name == keepFileName) continue
            try {
                DocumentsContract.deleteDocument(context.contentResolver, document.uri)
            } catch (_: Exception) {
                // Retention cleanup must not invalidate the backup just written.
            }
        }
    }

    private fun canWrite(context: Context, treeUri: Uri): Boolean {
        val persisted = context.contentResolver.persistedUriPermissions.any { permission ->
            permission.uri == treeUri && permission.isWritePermission
        }
        if (!persisted) return false
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
            context.contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun parentDocumentUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun childDocumentsUri(treeUri: Uri, parentDocumentUri: Uri): Uri {
        val documentId = DocumentsContract.getDocumentId(parentDocumentUri)
        return DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
    }

    private fun selectedTreeSegments(treeUri: Uri): List<String> {
        return try {
            val treeId = DocumentsContract.getTreeDocumentId(treeUri)
            val relative = treeId.split(":", limit = 2).getOrNull(1).orEmpty().trim('/')
            if (relative.isBlank()) emptyList() else relative.split('/').filter { it.isNotBlank() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun selectedTreeIsKoinlyBackup(treeUri: Uri): Boolean {
        val segments = selectedTreeSegments(treeUri)
        return segments.size >= 2 &&
            segments[segments.lastIndex - 1].equals("Koinly", ignoreCase = true) &&
            segments.last().equals("Backup", ignoreCase = true)
    }

    private fun selectedTreeIsKoinlyFolder(treeUri: Uri): Boolean {
        val segments = selectedTreeSegments(treeUri)
        return segments.isNotEmpty() && segments.last().equals("Koinly", ignoreCase = true)
    }

    private fun ensureKoinlyBackupDirectory(context: Context, treeUri: Uri): Uri {
        val selected = parentDocumentUri(treeUri)
        if (selectedTreeIsKoinlyBackup(treeUri)) return selected
        if (selectedTreeIsKoinlyFolder(treeUri)) {
            return ensureChildDirectory(context, treeUri, selected, "Backup")
        }
        val koinly = ensureChildDirectory(context, treeUri, selected, "Koinly")
        return ensureChildDirectory(context, treeUri, koinly, "Backup")
    }

    private fun ensureChildDirectory(
        context: Context,
        treeUri: Uri,
        parentDocumentUri: Uri,
        name: String,
    ): Uri {
        return findChild(context, treeUri, parentDocumentUri, name, directoryOnly = true)
            ?: DocumentsContract.createDocument(
                context.contentResolver,
                parentDocumentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name,
            )
            ?: throw IllegalStateException("Android could not create the $name backup folder.")
    }

    private fun findChild(
        context: Context,
        treeUri: Uri,
        parentDocumentUri: Uri,
        displayName: String,
        directoryOnly: Boolean,
    ): Uri? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        context.contentResolver.query(childDocumentsUri(treeUri, parentDocumentUri), projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0) continue
                if (cursor.getString(nameIndex) != displayName) continue
                if (directoryOnly && (mimeIndex < 0 || cursor.getString(mimeIndex) != DocumentsContract.Document.MIME_TYPE_DIR)) continue
                return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex))
            }
        }
        return null
    }

    private fun listChildren(context: Context, treeUri: Uri, parentDocumentUri: Uri): List<BackupDocument> {
        val result = mutableListOf<BackupDocument>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        context.contentResolver.query(childDocumentsUri(treeUri, parentDocumentUri), projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0) continue
                val id = cursor.getString(idIndex) ?: continue
                val name = cursor.getString(nameIndex) ?: continue
                val modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) cursor.getLong(modifiedIndex) else 0L
                result.add(
                    BackupDocument(
                        uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                        name = name,
                        modified = modified,
                    ),
                )
            }
        }
        return result
    }
}
