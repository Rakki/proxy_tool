import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_log_entry.dart';
import '../models/proxy_connection.dart';

class ConnectionStorage {
  static const String _connectionsKey = 'connections';
  static const String _activeConnectionIdKey = 'active_connection_id';
  static const String _logsKey = 'connection_logs';

  Future<List<ProxyConnection>> loadConnections() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<String> rawConnections =
        preferences.getStringList(_connectionsKey) ?? <String>[];

    return rawConnections
        .map(ProxyConnection.fromJson)
        .toList(growable: false);
  }

  Future<void> saveConnections(List<ProxyConnection> connections) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<String> rawConnections =
        connections.map((ProxyConnection item) => item.toJson()).toList();
    await preferences.setStringList(_connectionsKey, rawConnections);
  }

  Future<String?> loadActiveConnectionId() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    return preferences.getString(_activeConnectionIdKey);
  }

  Future<void> saveActiveConnectionId(String connectionId) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(_activeConnectionIdKey, connectionId);
  }

  Future<void> clearActiveConnectionId() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.remove(_activeConnectionIdKey);
  }

  Future<List<ConnectionLogEntry>> loadLogs() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<String> rawLogs =
        preferences.getStringList(_logsKey) ?? <String>[];

    return rawLogs
        .map(ConnectionLogEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> saveLogs(List<ConnectionLogEntry> logs) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<String> rawLogs = logs
        .map((ConnectionLogEntry entry) => entry.toJson())
        .toList();
    await preferences.setStringList(_logsKey, rawLogs);
  }
}
