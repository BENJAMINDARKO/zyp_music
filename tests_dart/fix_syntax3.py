with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    text = f.read()

import re
text = re.sub(r'        \],\n        \),\n        \);\n      \},\n    \);\n  \}', r'        ],\n        ),\n          ),\n        );\n      },\n    );\n  }', text)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(text)
