package com.dude555afk.orvia.workspace

import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.util.Log
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException

internal class WorkspaceDocumentsStore(private val appData: File) {
    fun list(): List<WorkspaceDocumentRoot> {
        val database = File(appData, "orvia.db")
        if (!database.isFile) return emptyList()
        try {
            SQLiteDatabase.openDatabase(
                database.path,
                null,
                SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            ) { throw SQLiteException("Workspace database unavailable") }.use { db ->
                db.rawQuery(
                    "SELECT id, payload FROM extension_entity_rows WHERE kind = ? ORDER BY sort_order, id",
                    arrayOf("workspace"),
                ).use { cursor ->
                    val result = mutableListOf<WorkspaceDocumentRoot>()
                    while (cursor.moveToNext()) {
                        val id = cursor.getString(0)
                        if (!WorkspaceDocumentPaths.validId(id)) continue
                        try {
                            val payload = JSONObject(cursor.getString(1))
                            if (payload.optString("kind", "managed") != "managed") continue
                            if (payload.optString("id") != id) continue
                            result += WorkspaceDocumentRoot(
                                id,
                                payload.optString("name").ifBlank { id },
                                WorkspaceDocumentPaths.managedDirectory(appData, id),
                            )
                        } catch (_: JSONException) {
                        } catch (_: IOException) {
                        }
                    }
                    return result
                }
            }
        } catch (error: SQLiteException) {
            Log.w("WorkspaceDocuments", "Workspace registry unavailable", error)
            return emptyList()
        }
    }
}
