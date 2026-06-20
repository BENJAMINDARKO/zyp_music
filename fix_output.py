import re

with open('lib/ui/widgets/audio_output_selector.dart', 'r') as f:
    content = f.read()

target = """bool hasBluetooth = devices.any((d) => d.type.toString().toLowerCase().contains('bluetooth') || d.type.toString().toLowerCase().contains('a2dp'));"""
replacement = """// Only check output devices for Bluetooth
      bool hasBluetooth = devices.any((d) => 
        d.isOutput && 
        (d.type.toString().toLowerCase().contains('bluetooth') || 
         d.type.toString().toLowerCase().contains('a2dp'))
      );"""

content = content.replace(target, replacement)

with open('lib/ui/widgets/audio_output_selector.dart', 'w') as f:
    f.write(content)
