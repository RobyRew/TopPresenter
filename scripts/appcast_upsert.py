#!/usr/bin/env python3
"""Insert (or replace) one <item> in a Sparkle appcast, newest first. Reusable.

Reads config from env (see publish_appcast.sh) and rewrites $APPCAST in place.
Uses ElementTree with the Sparkle namespace so the file stays valid + minimal.
"""
import os
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def sparkle(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def main() -> None:
    path = os.environ["APPCAST"]
    short = os.environ["SHORT_VERSION"]
    build = os.environ["BUILD_VERSION"]
    url = os.environ["DOWNLOAD_URL"]
    ed_sig = os.environ["ED_SIG"]
    length = os.environ["LENGTH"]
    channel = os.environ.get("CHANNEL", "").strip()
    notes = os.environ.get("NOTES", "").strip()
    min_os = os.environ.get("MIN_OS", "").strip()
    # Per CHANNEL, not per feed. A single cap let 40 rolling-alpha entries
    # push every stable item out of the feed.
    max_per_channel = int(os.environ.get("MAX_ITEMS_PER_CHANNEL", "10"))

    if os.path.exists(path):
        tree = ET.parse(path)
        rss = tree.getroot()
        channel_el = rss.find("channel")
    else:
        rss = ET.Element("rss", {"version": "2.0"})
        channel_el = ET.SubElement(rss, "channel")
        ET.SubElement(channel_el, "title").text = "TopPresenter"
        tree = ET.ElementTree(rss)

    # Drop any existing item for this build version (idempotent re-runs).
    for item in list(channel_el.findall("item")):
        v = item.find(sparkle("version"))
        if v is not None and (v.text or "") == build:
            channel_el.remove(item)

    # Drop the rolling-alpha era. Every push to main used to publish an item
    # whose enclosure was ONE shared URL (releases/download/v<ver>-alpha/…)
    # that the next push overwrote — so all but the newest of them pointed at
    # bytes that no longer existed, with a signature for bytes that no longer
    # existed. Sparkle reports that as "the update is improperly signed".
    # Those items cannot be repaired, only removed; each release now has its
    # own immutable asset URL.
    for item in list(channel_el.findall("item")):
        short_el = item.find(sparkle("shortVersionString"))
        enc_el = item.find("enclosure")
        short_text = (short_el.text or "") if short_el is not None else ""
        url_text = enc_el.get("url", "") if enc_el is not None else ""
        # Both the rolling `-alpha` and the numbered `-alpha.N` before it: every
        # asset from that era was checked and every one returns 404.
        if "-alpha" in short_text or "-alpha" in url_text:
            channel_el.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = short
    ET.SubElement(item, sparkle("version")).text = build
    ET.SubElement(item, sparkle("shortVersionString")).text = short
    if channel:
        ET.SubElement(item, sparkle("channel")).text = channel
    if min_os:
        # Without this a Mac below the deployment target downloads the update,
        # installs it, and cannot launch it.
        ET.SubElement(item, sparkle("minimumSystemVersion")).text = min_os
    if notes:
        desc = ET.SubElement(item, "description")
        desc.text = notes  # ElementTree escapes it safely
    ET.SubElement(item, "pubDate").text = formatdate(localtime=False, usegmt=True)
    enc = ET.SubElement(item, "enclosure")
    enc.set("url", url)
    enc.set("length", length)
    enc.set("type", "application/octet-stream")
    enc.set(sparkle("edSignature"), ed_sig)
    enc.set(sparkle("version"), build)
    enc.set(sparkle("shortVersionString"), short)

    # Newest first, capped PER CHANNEL so stable and beta age independently.
    channel_el.insert(_first_item_index(channel_el), item)
    seen = {}
    for it in list(channel_el.findall("item")):
        ch_el = it.find(sparkle("channel"))
        key = (ch_el.text or "").strip() if ch_el is not None else ""
        seen[key] = seen.get(key, 0) + 1
        if seen[key] > max_per_channel:
            channel_el.remove(it)

    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def _first_item_index(channel_el) -> int:
    for i, child in enumerate(list(channel_el)):
        if child.tag == "item":
            return i
    return len(list(channel_el))


if __name__ == "__main__":
    main()
