import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await AudioSession.instance;
  final devices = await session.getDevices();
  for (var d in devices) {
    print("Device: \${d.id} \${d.isSource} \${d.isSink} \${d.type}");
  }
}
