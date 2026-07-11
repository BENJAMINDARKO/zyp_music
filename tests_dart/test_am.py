import json

with open("apple_music.html", "r") as f:
    html = f.read()

start = html.find('<script type="application/json" id="serialized-server-data">') + len('<script type="application/json" id="serialized-server-data">')
end = html.find('</script>', start)
data = json.loads(html[start:end])

def find_keys(d, key, path=""):
    if isinstance(d, dict):
        if key in d:
            print(f"Found {key} at {path}: {d[key]}")
        for k, v in d.items():
            find_keys(v, key, path + f"['{k}']")
    elif isinstance(d, list):
        for i, item in enumerate(d):
            find_keys(item, key, path + f"[{i}]")

find_keys(data, 'seoData', "root")
