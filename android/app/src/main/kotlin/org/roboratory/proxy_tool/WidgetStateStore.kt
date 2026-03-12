package org.roboratory.proxy_tool

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object WidgetStateStore {
    private const val prefsName = "proxy_widget_state"
    private const val keyProfilesJson = "profiles_json"
    private const val keySelectedProfileId = "selected_profile_id"
    private const val keyActiveProfileId = "active_profile_id"

    fun saveProfiles(
        context: Context,
        profiles: List<Map<*, *>>,
        activeProfileId: String?,
    ) {
        val jsonArray = JSONArray()
        profiles.forEach { profile ->
            jsonArray.put(configurationToJson(profile))
        }

        val currentSelectedId = selectedProfileId(context)
        val nextSelectedId = when {
            profiles.isEmpty() -> null
            profiles.any { (it["id"] as? String) == currentSelectedId } -> currentSelectedId
            else -> profiles.first()["id"] as? String
        }

        prefs(context).edit()
            .putString(keyProfilesJson, jsonArray.toString())
            .putString(keySelectedProfileId, nextSelectedId)
            .putString(keyActiveProfileId, activeProfileId)
            .apply()
    }

    fun clearProfiles(context: Context) {
        prefs(context).edit()
            .remove(keyProfilesJson)
            .remove(keySelectedProfileId)
            .remove(keyActiveProfileId)
            .apply()
    }

    fun setActiveProfileId(context: Context, profileId: String?) {
        prefs(context).edit()
            .putString(keyActiveProfileId, profileId)
            .apply()
    }

    fun activeProfileId(context: Context): String? {
        return prefs(context).getString(keyActiveProfileId, null)
    }

    fun selectedProfileId(context: Context): String? {
        return prefs(context).getString(keySelectedProfileId, null)
    }

    fun profiles(context: Context): List<Map<String, Any?>> {
        val rawJson = prefs(context).getString(keyProfilesJson, null) ?: return emptyList()
        val array = JSONArray(rawJson)
        return buildList {
            for (index in 0 until array.length()) {
                add(jsonToMap(array.getJSONObject(index)))
            }
        }
    }

    fun selectedProfile(context: Context): Map<String, Any?>? {
        val allProfiles = profiles(context)
        val selectedId = selectedProfileId(context)
        if (allProfiles.isEmpty()) {
            return null
        }
        return allProfiles.firstOrNull { it["id"] == selectedId } ?: allProfiles.first()
    }

    fun moveSelection(context: Context, delta: Int) {
        val allProfiles = profiles(context)
        if (allProfiles.isEmpty()) {
            return
        }

        val selectedId = selectedProfileId(context)
        val currentIndex = allProfiles.indexOfFirst { it["id"] == selectedId }.let {
            if (it == -1) 0 else it
        }
        val nextIndex = (currentIndex + delta).floorMod(allProfiles.size)
        prefs(context).edit()
            .putString(keySelectedProfileId, allProfiles[nextIndex]["id"] as? String)
            .apply()
    }

    private fun Int.floorMod(mod: Int): Int {
        val remainder = this % mod
        return if (remainder < 0) remainder + mod else remainder
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun configurationToJson(configuration: Map<*, *>): JSONObject {
        val json = JSONObject()
        configuration.forEach { (key, value) ->
            if (key !is String) return@forEach
            when (value) {
                null -> json.put(key, JSONObject.NULL)
                is List<*> -> {
                    val array = JSONArray()
                    value.forEach { item ->
                        when (item) {
                            is Map<*, *> -> array.put(configurationToJson(item))
                            null -> array.put(JSONObject.NULL)
                            else -> array.put(item)
                        }
                    }
                    json.put(key, array)
                }
                else -> json.put(key, value)
            }
        }
        return json
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = hashMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonToList(array: JSONArray): List<Any?> {
        val result = mutableListOf<Any?>()
        for (index in 0 until array.length()) {
            val value = array.get(index)
            result += when (value) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonToList(value)
                else -> value
            }
        }
        return result
    }
}
