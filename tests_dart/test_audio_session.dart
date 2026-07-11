import 'package:audio_session/audio_session.dart';
void main() async {
  final session = await AudioSession.instance;
  final devices = await session.getDevices();
  for (var d in devices) {
    print(d.type.name);
  }
}
