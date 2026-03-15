import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

import 'config/unity_ads_config.dart';
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

class _ProxyToolAppState extends State<ProxyToolApp> with WidgetsBindingObserver {
  final ConnectionStorage _storage = ConnectionStorage();
  final List<ProxyConnection> _connections = <ProxyConnection>[];
  final List<ConnectionLogEntry> _logs = <ConnectionLogEntry>[];
  final ValueNotifier<List<ConnectionLogEntry>> _logsListenable =
      ValueNotifier<List<ConnectionLogEntry>>(const <ConnectionLogEntry>[]);
  final ValueNotifier<TrafficSnapshot> _trafficSnapshotNotifier =
      ValueNotifier<TrafficSnapshot>(
        const TrafficSnapshot(
          uploadTotal: '0 B',
          downloadTotal: '0 B',
          uploadSpeed: '0 B/s',
          downloadSpeed: '0 B/s',
        ),
      );
  StreamSubscription<Map<String, dynamic>>? _runtimeSubscription;
  String? _activeConnectionId;
  bool _isLoading = true;
  int? _lastTrafficTimestampMs;
  int? _lastTrafficTxBytes;
  int? _lastTrafficRxBytes;
  Timer? _pendingLogSaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeUnityAds();
    _runtimeSubscription = ProxyRuntime.runtimeEvents().listen(_handleRuntimeEvent);
    _loadSavedConnections();
  }

  Future<void> _initializeUnityAds() async {
    if (!UnityAdsConfig.isConfigured) {
      return;
    }

    await UnityAds.init(
      gameId: UnityAdsConfig.androidGameId,
      testMode: UnityAdsConfig.testMode,
      onComplete: () {},
      onFailed: (UnityAdsInitializationError error, String message) {},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtimeSubscription?.cancel();
    _pendingLogSaveTimer?.cancel();
    _flushLogsToStorage();
    _logsListenable.dispose();
    _trafficSnapshotNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRuntimeStateFromNative();
    }
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
    _publishVisibleLogs();

    await _refreshRuntimeStateFromNative();
    await _syncWidgetFromState();
  }

  Future<void> _refreshRuntimeStateFromNative() async {
    final Map<String, dynamic> state = await ProxyRuntime.getWidgetState();
    final String? nativeProfileId = state['profileId'] as String?;
    final bool nativeIsActive = state['isActive'] as bool? ?? false;

    if (!mounted) {
      _activeConnectionId = nativeIsActive ? nativeProfileId : null;
      return;
    }

    setState(() {
      _activeConnectionId = nativeIsActive ? nativeProfileId : null;
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
    await _syncWidgetFromState();
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
    await _syncWidgetFromState();
  }

  Future<void> _startConnection(
    BuildContext context,
    ProxyConnection connection,
  ) async {
    try {
      final String? previousActiveConnectionId = _activeConnectionId;
      final bool isSwitching =
          previousActiveConnectionId != null &&
          previousActiveConnectionId != connection.id;

      if (previousActiveConnectionId == connection.id) {
        await _appendLog('Proxy already active: ${connection.name}');

        if (!context.mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile "${connection.name}" is already active.'),
          ),
        );
        return;
      }

      if (isSwitching) {
        final String? previousConnectionName = _connectionNameById(
          previousActiveConnectionId,
        );
        await ProxyRuntime.stop();
        _resetTrafficStats();

        if (mounted) {
          setState(() {
            _activeConnectionId = null;
          });
        } else {
          _activeConnectionId = null;
        }
        await _storage.clearActiveConnectionId();
        await _syncWidgetFromState();

        if (previousConnectionName != null) {
          await _appendLog('Proxy deactivated: $previousConnectionName');
          await _appendLog(
            'Proxy switched: $previousConnectionName -> ${connection.name}',
          );
        } else {
          await _appendLog('Proxy switched to: ${connection.name}');
        }
      }

      _resetTrafficStats();
      await ProxyRuntime.start(connection);

      setState(() {
        _activeConnectionId = connection.id;
      });

      await _storage.saveActiveConnectionId(connection.id);
      await _appendLog('Proxy activated: ${connection.name}');
      await _syncWidgetFromState();

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
            isSwitching
                ? 'Profile switched to "${connection.name}". Routing: $routingMessage.'
                : 'Profile "${connection.name}" started. Routing: $routingMessage.',
          ),
        ),
      );
    } catch (error) {
      await _appendLog('Proxy start error: ${connection.name} • $error');

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
      _resetTrafficStats();

      setState(() {
        _activeConnectionId = null;
      });

      await _storage.clearActiveConnectionId();
      await _appendLog('Proxy deactivated: ${connection.name}');
      await _syncWidgetFromState();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile "${connection.name}" stopped.'),
        ),
      );
    } catch (error) {
      await _appendLog('Proxy stop error: ${connection.name} • $error');

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
        builder: (_) => LogsScreen(
          logsListenable: _logsListenable,
          trafficListenable: _trafficSnapshotNotifier,
          onClearPressed: _clearLogs,
        ),
      ),
    );
  }

  Future<void> _clearLogs() async {
    if (!mounted) {
      _logs.clear();
      _publishVisibleLogs();
      _pendingLogSaveTimer?.cancel();
      await _flushLogsToStorage();
      return;
    }

    setState(() {
      _logs.clear();
    });
    _publishVisibleLogs();

    _pendingLogSaveTimer?.cancel();
    await _flushLogsToStorage();
  }

  Future<void> _syncWidgetFromState() async {
    if (_connections.isEmpty) {
      await ProxyRuntime.clearWidgetState();
      return;
    }

    await ProxyRuntime.syncWidgetState(
      connections: _connections
          .map((ProxyConnection connection) => connection.toMap())
          .toList(growable: false),
      activeConnectionId: _activeConnectionId,
    );
  }

  Future<void> _deleteConnection(
    BuildContext context,
    ProxyConnection connection,
  ) async {
    final bool wasActive = connection.id == _activeConnectionId;

    if (wasActive) {
      try {
        await ProxyRuntime.stop();
      } catch (error) {
        await _appendLog('Proxy stop error: ${connection.name} • $error');
      }
    }

    setState(() {
      _connections.removeWhere((ProxyConnection item) => item.id == connection.id);
      if (wasActive) {
        _activeConnectionId = null;
      }
    });

    await _storage.saveConnections(_connections);
    if (wasActive) {
      await _storage.clearActiveConnectionId();
    }
    await _syncWidgetFromState();

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connection "${connection.name}" deleted.'),
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
      _publishVisibleLogs();
      _scheduleLogsSave();
      return;
    }

    setState(() {
      _logs.add(entry);
      if (_logs.length > 200) {
        _logs.removeRange(0, _logs.length - 200);
      }
    });
    _publishVisibleLogs();

    _scheduleLogsSave();
  }

  void _handleRuntimeEvent(Map<String, dynamic> event) {
    final String type = (event['type'] as String?) ?? 'runtime';
    final String message = (event['message'] as String?) ?? 'Runtime event';
    final int? timestampMs = event['timestamp'] as int?;
    final Map<String, dynamic> data = Map<String, dynamic>.from(
      (event['data'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
    );

    final ConnectionLogEntry? normalizedEntry = _normalizeRuntimeLogEntry(
      type: type,
      message: message,
      timestampMs: timestampMs,
      data: data,
    );
    if (normalizedEntry != null) {
      _appendStructuredLog(normalizedEntry);
    }

    if (type == 'vpn_destroyed' ||
        type == 'vpn_revoked' ||
        type == 'tun2proxy_exit' ||
        type == 'vpn_error') {
      _resetTrafficStats();
      final bool hadActiveConnection = _activeConnectionId != null;
      final String? activeConnectionName = _activeConnectionName();

      if (mounted && _activeConnectionId != null) {
        setState(() {
          _activeConnectionId = null;
        });
      } else {
        _activeConnectionId = null;
      }
      _storage.clearActiveConnectionId();

      if (type == 'vpn_revoked' && hadActiveConnection && activeConnectionName != null) {
        _appendLog('Proxy deactivated: $activeConnectionName');
      }
      if (type == 'vpn_destroyed' && hadActiveConnection && activeConnectionName != null) {
        _appendLog('Proxy deactivated: $activeConnectionName');
      }

      _syncWidgetFromState();
    }

    if (type == 'vpn_starting' || type == 'vpn_established') {
      final String? profileId = data['profileId'] as String?;
      if (profileId != null) {
        if (mounted) {
          setState(() {
            _activeConnectionId = profileId;
          });
        } else {
          _activeConnectionId = profileId;
        }
      }
    }
  }

  String? _activeConnectionName() {
    return _connectionNameById(_activeConnectionId);
  }

  String? _connectionNameById(String? connectionId) {
    if (connectionId == null) {
      return null;
    }

    for (final ProxyConnection connection in _connections) {
      if (connection.id == connectionId) {
        return connection.name;
      }
    }

    return null;
  }

  bool _shouldDisplayLogEntry(ConnectionLogEntry entry) {
    return entry.type == 'connection' ||
        entry.type == 'status' ||
        entry.message.startsWith('Proxy activated:') ||
        entry.message.startsWith('Proxy deactivated:') ||
        entry.message.toLowerCase().contains('error');
  }

  ConnectionLogEntry? _normalizeRuntimeLogEntry({
    required String type,
    required String message,
    required int? timestampMs,
    required Map<String, dynamic> data,
  }) {
    final DateTime timestamp = timestampMs == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(timestampMs);

    if (type == 'native_log') {
      final RegExpMatch? beginningMatch = RegExp(
        r'Beginning #\d+ (\w+) ([^ ]+) -> ([^ ]+)',
      ).firstMatch(message);
      if (beginningMatch != null) {
        final String protocol = beginningMatch.group(1) ?? 'IP';
        final String destination = beginningMatch.group(3) ?? 'unknown';

        return ConnectionLogEntry(
          type: 'connection',
          message: '$protocol $destination',
          timestamp: timestamp,
        );
      }

      return null;
    }

    if (type == 'proxy_ready') {
      return ConnectionLogEntry(
        type: 'status',
        message: 'Proxy ready',
        timestamp: timestamp,
        data: <String, dynamic>{
          if (data['endpoint'] != null) 'endpoint': data['endpoint'],
          if (data['proxyType'] != null) 'proxyType': data['proxyType'],
          if (data['source'] != null) 'source': data['source'],
        },
      );
    }

    if (type == 'traffic') {
      final int tx = (data['tx'] as num?)?.toInt() ?? 0;
      final int rx = (data['rx'] as num?)?.toInt() ?? 0;
      final int currentTimestampMs =
          timestampMs ?? DateTime.now().millisecondsSinceEpoch;
      final int? previousTimestampMs = _lastTrafficTimestampMs;
      final int? previousTx = _lastTrafficTxBytes;
      final int? previousRx = _lastTrafficRxBytes;

      _lastTrafficTimestampMs = currentTimestampMs;
      _lastTrafficTxBytes = tx;
      _lastTrafficRxBytes = rx;

      if (previousTimestampMs == null || previousTx == null || previousRx == null) {
        _updateTrafficSnapshot(
          uploadTotal: _formatBytes(tx),
          downloadTotal: _formatBytes(rx),
          uploadSpeed: '0 B/s',
          downloadSpeed: '0 B/s',
        );
        return null;
      }

      final int elapsedMs = currentTimestampMs - previousTimestampMs;
      final int txDelta = tx - previousTx;
      final int rxDelta = rx - previousRx;
      final double elapsedSeconds = elapsedMs <= 0 ? 1 : elapsedMs / 1000.0;

      _updateTrafficSnapshot(
        uploadTotal: _formatBytes(tx),
        downloadTotal: _formatBytes(rx),
        uploadSpeed: _formatBytesPerSecond(txDelta <= 0 ? 0 : txDelta / elapsedSeconds),
        downloadSpeed: _formatBytesPerSecond(rxDelta <= 0 ? 0 : rxDelta / elapsedSeconds),
      );
      return null;
    }

    if (type == 'vpn_error') {
      return ConnectionLogEntry(
        type: 'error',
        message: 'Proxy error: $message',
        timestamp: timestamp,
      );
    }

    return null;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatBytesPerSecond(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }

    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }

    if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }

    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
  }

  void _resetTrafficStats() {
    _lastTrafficTimestampMs = null;
    _lastTrafficTxBytes = null;
    _lastTrafficRxBytes = null;
    _updateTrafficSnapshot(
      uploadTotal: '0 B',
      downloadTotal: '0 B',
      uploadSpeed: '0 B/s',
      downloadSpeed: '0 B/s',
    );
  }

  void _updateTrafficSnapshot({
    required String uploadTotal,
    required String downloadTotal,
    required String uploadSpeed,
    required String downloadSpeed,
  }) {
    _trafficSnapshotNotifier.value = TrafficSnapshot(
      uploadTotal: uploadTotal,
      downloadTotal: downloadTotal,
      uploadSpeed: uploadSpeed,
      downloadSpeed: downloadSpeed,
    );
  }

  void _scheduleLogsSave() {
    _pendingLogSaveTimer?.cancel();
    _pendingLogSaveTimer = Timer(
      const Duration(milliseconds: 800),
      _flushLogsToStorage,
    );
  }

  Future<void> _flushLogsToStorage() async {
    await _storage.saveLogs(_logs);
  }

  void _publishVisibleLogs() {
    _logsListenable.value = _logs
        .where(_shouldDisplayLogEntry)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    const ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0A7BD3),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD9F1FF),
      onPrimaryContainer: Color(0xFF003355),
      secondary: Color(0xFF10A9BC),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD9F7FB),
      onSecondaryContainer: Color(0xFF00363E),
      tertiary: Color(0xFF2BCB6F),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFDCF9E6),
      onTertiaryContainer: Color(0xFF0A3A1C),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFCFDFE),
      onSurface: Color(0xFF14212B),
      surfaceContainerHighest: Color(0xFFE2EEF5),
      onSurfaceVariant: Color(0xFF4A626F),
      outline: Color(0xFF6E8794),
      outlineVariant: Color(0xFFC2D2DC),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF29363F),
      onInverseSurface: Color(0xFFECF2F5),
      inversePrimary: Color(0xFFA9D6FF),
      surfaceTint: Color(0xFF0A7BD3),
    );

    return MaterialApp(
      title: 'Proxy Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F8FB),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
          scrolledUnderElevation: 6,
          elevation: 4,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: colorScheme.surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF0381EC),
          foregroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: colorScheme.secondaryContainer,
          selectedColor: colorScheme.primaryContainer,
          labelStyle: TextStyle(color: colorScheme.onSecondaryContainer),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.18),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.26),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.26),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.52),
              width: 1.6,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
            onDeletePressed: (ProxyConnection connection) =>
                _deleteConnection(context, connection),
          );
        },
      ),
    );
  }
}
