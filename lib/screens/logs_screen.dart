import 'package:flutter/material.dart';

import '../models/connection_log_entry.dart';
import '../widgets/app_gradient_background.dart';
import '../widgets/glass_panel.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({
    super.key,
    required this.logs,
    required this.onClearPressed,
  });

  final List<ConnectionLogEntry> logs;
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
                  onPressed: logs.isEmpty
                      ? null
                      : () async {
                          await onClearPressed();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white54,
                  ),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(28),
                  padding: const EdgeInsets.all(18),
                  child: logs.isEmpty
                      ? Center(
                          child: Text(
                            'No logs yet',
                            style: theme.textTheme.titleMedium,
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
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
                        ),
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
  }

  String _formatValue(dynamic value) {
    if (value is List<dynamic>) {
      return value.join(', ');
    }

    return '$value';
  }
}
