package org.roboratory.proxy_tool

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object WidgetStateStore {
    private const val prefsName = "proxy_widget_state"
    private const val keyProfileJson = "profile_json"
    private const val keyProfileName = "profile_name"
    private const val keyProfileId = "profile_id"
    private const val keyIsActive = "is_active"

    fun saveProfile(context: Context, configuration: Map<*, *>, isActive: Boolean) {
        val json = configurationToJson(configuration).toString()
        prefs(context).edit()
            .putString(keyProfileJson, json)
            .putString(keyProfileName, configuration["name"] as? String ?: "Proxy profile")
            .putString(keyProfileId, configuration["id"] as? String)
            .putBoolean(keyIsActive, isActive)
            .apply()
    }

    fun setActive(context: Context, isActive: Boolean) {
        prefs(context).edit()
            .putBoolean(keyIsActive, isActive)
            .apply()
    }

    fun clearProfile(context: Context) {
        prefs(context).edit()
            .remove(keyProfileJson)
            .remove(keyProfileName)
            .remove(keyProfileId)
            .putBoolean(keyIsActive, false)
            .apply()
    }

    fun profileName(context: Context): String? {
        return prefs(context).getString(keyProfileName, null)
    }

    fun profileId(context: Context): String? {
        return prefs(context).getString(keyProfileId, null)
    }

    fun isActive(context: Context): Boolean {
        return prefs(context).getBoolean(keyIsActive, false)
    }

    fun loadProfile(context: Context): Map<String, Any?>? {
        val json = prefs(context).getString(keyProfileJson, null) ?: return null
        return jsonToMap(JSONObject(json))
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
