import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

content = content.replace('PhosphorIconsRegular.shuffle', 'PhosphorIconsBold.shuffle')
content = content.replace('PhosphorIconsRegular.repeat', 'PhosphorIconsBold.repeat')
content = content.replace('PhosphorIconsRegular.repeatOnce', 'PhosphorIconsBold.repeatOnce')
content = content.replace('PhosphorIconsRegular.magicWand', 'PhosphorIconsBold.magicWand')
content = content.replace('PhosphorIconsRegular.sparkle', 'PhosphorIconsBold.sparkle')
content = content.replace('PhosphorIconsRegular.skipBack', 'PhosphorIconsBold.skipBack')
content = content.replace('PhosphorIconsRegular.skipForward', 'PhosphorIconsBold.skipForward')
content = content.replace('PhosphorIconsRegular.play', 'PhosphorIconsBold.play')
content = content.replace('PhosphorIconsRegular.pause', 'PhosphorIconsBold.pause')

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)
