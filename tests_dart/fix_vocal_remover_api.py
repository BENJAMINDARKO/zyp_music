import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

content = content.replace('VocalRemoverService.vocalAttenuation', 'VocalRemoverService().vocalReductionFactor')
content = content.replace('VocalRemoverService.vocalAttenuation = val;', 'VocalRemoverService().setVocalReduction(val);')

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)
