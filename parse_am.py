import json

with open("apple_music.html", "r") as f:
    html = f.read()

start = html.find('<script type="application/json" id="serialized-server-data">') + len('<script type="application/json" id="serialized-server-data">')
end = html.find('</script>', start)
data = json.loads(html[start:end])

first_item = data.get('data', [])[0]
sections = first_item['data']['sections']
print("Track item structure:")
print(json.dumps(sections[1]['items'][0], indent=2))
