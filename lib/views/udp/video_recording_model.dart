class VideoRecording {
  final String filePath;
  final String fileName;
  final DateTime timestamp;
  final int duration; // in seconds
  final String senderIp;

  VideoRecording({
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

  factory VideoRecording.fromJson(Map<String, dynamic> json) {
    return VideoRecording(
      filePath: json['filePath'],
      fileName: json['fileName'],
      timestamp: DateTime.parse(json['timestamp']),
      duration: json['duration'],
      senderIp: json['senderIp'],
    );
  }
}
