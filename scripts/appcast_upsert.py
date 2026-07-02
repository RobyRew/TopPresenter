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
    max_items = int(os.environ.get("MAX_ITEMS", "40"))

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

    item = ET.Element("item")
    ET.SubElement(item, "title").text = short
    ET.SubElement(item, sparkle("version")).text = build
    ET.SubElement(item, sparkle("shortVersionString")).text = short
    if channel:
        ET.SubElement(item, sparkle("channel")).text = channel
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

    # Newest first, capped.
    channel_el.insert(_first_item_index(channel_el), item)
    items = channel_el.findall("item")
    for extra in items[max_items:]:
        channel_el.remove(extra)

    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


def _first_item_index(channel_el) -> int:
    for i, child in enumerate(list(channel_el)):
        if child.tag == "item":
            return i
    return len(list(channel_el))


if __name__ == "__main__":
    main()
