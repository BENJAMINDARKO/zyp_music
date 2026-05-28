class PlaylistNotFoundException implements Exception {
  final String message;
  PlaylistNotFoundException(this.message);
}

class AudioStreamException implements Exception {
  final String message;
  AudioStreamException(this.message);
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}
