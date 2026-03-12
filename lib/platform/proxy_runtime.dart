import 'package:flutter/services.dart';

import '../models/proxy_connection.dart';

class ProxyRuntime {
  static const MethodChannel _channel = MethodChannel('proxy_tool/runtime');
  static const MethodChannel _widgetChannel =
      MethodChannel('proxy_tool/widget');
  static const EventChannel _events =
      EventChannel('proxy_tool/runtime_events');

  static Future<void> start(ProxyConnection connection) {
    return _channel.invokeMethod<void>(
      'startProxy',
      connection.toMap(),
    );
  }

  static Future<void> stop() {
    return _channel.invokeMethod<void>('stopProxy');
  }

  static Future<void> syncWidgetState({
    Map<String, Object?>? connection,
    required bool isActive,
  }) {
    return _widgetChannel.invokeMethod<void>(
      'syncWidgetState',
      <String, Object?>{
        'connection': connection,
        'isActive': isActive,
      },
    );
  }

  static Future<void> clearWidgetState() {
    return _widgetChannel.invokeMethod<void>('clearWidgetState');
  }

  static Future<Map<String, dynamic>> getWidgetState() async {
    final dynamic result = await _widgetChannel.invokeMethod<dynamic>(
      'getWidgetState',
    );
    return Map<String, dynamic>.from(
      (result as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
    );
  }

  static Stream<Map<String, dynamic>> runtimeEvents() {
    return _events.receiveBroadcastStream().map((dynamic event) {
      return Map<String, dynamic>.from(event as Map<dynamic, dynamic>);
    });
  }
}
