import 'package:flutter/services.dart';

import '../models/proxy_connection.dart';

class ProxyRuntime {
  static const MethodChannel _channel = MethodChannel('proxy_tool/runtime');
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

  static Stream<Map<String, dynamic>> runtimeEvents() {
    return _events.receiveBroadcastStream().map((dynamic event) {
      return Map<String, dynamic>.from(event as Map<dynamic, dynamic>);
    });
  }
}
