import sys

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    text = f.read()

def check():
    stack = []
    lines = text.split('\n')
    
    for i, line in enumerate(lines):
        for j, char in enumerate(line):
            if char in '({[':
                stack.append((char, i+1, j+1))
            elif char in ')}]':
                if not stack:
                    print(f"Unmatched closing '{char}' at line {i+1}, col {j+1}")
                    return
                top, l, c = stack.pop()
                expected = {'(': ')', '{': '}', '[': ']'}[top]
                if char != expected:
                    print(f"Mismatched bracket at line {i+1}, col {j+1}: expected '{expected}' but found '{char}'. Opening bracket was at line {l}, col {c}")
                    return
    
    if stack:
        top, l, c = stack[-1]
        print(f"Unclosed '{top}' starting at line {l}, col {c}")
    else:
        print("All brackets matched!")

check()
