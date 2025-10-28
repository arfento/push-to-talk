class VoiceRecording {
  final String filePath;
  final String fileName;
  final DateTime timestamp;
  final int duration; // in seconds
  final String senderIp;

  VoiceRecording({
    required this.filePath,
    required this.fileName,
    required this.timestamp,
    required this.duration,
    required this.senderIp,
  });

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileName': fileName,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration,
      'senderIp': senderIp,
    };
  }

  factory VoiceRecording.fromJson(Map<String, dynamic> json) {
    return VoiceRecording(
      filePath: json['filePath'],
      fileName: json['fileName'],
      timestamp: DateTime.parse(json['timestamp']),
      duration: json['duration'],
      senderIp: json['senderIp'],
    );
  }
}
