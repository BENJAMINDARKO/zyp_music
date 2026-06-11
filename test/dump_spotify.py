import urllib.request
response = urllib.request.urlopen("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")
html = response.read().decode('utf-8')

with open("spotify_dump.html", "w") as f:
    f.write(html)
