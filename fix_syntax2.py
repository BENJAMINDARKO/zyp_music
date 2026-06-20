with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if line.strip() == "];" or line.strip() == "]," and "Stack" not in lines[i-1]:
        # we know line 517 is "],"
        pass

# Actually we know exactly where it is.
# Let's just find the sequence
seq = "        ],\n        ),\n        );\n      },\n    );\n  }\n\n  Widget _buildInlineQueueView"
replacement = "        ],\n        ),\n          ),\n        );\n      },\n    );\n  }\n\n  Widget _buildInlineQueueView"

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    text = f.read()

text = text.replace(seq, replacement)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(text)
