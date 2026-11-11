#!/usr/bin/env python3
"""Year-in-review builder for Dabble Me journals.

  build.py stats entries.json [--names "Leo,Silas,Cuchara"]
  build.py build entries.json cards.json out.html [--title "..."] [--no-photos]

entries.json: list of {"id","date":"YYYY-MM-DD","text","hashtags":[],"image_url","pasted"?}.
Set "pasted": true on entries that are someone else's words (a letter, an email);
they count as entries but not toward word counts, longest, or shortest.
"""
import argparse, base64, calendar, collections, datetime as dt, io, json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "..", "assets", "template.html")
MAX_PHOTO_BYTES = 12 * 1024 * 1024


def load(path):
    entries = json.load(open(path))
    seen, out = set(), []
    for e in entries:
        if e["id"] in seen:
            continue
        seen.add(e["id"])
        e["d"] = dt.date.fromisoformat(e["date"][:10])
        e["text"] = e.get("text") or ""
        out.append(e)
    return sorted(out, key=lambda e: (e["d"], str(e["id"])))


def words(t):
    return len(re.findall(r"\S+", re.sub(r"https?://\S+", "", t)))


def label(d):
    return f"{d.strftime('%b')} {d.day}"


def compute(entries, names=()):
    if not entries:
        sys.exit("No entries.")
    first, last = entries[0]["d"], entries[-1]["d"]
    wc = {e["id"]: (0 if e.get("pasted") else words(e["text"])) for e in entries}
    own = [e for e in entries if not e.get("pasted")] or entries
    total = sum(wc.values())
    months = collections.Counter(e["d"].month for e in entries)
    span = list(range(first.month, last.month + 1)) if first.year == last.year else list(range(1, 13))
    by_month = [[calendar.month_name[m][0], months.get(m, 0)] for m in span]
    top_m = max(span, key=lambda m: (months.get(m, 0), -m))
    empty = [calendar.month_name[m] for m in span if not months.get(m)]
    wd = collections.Counter(e["d"].weekday() for e in entries)
    order = [6, 0, 1, 2, 3, 4, 5]
    by_wd = [[["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"][d], wd.get(d, 0)] for d in order]
    weekend = wd.get(5, 0) + wd.get(6, 0)
    top_wd = max(range(7), key=lambda d: wd.get(d, 0))
    if weekend / len(entries) >= 0.5:
        wh, wn = "You’re a weekend writer.", f"{weekend} of {len(entries)} entries landed on a Saturday or Sunday."
    else:
        wh, wn = f"{calendar.day_name[top_wd]}s were your day.", f"{wd[top_wd]} of {len(entries)} entries landed on a {calendar.day_name[top_wd]}."
    photo = {e["date"][:10] for e in entries if e.get("image_url")}
    longest = max(own, key=lambda e: wc[e["id"]])
    shortest = min((e for e in own if wc[e["id"]] > 0), key=lambda e: wc[e["id"]])
    days = sorted({e["d"] for e in entries})
    gaps = sorted(((b - a).days, a, b) for a, b in zip(days, days[1:]))[::-1][:3]
    tags = collections.Counter(t.lower() for e in entries for t in (e.get("hashtags") or []))
    mentions = {}
    for n in names:
        rx = re.compile(r"\b" + re.escape(n) + r"(?:'s|’s)?\b", re.I)
        ents = [e for e in entries if rx.search(e["text"])]
        mentions[n] = {"entries": len(ents), "mentions": sum(len(rx.findall(e["text"])) for e in ents),
                       "photo_dates": sorted({e["date"][:10] for e in ents if e.get("image_url")})}
    pick = lambda pred: sorted(d for d in photo if pred(dt.date.fromisoformat(d)))[:4]
    return {
        "range_label": f"{label(first)} to {label(last)}, {last.year}" if first.year == last.year else f"{first} to {last}",
        "entries": len(entries), "days": len(days), "words": total, "avg_words": round(total / len(own)), "pasted": [label(e["d"]) for e in entries if e.get("pasted")],
        "with_photos": sum(1 for e in entries if e.get("image_url")),
        "by_month": by_month, "top_month_name": calendar.month_name[top_m], "top_month_count": months[top_m],
        "empty_months": empty, "by_weekday": by_wd, "weekday_headline": wh, "weekday_note": wn,
        "top_month_imgs": pick(lambda d: d.month == top_m), "weekend_imgs": pick(lambda d: d.weekday() >= 5),
        "longest": {"date": longest["date"][:10], "label": label(longest["d"]), "words": wc[longest["id"]]},
        "shortest": {"date": shortest["date"][:10], "label": label(shortest["d"]), "words": wc[shortest["id"]],
                     "text": shortest["text"].strip()[:220]},
        "latest_img": max(photo) if photo else None,
        "longest_gaps": [{"days": g, "from": str(a), "to": str(b)} for g, a, b in gaps],
        "hashtags": tags.most_common(10), "hashtag_total": sum(tags.values()),
        "mentions": dict(sorted(mentions.items(), key=lambda kv: -kv[1]["entries"])),
        "photo_dates": sorted(photo),
    }


def fetch_photos(entries):
    try:
        from PIL import Image, ImageOps
    except ImportError:
        print("Pillow missing: pip install pillow. Building without photos.", file=sys.stderr)
        return {}, ["Pillow not installed"]
    out, failed, used = {}, [], 0
    for e in entries:
        url, key = e.get("image_url"), e["date"][:10]
        if not url or key in out:
            continue
        try:
            raw = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "year-in-review"}), timeout=30).read()
            im = ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert("RGB")
            im.thumbnail((760, 760))
            buf = io.BytesIO(); im.save(buf, "JPEG", quality=70, optimize=True)
            if used + buf.tell() > MAX_PHOTO_BYTES:
                failed.append(f"{key} (size cap)"); continue
            used += buf.tell()
            out[key] = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
        except Exception as ex:
            failed.append(f"{key} ({type(ex).__name__})")
    return out, failed


def build(entries, cards, out, title, photos=True):
    st = compute(entries)
    imgs, failed = fetch_photos(entries) if photos else ({}, [])
    rows = [{"id": str(e["id"]), "date": e["date"][:10], "label": label(e["d"]),
             "url": f"https://dabble.me/entries/{e['d'].year}/{e['d'].month}/{e['d'].day}",
             "fallback": (e["text"].strip()[:140] + ("…" if len(e["text"].strip()) > 140 else ""))}
            for e in sorted(entries, key=lambda e: e["d"], reverse=True)]
    cards["summaries"] = {str(k): v for k, v in cards.get("summaries", {}).items()}
    missing = [r["label"] for r in rows if r["id"] not in cards["summaries"]]
    bad = sorted({k for c in cards.get("cards", []) for k in ([i.get("img") for i in c.get("items", []) if isinstance(i, dict)] + (c.get("imgs") or [])) if k and k not in st["photo_dates"]})
    data = {"title": title, "stats": st, "entries": rows, **cards}
    html = open(TEMPLATE).read().replace("__TITLE__", title).replace("__DATA__", json.dumps(data, ensure_ascii=False)).replace("__IMGS__", json.dumps(imgs))
    open(out, "w").write(html)
    print(f"Wrote {out} ({len(html)//1024} KB): {len(entries)} entries, {len(imgs)} photos embedded.")
    if failed: print("Photos not embedded:", ", ".join(failed))
    if missing: print("Entries without a summary (fallback text used):", ", ".join(missing))
    if bad: print("Card image dates with no photo entry:", ", ".join(bad))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stats"); s.add_argument("entries"); s.add_argument("--names", default="")
    b = sub.add_parser("build"); b.add_argument("entries"); b.add_argument("cards"); b.add_argument("out")
    b.add_argument("--title", default=None); b.add_argument("--no-photos", action="store_true")
    a = ap.parse_args()
    ents = load(a.entries)
    if a.cmd == "stats":
        for k, v in compute(ents, [n.strip() for n in a.names.split(",") if n.strip()]).items():
            print(f"{k}: {json.dumps(v, ensure_ascii=False, default=str)}")
    else:
        build(ents, json.load(open(a.cards)), a.out, a.title or f"{ents[-1]['d'].year}, as you wrote it.", not a.no_photos)
