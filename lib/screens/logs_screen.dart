import 'package:flutter/material.dart';

import '../models/connection_log_entry.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({
    super.key,
    required this.logs,
  });

  final List<ConnectionLogEntry> logs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection logs'),
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('No logs yet'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final ConnectionLogEntry entry = logs[index];
                return Card(
                  elevation: 0,
                  child: ListTile(
                    title: Text(entry.message),
                    subtitle: Text(
                      [
                        _formatTimestamp(entry.timestamp),
                        if (entry.data.isNotEmpty) _formatData(entry),
                      ].join('\n'),
                    ),
                    isThreeLine: entry.data.isNotEmpty,
                  ),
                );
              },
            ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${timestamp.year}-${twoDigits(timestamp.month)}-${twoDigits(timestamp.day)} '
        '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
  }

  String _formatData(ConnectionLogEntry entry) {
    final List<String> lines = <String>[];
    entry.data.forEach((String key, dynamic value) {
      if (value == null) {
        return;
      }

      final String normalizedKey = switch (key) {
        'tx' => 'tx',
        'rx' => 'rx',
        'endpoint' => 'endpoint',
        'proxyType' => 'proxy',
        'routingMode' => 'routing',
        'selectedApps' => 'apps',
        'selectedAppsCount' => 'apps',
        'level' => 'level',
        'exitCode' => 'exit',
        'result' => 'result',
        _ => key,
      };

      lines.add('$normalizedKey: ${_formatValue(value)}');
    });

    return lines.join(' | ');
  }

  String _formatValue(dynamic value) {
    if (value is List<dynamic>) {
      return value.join(', ');
    }
    return '$value';
  }
}
