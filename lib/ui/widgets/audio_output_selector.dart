import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:audio_session/audio_session.dart';

class AudioOutputSelector extends StatefulWidget {
  final Color iconColor;
  const AudioOutputSelector({super.key, required this.iconColor});

  @override
  State<AudioOutputSelector> createState() => _AudioOutputSelectorState();
}

class _AudioOutputSelectorState extends State<AudioOutputSelector> {
  List<AudioDevice> _outputDevices = [];
  AudioDevice? _activeDevice;
  Timer? _pollTimer;
  StreamSubscription? _deviceChangeSub;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
    _listenForDeviceChanges();
    // Poll as a fallback since devicesChangedEventStream may not fire on all
    // Android versions.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshDevices();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _deviceChangeSub?.cancel();
    super.dispose();
  }

  Future<void> _listenForDeviceChanges() async {
    try {
      final session = await AudioSession.instance;
      _deviceChangeSub = session.devicesChangedEventStream.listen((_) {
        if (mounted) _refreshDevices();
      });
    } catch (_) {}
  }

  Future<void> _refreshDevices() async {
    try {
      final session = await AudioSession.instance;
      final devices = await session.getDevices();
      final outputs = devices.where((d) => d.isOutput).toList();

      if (!mounted) return;

      // Heuristic: the "active" output is the highest-priority connected
      // output device.  Priority order on Android:
      //   BT A2DP / BT LE  >  Wired headset/phones  >  Built-in speaker
      // We pick the first match in priority order.
      AudioDevice? active;
      for (final d in outputs) {
        final t = d.type;
        if (t == AudioDeviceType.bluetoothA2dp ||
            t == AudioDeviceType.bluetoothLe ||
            t == AudioDeviceType.bluetoothSco) {
          active = d;
          break;
        }
      }
      active ??= outputs.firstWhere(
        (d) =>
            d.type == AudioDeviceType.wiredHeadset ||
            d.type == AudioDeviceType.wiredHeadphones ||
            d.type == AudioDeviceType.usbAudio,
        orElse: () => outputs.firstWhere(
          (d) => d.type == AudioDeviceType.builtInSpeaker,
          orElse: () => outputs.isNotEmpty ? outputs.first : AudioDevice(
            id: 'speaker',
            name: 'Phone Speaker',
            isInput: false,
            isOutput: true,
            type: AudioDeviceType.builtInSpeaker,
          ),
        ),
      );

      setState(() {
        _outputDevices = outputs;
        _activeDevice = active;
      });
    } catch (_) {}
  }

  IconData _iconForType(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothLe:
      case AudioDeviceType.bluetoothSco:
        return PhosphorIconsRegular.bluetoothConnected;
      case AudioDeviceType.wiredHeadset:
      case AudioDeviceType.wiredHeadphones:
        return PhosphorIconsRegular.headphones;
      case AudioDeviceType.usbAudio:
        return PhosphorIconsRegular.usb;
      case AudioDeviceType.hdmi:
      case AudioDeviceType.hdmiArc:
        return PhosphorIconsRegular.monitor;
      case AudioDeviceType.carAudio:
        return PhosphorIconsRegular.car;
      case AudioDeviceType.builtInSpeaker:
      case AudioDeviceType.builtInSpeakerSafe:
      default:
        return PhosphorIconsRegular.speakerHigh;
    }
  }

  String _displayName(AudioDevice device) {
    // The audio_session plugin returns the product name from Android
    // (e.g. "JBL Flip 5", "Galaxy Buds Pro").  Fall back to a
    // human-readable type label when the name is empty or generic.
    final name = device.name.trim();
    if (name.isNotEmpty && name != 'null') return name;
    switch (device.type) {
      case AudioDeviceType.bluetoothA2dp:
      case AudioDeviceType.bluetoothLe:
      case AudioDeviceType.bluetoothSco:
        return 'Bluetooth';
      case AudioDeviceType.wiredHeadset:
        return 'Wired Headset';
      case AudioDeviceType.wiredHeadphones:
        return 'Headphones';
      case AudioDeviceType.usbAudio:
        return 'USB Audio';
      case AudioDeviceType.builtInSpeaker:
      case AudioDeviceType.builtInSpeakerSafe:
        return 'Phone Speaker';
      case AudioDeviceType.builtInEarpiece:
        return 'Earpiece';
      default:
        return 'Speaker';
    }
  }



  @override
  Widget build(BuildContext context) {
    final device = _activeDevice;
    final label = device != null ? _displayName(device) : 'Speaker';
    final icon = device != null ? _iconForType(device.type) : PhosphorIconsRegular.speakerHigh;

    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 680;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8.0 : 12.0,
        vertical: isSmallScreen ? 4.0 : 6.0,
      ),
      decoration: BoxDecoration(
        color: widget.iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: widget.iconColor, size: isSmallScreen ? 14 : 18),
          SizedBox(width: isSmallScreen ? 4 : 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isSmallScreen ? 90 : 120),
            child: Text(
              label,
              style: TextStyle(
                color: widget.iconColor,
                fontSize: isSmallScreen ? 10 : 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
