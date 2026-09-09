package com.koinly.siam

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val updaterChannel = "com.koinly.siam/updater"
    private val profileMediaChannel = "com.koinly.siam/profile_media"
    private val backupStorageChannel = "com.koinly.siam/backup_storage"
    private val profileMediaPermissionRequestCode = 4107
    private val backupDirectoryRequestCode = 4208
    private var pendingProfileMediaPermissionResult: MethodChannel.Result? = null
    private var pendingBackupDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> {
                    openInstallPermissionSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("missing_path", "APK path is missing.", null)
                    } else {
                        result.success(installApk(path))
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, profileMediaChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> result.success(profileMediaPermissionState())
                "requestPermission" -> requestProfileMediaPermission(result)
                "openAppSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupStorageChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> pickBackupDirectory(result)
                "canWrite" -> {
                    val uri = call.argument<String>("uri")
                    result.success(!uri.isNullOrBlank() && canWriteBackupDirectory(Uri.parse(uri)))
                }
                "writeFile" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (uri.isNullOrBlank() || name.isNullOrBlank() || bytes == null) {
                        result.error("invalid_arguments", "Backup folder, file name, or bytes are missing.", null)
                    } else {
                        try {
                            writeBackupFile(Uri.parse(uri), name, bytes)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("backup_write_failed", error.message ?: "Could not write backup file.", null)
                        }
                    }
                }
                "listFiles" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("missing_uri", "Backup folder is missing.", null)
                    } else {
                        try {
                            result.success(listBackupFiles(Uri.parse(uri)))
                        } catch (error: Exception) {
                            result.error("backup_list_failed", error.message ?: "Could not list backup files.", null)
                        }
                    }
                }
                "deleteFile" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name")
                    if (uri.isNullOrBlank() || name.isNullOrBlank()) {
                        result.error("invalid_arguments", "Backup folder or file name is missing.", null)
                    } else {
                        try {
                            deleteBackupFile(Uri.parse(uri), name)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("backup_delete_failed", error.message ?: "Could not delete backup file.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != backupDirectoryRequestCode) return
        val pending = pendingBackupDirectoryResult
        pendingBackupDirectoryResult = null
        if (pending == null) return
        val treeUri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (treeUri == null) {
            pending.success(null)
            return
        }
        try {
            val takeFlags = (data?.flags ?: 0) and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (takeFlags == 0) {
                pending.error("folder_permission_failed", "Android did not grant access to the selected folder.", null)
                return
            }
            contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            if (!canWriteBackupDirectory(treeUri)) {
                pending.error("folder_not_writable", "The selected folder is not writable.", null)
                return
            }
            pending.success(mapOf("uri" to treeUri.toString(), "label" to backupDirectoryLabel(treeUri)))
        } catch (error: Exception) {
            pending.error("folder_permission_failed", error.message ?: "Could not keep access to the selected folder.", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != profileMediaPermissionRequestCode) return
        pendingProfileMediaPermissionResult?.success(profileMediaPermissionState(checkPermanentDenial = true))
        pendingProfileMediaPermissionResult = null
    }

    private fun fullProfileMediaPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun requestedProfileMediaPermissions(): Array<String> {
        val permissions = fullProfileMediaPermissions().toMutableList()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            permissions.add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        }
        return permissions.toTypedArray()
    }

    private fun hasFullProfileMediaPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return fullProfileMediaPermissions().all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun hasSelectedProfileMediaPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun profileMediaPermissionState(checkPermanentDenial: Boolean = false): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"
        if (hasFullProfileMediaPermission() || hasSelectedProfileMediaPermission()) return "granted"
        if (checkPermanentDenial) {
            val permanentlyDenied = fullProfileMediaPermissions().any { permission ->
                ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED &&
                    !ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
            }
            if (permanentlyDenied) return "permanentlyDenied"
        }
        return "denied"
    }

    private fun requestProfileMediaPermission(result: MethodChannel.Result) {
        if (hasFullProfileMediaPermission() || hasSelectedProfileMediaPermission()) {
            result.success("granted")
            return
        }
        if (pendingProfileMediaPermissionResult != null) {
            result.error("request_in_progress", "A Photos and videos permission request is already active.", null)
            return
        }
        pendingProfileMediaPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            requestedProfileMediaPermissions(),
            profileMediaPermissionRequestCode,
        )
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun pickBackupDirectory(result: MethodChannel.Result) {
        if (pendingBackupDirectoryResult != null) {
            result.error("request_in_progress", "A backup folder picker is already open.", null)
            return
        }
        pendingBackupDirectoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        startActivityForResult(intent, backupDirectoryRequestCode)
    }

    private fun hasPersistedWritePermission(uri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.uri == uri && permission.isWritePermission
        }
    }

    private fun canWriteBackupDirectory(uri: Uri): Boolean {
        if (!hasPersistedWritePermission(uri)) return false
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(uri)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(uri, documentId)
            contentResolver.query(
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

    private fun backupDirectoryLabel(uri: Uri): String {
        return try {
            val treeId = DocumentsContract.getTreeDocumentId(uri)
            val parts = treeId.split(":", limit = 2)
            val volume = when (parts.firstOrNull()?.lowercase()) {
                "primary" -> "Internal storage"
                "home" -> "Documents"
                else -> parts.firstOrNull().orEmpty().ifBlank { "Android storage" }
            }
            val relative = parts.getOrNull(1).orEmpty().trim('/')
            if (relative.isBlank()) volume else "$volume/$relative"
        } catch (_: Exception) {
            "Selected Android folder"
        }
    }

    private fun childDocumentsUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
    }

    private fun parentDocumentUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun findBackupDocument(treeUri: Uri, fileName: String): Uri? {
        val childrenUri = childDocumentsUri(treeUri)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (nameIndex < 0 || idIndex < 0) continue
                if (cursor.getString(nameIndex) == fileName) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex))
                }
            }
        }
        return null
    }

    private fun writeBackupFile(treeUri: Uri, fileName: String, bytes: ByteArray) {
        if (!canWriteBackupDirectory(treeUri)) {
            throw SecurityException("Koinly no longer has write access to this folder. Choose it again in backup settings.")
        }
        val documentUri = findBackupDocument(treeUri, fileName)
            ?: DocumentsContract.createDocument(
                contentResolver,
                parentDocumentUri(treeUri),
                "application/octet-stream",
                fileName,
            )
            ?: throw IllegalStateException("Android could not create the backup file in this folder.")
        contentResolver.openOutputStream(documentUri, "wt")?.use { stream ->
            stream.write(bytes)
            stream.flush()
        } ?: throw IllegalStateException("Android could not open the backup file for writing.")
    }

    private fun listBackupFiles(treeUri: Uri): List<Map<String, Any>> {
        if (!canWriteBackupDirectory(treeUri)) {
            throw SecurityException("Koinly no longer has access to this backup folder.")
        }
        val result = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        contentResolver.query(childDocumentsUri(treeUri), projection, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                if (nameIndex < 0) continue
                val name = cursor.getString(nameIndex) ?: continue
                val modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) cursor.getLong(modifiedIndex) else 0L
                result.add(mapOf("name" to name, "lastModified" to modified))
            }
        }
        return result
    }

    private fun deleteBackupFile(treeUri: Uri, fileName: String) {
        if (!canWriteBackupDirectory(treeUri)) return
        val documentUri = findBackupDocument(treeUri, fileName) ?: return
        DocumentsContract.deleteDocument(contentResolver, documentUri)
    }

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun installApk(path: String): Boolean {
        val apkFile = File(path)
        if (!apkFile.exists()) return false
        val apkUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        grantUriPermission(packageName, apkUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(intent)
        return true
    }
}
