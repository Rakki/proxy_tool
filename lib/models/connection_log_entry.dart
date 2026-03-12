import 'dart:convert';

class ConnectionLogEntry {
  const ConnectionLogEntry({
    required this.message,
    required this.timestamp,
    this.type = 'app',
    this.data = const <String, dynamic>{},
  });

  final String message;
  final DateTime timestamp;
  final String type;
  final Map<String, dynamic> data;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'data': data,
    };
  }

  factory ConnectionLogEntry.fromMap(Map<String, dynamic> map) {
    return ConnectionLogEntry(
      message: map['message'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      type: (map['type'] as String?) ?? 'app',
      data: Map<String, dynamic>.from(
        (map['data'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ConnectionLogEntry.fromJson(String source) {
    return ConnectionLogEntry.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}
