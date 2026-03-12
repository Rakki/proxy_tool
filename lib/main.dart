import 'dart:async';

import 'package:flutter/material.dart';

import 'data/connection_storage.dart';
import 'models/connection_log_entry.dart';
import 'models/proxy_connection.dart';
import 'platform/proxy_runtime.dart';
import 'screens/connection_form_screen.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';

void main() {
  runApp(const ProxyToolApp());
}

class ProxyToolApp extends StatefulWidget {
  const ProxyToolApp({super.key});

  @override
  State<ProxyToolApp> createState() => _ProxyToolAppState();
}

class _ProxyToolAppState extends State<ProxyToolApp> {
  final ConnectionStorage _storage = ConnectionStorage();
  final List<ProxyConnection> _connections = <ProxyConnection>[];
  final List<ConnectionLogEntry> _logs = <ConnectionLogEntry>[];
  StreamSubscription<Map<String, dynamic>>? _runtimeSubscription;
  String? _activeConnectionId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _runtimeSubscription = ProxyRuntime.runtimeEvents().listen(_handleRuntimeEvent);
    _loadSavedConnections();
  }

  @override
  void dispose() {
    _runtimeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedConnections() async {
    final List<ProxyConnection> savedConnections =
        await _storage.loadConnections();
    final String? savedActiveConnectionId =
        await _storage.loadActiveConnectionId();
    final List<ConnectionLogEntry> savedLogs = await _storage.loadLogs();

    if (!mounted) {
      return;
    }

    setState(() {
      _connections
        ..clear()
        ..addAll(savedConnections);
      _logs
        ..clear()
        ..addAll(savedLogs);
      _activeConnectionId = savedActiveConnectionId;
      _isLoading = false;
    });
  }

  Future<void> _openCreateConnection(BuildContext context) async {
    final ProxyConnection? created = await Navigator.of(context).push(
      MaterialPageRoute<ProxyConnection>(
        builder: (_) => const ConnectionFormScreen(),
      ),
    );

    if (created == null) {
      return;
    }

    setState(() {
      _connections.add(created);
    });

    await _storage.saveConnections(_connections);
    await _appendLog('Saved connection "${created.name}".');
  }

  Future<void> _openEditConnection(
    BuildContext context,
    ProxyConnection connection,
  ) async {
    final ProxyConnection? updated = await Navigator.of(context).push(
      MaterialPageRoute<ProxyConnection>(
        builder: (_) => ConnectionFormScreen(initialConnection: connection),
      ),
    );

    if (updated == null) {
      return;
    }

    final int index = _connections.indexWhere(
      (ProxyConnection item) => item.id == connection.id,
    );
    if (index == -1) {
      return;
    }

    setState(() {
      _connections[index] = updated;
    });

    await _storage.saveConnections(_connections);
    await _appendLog('Updated connection "${updated.name}".');
  }

  Future<void> _startConnection(
    BuildContext context,
    ProxyConnection connection,
  ) async {
    try {
      await ProxyRuntime.start(connection);

      setState(() {
        _activeConnectionId = connection.id;
      });

      await _storage.saveActiveConnectionId(connection.id);
      await _appendLog('Started connection "${connection.name}".');

      if (!context.mounted) {
        return;
      }

      final String routingMessage =
          connection.routingMode == RoutingMode.allTraffic
              ? 'all traffic'
              : 'selected apps only';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile "${connection.name}" started. Routing: $routingMessage.',
          ),
        ),
      );
    } catch (error) {
      await _appendLog('Failed to start "${connection.name}": $error');

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start "${connection.name}".'),
        ),
      );
    }
  }

  Future<void> _stopConnection(
    BuildContext context,
    ProxyConnection connection,
  ) async {
    try {
      await ProxyRuntime.stop();

      setState(() {
        _activeConnectionId = null;
      });

      await _storage.clearActiveConnectionId();
      await _appendLog('Stopped connection "${connection.name}".');

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile "${connection.name}" stopped.'),
        ),
      );
    } catch (error) {
      await _appendLog('Failed to stop "${connection.name}": $error');

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop "${connection.name}".'),
        ),
      );
    }
  }

  Future<void> _openLogs(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogsScreen(logs: _logs.reversed.toList(growable: false)),
      ),
    );
  }

  Future<void> _appendLog(String message) async {
    await _appendStructuredLog(
      ConnectionLogEntry(
        message: message,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> _appendStructuredLog(ConnectionLogEntry entry) async {
    if (!mounted) {
      _logs.add(entry);
      await _storage.saveLogs(_logs);
      return;
    }

    setState(() {
      _logs.add(entry);
      if (_logs.length > 200) {
        _logs.removeRange(0, _logs.length - 200);
      }
    });

    await _storage.saveLogs(_logs);
  }

  void _handleRuntimeEvent(Map<String, dynamic> event) {
    final String type = (event['type'] as String?) ?? 'runtime';
    final String message = (event['message'] as String?) ?? 'Runtime event';
    final int? timestampMs = event['timestamp'] as int?;
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      (event['data'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
    );

    _appendStructuredLog(
      ConnectionLogEntry(
        type: type,
        message: message,
        timestamp: timestampMs == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(timestampMs),
        data: data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E5EFF),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Proxy Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: Builder(
        builder: (BuildContext context) {
          if (_isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return HomeScreen(
            connections: _connections,
            activeConnectionId: _activeConnectionId,
            onAddPressed: () => _openCreateConnection(context),
            onEditPressed: (ProxyConnection connection) =>
                _openEditConnection(context, connection),
            onStartPressed: (ProxyConnection connection) =>
                _startConnection(context, connection),
            onStopPressed: (ProxyConnection connection) =>
                _stopConnection(context, connection),
            onLogsPressed: () => _openLogs(context),
          );
        },
      ),
    );
  }
}
