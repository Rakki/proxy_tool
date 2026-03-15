import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/connection_log_entry.dart';
import '../widgets/app_gradient_background.dart';
import '../widgets/glass_panel.dart';

class TrafficSnapshot {
  const TrafficSnapshot({
    required this.uploadTotal,
    required this.downloadTotal,
    required this.uploadSpeed,
    required this.downloadSpeed,
  });

  final String uploadTotal;
  final String downloadTotal;
  final String uploadSpeed;
  final String downloadSpeed;
}

class LogsScreen extends StatelessWidget {
  const LogsScreen({
    super.key,
    required this.logsListenable,
    required this.trafficListenable,
    required this.onClearPressed,
  });

  final ValueListenable<List<ConnectionLogEntry>> logsListenable;
  final ValueListenable<TrafficSnapshot> trafficListenable;
  final Future<void> Function() onClearPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: AppGradientBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: 68,
              scrolledUnderElevation: 8,
              elevation: 4,
              title: const Text('Connection logs'),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    await onClearPressed();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  <Widget>[
                    ValueListenableBuilder<TrafficSnapshot>(
                      valueListenable: trafficListenable,
                      builder: (
                        BuildContext context,
                        TrafficSnapshot trafficSnapshot,
                        Widget? child,
                      ) {
                        return _TrafficPanel(trafficSnapshot: trafficSnapshot);
                      },
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<List<ConnectionLogEntry>>(
                      valueListenable: logsListenable,
                      builder: (
                        BuildContext context,
                        List<ConnectionLogEntry> logs,
                        Widget? child,
                      ) {
                        return GlassPanel(
                          borderRadius: BorderRadius.circular(28),
                          padding: const EdgeInsets.all(18),
                          child: logs.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 24),
                                    child: Text(
                                      'No logs yet',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    for (int index = 0; index < logs.length; index++) ...<Widget>[
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        child: SelectableText(
                                          _formatEntry(logs[index]),
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                      if (index != logs.length - 1)
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: Colors.white.withValues(alpha: 0.24),
                                        ),
                                    ],
                                  ],
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEntry(ConnectionLogEntry entry) {
    final String timestamp = _formatTimestamp(entry.timestamp);
    final Iterable<String> dataParts = entry.data.entries
        .where((MapEntry<String, dynamic> entry) => entry.value != null)
        .map(
          (MapEntry<String, dynamic> item) =>
              '${_normalizedKey(item.key)}=${_formatValue(item.value)}',
        );

    final String details = dataParts.isEmpty ? '' : ' • ${dataParts.join(' • ')}';

    return '$timestamp  ${entry.message}$details';
  }

  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
  }

  String _normalizedKey(String key) {
    return switch (key) {
      'tx' => 'tx',
      'rx' => 'rx',
      'up' => 'up',
      'down' => 'down',
      'upSpeed' => 'up/s',
      'downSpeed' => 'down/s',
      'endpoint' => 'endpoint',
      'proxyType' => 'proxy',
      'routingMode' => 'routing',
      'selectedApps' => 'apps',
      'selectedAppsCount' => 'apps',
      'level' => 'level',
      'source' => 'source',
      'exitCode' => 'exit',
      'result' => 'result',
      _ => key,
    };
  }

  String _formatValue(dynamic value) {
    if (value is List<dynamic>) {
      return value.join(', ');
    }

    return '$value';
  }
}

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.trafficSnapshot});

  final TrafficSnapshot trafficSnapshot;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(28),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TrafficMetric(
              label: 'Upload',
              total: trafficSnapshot.uploadTotal,
              speed: trafficSnapshot.uploadSpeed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TrafficMetric(
              label: 'Download',
              total: trafficSnapshot.downloadTotal,
              speed: trafficSnapshot.downloadSpeed,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficMetric extends StatelessWidget {
  const _TrafficMetric({
    required this.label,
    required this.total,
    required this.speed,
  });

  final String label;
  final String total;
  final String speed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            total,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            speed,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
