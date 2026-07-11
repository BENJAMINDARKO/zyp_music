import pickle
import os
import json

with open("edits.pkl", "rb") as f:
    edits = pickle.load(f)

os.system("git checkout lib/ui/screens/playing_screen.dart")

with open("lib/ui/screens/playing_screen.dart", "r") as f:
    content = f.read()

def apply_chunk(content, target, replacement, start_line, end_line, allow_multiple):
    lines = content.split('\n')
    start_idx = max(0, start_line - 1)
    end_idx = min(len(lines), end_line)
    
    slice_content = '\n'.join(lines[start_idx:end_idx])
    if target in slice_content:
        count = 0 if allow_multiple else 1
        new_slice = slice_content.replace(target, replacement, count)
        lines = lines[:start_idx] + new_slice.split('\n') + lines[end_idx:]
        return '\n'.join(lines)
    else:
        print(f"  [WARN] Target not found in slice {start_line}-{end_line}")
        if target in content:
            count = 0 if allow_multiple else 1
            print(f"  [INFO] Found globally, replacing...")
            return content.replace(target, replacement, count)
        else:
            print(f"  [ERROR] Target not found anywhere!")
            return content

for idx, name, args in edits:
    if idx > 10784:
        break

    print(f"Applying Step {idx}: {name}")
    if name == "replace_file_content":
        content = apply_chunk(
            content,
            args.get("TargetContent", ""),
            args.get("ReplacementContent", ""),
            args.get("StartLine", 1),
            args.get("EndLine", len(content.split('\n'))),
            args.get("AllowMultiple", False)
        )
    elif name == "multi_replace_file_content":
        chunks = args.get("ReplacementChunks", [])
        if isinstance(chunks, str):
            chunks = json.loads(chunks, strict=False)
        for chunk in chunks:
            content = apply_chunk(
                content,
                chunk.get("TargetContent", ""),
                chunk.get("ReplacementContent", ""),
                chunk.get("StartLine", 1),
                chunk.get("EndLine", len(content.split('\n'))),
                chunk.get("AllowMultiple", False)
            )

with open("lib/ui/screens/playing_screen.dart", "w") as f:
    f.write(content)

print("Recovery complete.")
