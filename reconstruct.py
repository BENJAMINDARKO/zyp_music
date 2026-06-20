import json

# Original file (currently on disk after git checkout)
with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Read the log and apply replacements
with open('/Users/mmm/.gemini/antigravity-ide/brain/5a4f99fb-4a53-4677-807a-c4dcabdfc31e/.system_generated/logs/transcript.jsonl', 'r') as f:
    for line in f:
        try:
            data = json.loads(line)
        except:
            continue
            
        # Stop before git checkout command
        if data.get('type') == 'PLANNER_RESPONSE':
            if 'git checkout' in data.get('content', ''):
                break
            
        if 'tool_calls' in data:
            for call in data['tool_calls']:
                if call['name'] == 'replace_file_content':
                    args = call['args']
                    if 'playing_screen.dart' in args.get('TargetFile', ''):
                        target = args.get('TargetContent', '')
                        replacement = args.get('ReplacementContent', '')
                        if target in content:
                            content = content.replace(target, replacement)
                elif call['name'] == 'multi_replace_file_content':
                    args = call['args']
                    if 'playing_screen.dart' in args.get('TargetFile', ''):
                        for chunk in args.get('ReplacementChunks', []):
                            target = chunk.get('TargetContent', '')
                            replacement = chunk.get('ReplacementContent', '')
                            if target in content:
                                content = content.replace(target, replacement)

with open('lib/ui/screens/playing_screen_reconstructed.dart', 'w') as f:
    f.write(content)

print("Reconstructed file saved.")
