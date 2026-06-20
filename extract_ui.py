import pickle
with open("edits.pkl", "rb") as f:
    edits = pickle.load(f)

for idx, name, args in edits:
    if idx == 10618:
        with open("playing_screen_10618.txt", "w") as out:
            out.write(args.get("ReplacementContent", ""))
        print("Extracted step 10618!")
