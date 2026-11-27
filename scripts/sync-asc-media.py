#!/usr/bin/env python3
"""Plan or apply incremental placements from a Moro store-media/manifest.json."""
import argparse
import collections
import dataclasses
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
GROUPS = {"APP_IPHONE_67": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
          "APP_IPHONE_DUO": "IPHONE_DUO_PROFILE"}
SHOTS, PREVIEW = "APP_SCREENSHOT", "APP_PREVIEW"
HEADER, SEARCH = "PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"
STORE, CREATIVE = "APP_SCREENSHOTS_AND_PREVIEWS", "CREATIVE_ASSETS"
READY = {"PREPARE_FOR_SUBMISSION", "APPROVED"}


def asc(*args):
    result = subprocess.run(["asc", *map(str, args), "--output", "json"],
                            stdout=subprocess.PIPE, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def read(path):
    return json.loads(path.read_text())


@dataclasses.dataclass(frozen=True)
class File:
    path: Path
    size: int
    sha: str
    md5: str
    kind: str
    category: str
    poster: str

    @property
    def upload_name(self):
        frame = "-poster-" + self.poster.replace(":", "-") if self.poster else ""
        return f"moro-{self.sha}{frame}{self.path.suffix.lower()}"


def file_digests(path):
    sha, md5 = hashlib.sha256(), hashlib.md5()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
            md5.update(block)
    return sha.hexdigest(), md5.hexdigest()


def load_manifest(path, manifest):
    slots = {}
    locales = set(manifest["storefronts"])
    for entry in manifest["assets"]:
        rel = Path(entry["path"])
        file = (path.parent / rel).resolve()
        if not file.is_relative_to(path.parent) or rel.is_absolute():
            raise ValueError(f"Invalid media path: {rel}")
        sha, md5 = file_digests(file)
        size = file.stat().st_size
        if sha != entry["sha256"] or size != entry["bytes"]:
            raise ValueError(f"Manifest does not match {rel}")
        if rel.parts[0] == "posters":
            continue  # Local reference frames, not separate ASC uploads.
        slot = 1
        poster = ""
        if rel.parts[0] in ("screenshots", "previews"):
            folder, locale, device, name = rel.parts
            typ = SHOTS if folder == "screenshots" else PREVIEW
            group = GROUPS[device if typ == SHOTS else "APP_" + device]
            match = re.match(r"(\d+)[-.]", name)
            slot = entry.get("slot", int(match[1]) if match else 1)
            if not (1 <= slot <= (10 if typ == SHOTS else 3)):
                raise ValueError(f"Invalid slot: {rel}")
            poster = entry.get("posterFrameTimeCode", "")
            if poster and (typ != PREVIEW or not re.fullmatch(r"\d\d:\d\d:\d\d(:\d\d|\.\d{3})", poster)):
                raise ValueError(f"Invalid preview poster time: {rel}")
            targets = [locale]
        elif rel.parts[:2] == ("promotional-video", "Header") and len(rel.parts) == 3:
            typ, group, targets = HEADER, "DEFAULT_PROFILE", sorted(locales)
        elif rel.parts[:2] == ("promotional-video", "Search") and len(rel.parts) == 4:
            typ, group, targets = SEARCH, "DEFAULT_PROFILE", [rel.parts[2]]
        else:
            raise ValueError(f"Unknown media path: {rel}")
        suffix = file.suffix.lower()
        if suffix not in {".png", ".jpg", ".jpeg", ".mp4", ".m4v", ".mov"}:
            raise ValueError(f"Unknown media format: {rel}")
        kind = "images" if suffix in {".png", ".jpg", ".jpeg"} else "videos"
        if (typ == SHOTS and kind != "images") or (typ == PREVIEW and kind != "videos"):
            raise ValueError(f"Wrong media type: {rel}")
        asset = File(file, size, sha, md5, kind,
                     STORE if typ in (SHOTS, PREVIEW) else CREATIVE, poster)
        for loc in targets:
            key = (loc, group, typ, slot)
            if loc not in locales or key in slots:
                raise ValueError(f"Unexpected locale or duplicate slot: {key}")
            slots[key] = asset
    return slots


def known_digests(app):
    # The legacy screenshot/preview receipt IDs are library media IDs, not placement IDs.
    hashes = {}
    for path in (ROOT / "build/releases").glob("*/asc-media-receipt.json"):
        receipt = read(path)
        if str(receipt["appId"]) != app:
            continue
        for loc in receipt["localizations"].values():
            for rows in loc["screenshots"].values():
                for row in rows:
                    hashes[row["id"]] = row["md5"]
            if loc.get("preview"):
                row = loc["preview"]
                hashes[row["id"]] = row["md5"]
        for row in receipt["creativeAssets"].values():
            hashes[row["id"]] = row["sourceSHA256"]
    return hashes


def same_frame(a, b):
    # ASC also returns whole seconds with a zero millisecond or frame suffix.
    def canonical(value):
        return re.sub(r"(:\d\d:\d\d)(?::00|\.000)$", r"\1", value or "")
    return canonical(a) == canonical(b)


class Library:
    def __init__(self, library_id, hashes):
        self.id = library_id
        self.hashes = hashes
        reference, = asc("asset-library", "specs")["data"]
        self.specs = {
            (t["placementTypeId"], m["placementGroupId"]): set(m["specs"])
            for t in reference["attributes"]["placementTypes"] for m in t["specMappings"]
        }
        self.by_size = collections.defaultdict(list)
        for kind in ("images", "videos"):
            for row in asc("asset-library", kind, "list", "--library-id", self.id, "--paginate")["data"]:
                a = row["attributes"]
                self.by_size[kind, a["category"], a["fileSize"]].append(row)

    def candidates(self, file, specs):
        matches = []
        different_posters = []
        unverified = []
        unavailable = []
        for row in self.by_size[file.kind, file.category, file.size]:
            a, ident = row["attributes"], row["id"]
            if a["state"] == "ARCHIVED" or a["specId"] not in specs:
                continue
            managed = a["fileName"] == file.upload_name
            digest = self.hashes.get(ident)
            named_hash = re.fullmatch(r"moro-([0-9a-f]{64})(?:-poster-[0-9.-]+)?\.[a-z0-9]+", a["fileName"])
            if named_hash:
                digest = named_hash[1]
            if not managed and digest is None and file.category == STORE and a["state"] in READY:
                resource = "appScreenshots" if file.kind == "images" else "appPreviews"
                data = asc("api", "GET", f"/v1/{resource}/{ident}", "--query",
                           f"fields[{resource}]=sourceFileChecksum")["data"]
                digest = self.hashes[ident] = data["attributes"].get("sourceFileChecksum") or ""
            if not managed and not digest and file.category == CREATIVE and a["state"] in READY:
                # Older creative assets have no ASC source checksum. A matching size is
                # insufficient to either reuse the file or declare it a new upload.
                unverified.append(ident)
            if not managed and digest not in (file.md5, file.sha):
                continue
            if a["state"] not in READY:
                unavailable.append((ident, a["state"]))
                continue
            if file.poster and not same_frame(file.poster, a.get("previewFrameTimeCode")):
                if not managed:
                    different_posters.append(ident)
                continue
            matches.append(ident)
        if not matches and different_posters:
            raise ValueError(f"{file.path.name}: matching video {different_posters} has a different shared poster")
        if not matches and unavailable:
            raise ValueError(f"{file.path.name}: matching uploads are not ready for placement: {unavailable}")
        if not matches and unverified:
            raise ValueError(f"{file.path.name}: legacy creative {unverified} has the same size; "
                             "supply its verified source SHA-256 with --known-assets before uploading")
        return matches

    def upload(self, file, specs):
        # An immutable, content-based filename makes interrupted runs discoverable in ASC.
        # Resume an uploaded preview whose poster write was interrupted, only if unassigned.
        found = asc("asset-library", file.kind, "list", "--library-id", self.id,
                    "--category", file.category, "--reference-name", file.upload_name, "--paginate")
        previous = [r for r in found["data"] if r["attributes"]["state"] != "ARCHIVED"]
        if previous:
            row, = previous
            ident = row["id"]
            a = row["attributes"]
            if (a["fileName"] != file.upload_name or a["fileSize"] != file.size
                    or a["specId"] not in specs or a["state"] not in READY):
                raise ValueError(f"Check the existing upload {ident} before retrying")
            if not file.poster or same_frame(file.poster, a.get("previewFrameTimeCode")):
                return ident
            if (a["state"] != "PREPARE_FOR_SUBMISSION"
                    or asc("asset-library", "videos", "placements", "--id", ident, "--paginate")["data"]):
                raise ValueError(f"Inspect existing asset {ident} before changing a shared poster")
        else:
            with tempfile.TemporaryDirectory() as tmp:
                named = Path(tmp) / file.upload_name
                shutil.copyfile(file.path, named)
                if file_digests(named)[0] != file.sha:
                    raise ValueError(f"Source changed while syncing {file.path}")
                receipt = asc("asset-library", file.kind, "upload", "--library-id", self.id,
                              "--category", file.category, "--file", named)
            ident = receipt["imageId" if file.kind == "images" else "videoId"]
            if not receipt.get("ready"):
                raise ValueError(f"Asset {ident} has not finished processing")
            if receipt["specId"] not in specs:
                raise ValueError(f"ASC assigned an incompatible specification to {ident}")
        if file.poster:
            asc("asset-library", "videos", "set-poster-frame", "--id", ident, "--time-code", file.poster)
            a = asc("asset-library", "videos", "view", "--id", ident)["data"]["attributes"]
            if not same_frame(file.poster, a.get("previewFrameTimeCode")):
                raise ValueError(f"Poster not yet verified for {ident}; rerun after processing")
        return ident


def get_placements(loc_id):
    data = asc("localizations", "placements", "list", "--localization-id", loc_id,
               "--sort", "placementGroupPosition", "--include", "image,video", "--paginate")["data"]
    groups = collections.defaultdict(list)
    for row in data:
        a = row["attributes"]
        if a["state"] != "ACTIVE":
            raise ValueError(f"Placement {row['id']} is {a['state']}; check its status before syncing")
        media = row["relationships"][a["mediaType"].lower()]["data"]["id"]
        kind = "images" if a["mediaType"] == "IMAGE" else "videos"
        groups[a["placementGroup"]].append((a["placementType"], (kind, media), row["id"]))
    return groups


def desired_group(current, changes):
    # Overlay only manifest slots. Existing previews, later screenshots and other types survive.
    wanted = [(typ, media) for typ, media, _ in current]
    for (typ, slot), media in sorted(changes.items()):
        indices = [i for i, (kind, _) in enumerate(wanted) if kind == typ]
        if slot <= len(indices):
            wanted[indices[slot - 1]] = (typ, media)
        elif slot == len(indices) + 1:
            wanted.insert(indices[-1] + 1 if indices else len(wanted), (typ, media))
        else:
            raise ValueError(f"Missing preceding slot for {typ} {slot}")
    return wanted


def by_type(pairs):
    ordered = collections.defaultdict(list)
    for typ, asset in pairs:
        ordered[typ].append(asset)
    return ordered


def apply_group(loc_id, group, before, wanted):
    command = ("localizations", "placements")
    current = get_placements(loc_id)[group]
    if current != before:
        raise ValueError(f"{loc_id}/{group} changed since planning; run again")
    # Reserve each existing placement once, including items that only moved to another slot.
    remaining = list(current)
    missing = []
    for key in wanted:
        retained = next((r for r in remaining if r[:2] == key), None)
        if retained:
            remaining.remove(retained)
        else:
            missing.append(key)
    for typ, asset in missing:
        kind, ident = asset
        old = next((r for r in remaining if r[0] == typ), None)
        flags = ("--image-id" if kind == "images" else "--video-id", ident, "--placement-type", typ)
        if old and old[1][0] != kind:
            # ASC's atomic swap accepts only like media. Header/Search have one slot.
            asc(*command, "delete", "--id", old[2], "--confirm")
            try:
                asc(*command, "create", "--localization-id", loc_id, *flags, "--placement-group", group)
            except subprocess.CalledProcessError:
                live = [media for t, media, _ in get_placements(loc_id)[group] if t == typ]
                if not live:
                    old_kind, old_id = old[1]
                    asc(*command, "create", "--localization-id", loc_id, "--placement-type", typ,
                        "--placement-group", group, "--image-id" if old_kind == "images" else "--video-id", old_id)
                if asset not in live:
                    raise
            remaining.remove(old)
        elif old:
            asc(*command, "swap", "--localization-id", loc_id, *flags, "--placement-id", old[2], "--confirm")
            remaining.remove(old)
        else:
            asc(*command, "create", "--localization-id", loc_id, *flags, "--placement-group", group)
    refreshed = get_placements(loc_id)[group]
    order = by_type(wanted)
    if by_type(r[:2] for r in refreshed) != order:
        by_key = collections.defaultdict(collections.deque)
        for typ, asset, pid in refreshed:
            by_key[typ, asset].append(pid)
        if collections.Counter(wanted) != collections.Counter(r[:2] for r in refreshed):
            raise ValueError(f"Unexpected placements after writing {loc_id}/{group}; rerun to reconcile")
        # ASC orders slots within their type. Keep the server's interleaving of previews
        # and screenshots when the two types share the same device group.
        sequences = {typ: iter(assets) for typ, assets in order.items()}
        ordered = [by_key[typ, next(sequences[typ])].popleft() for typ, _, _ in refreshed]
        asc(*command, "reorder", "--localization-id", loc_id, "--placement-group", group,
            "--placement-ids", ",".join(ordered))
        if by_type(r[:2] for r in get_placements(loc_id)[group]) != order:
            raise ValueError(f"Unverified placement order: {loc_id}/{group}")


def sync(path, apply, known_assets=None):
    path = path.resolve()
    manifest = read(path)
    slots = load_manifest(path, manifest)
    app, version = str(manifest["appId"]), manifest["version"]
    version_row, = asc("versions", "list", "--app", app, "--version", version, "--platform", "IOS")["data"]
    if version_row["attributes"]["versionString"] != version:
        raise ValueError("Target version mismatch")
    if apply and version_row["attributes"]["appVersionState"] != "PREPARE_FOR_SUBMISSION":
        raise ValueError(f"{version} is not an editable draft")
    localizations = asc("localizations", "list", "--version", version_row["id"], "--paginate")["data"]
    ids = {r["attributes"]["locale"]: r["id"] for r in localizations}
    locales = sorted({k[0] for k in slots})
    with ThreadPoolExecutor(max_workers=3) as pool:
        states = dict(zip(locales, pool.map(get_placements, [ids[loc] for loc in locales])))
    lib_id = asc("asset-library", "view", "--app", app)["data"]["id"]
    hashes = known_digests(app)
    if known_assets:
        index = read(known_assets)
        if str(index["appId"]) != app or not all(re.fullmatch("[0-9a-f]{64}", h) for h in index["assets"].values()):
            raise ValueError("Invalid source checksum index for this app")
        hashes.update(index["assets"])
    library = Library(lib_id, hashes)
    uploads, matches, changes = {}, {}, collections.defaultdict(dict)
    upload_specs = {}
    counts = collections.Counter()
    for (loc, group, typ, slot), file in sorted(slots.items()):
        rows = [m for t, m, _ in states[loc][group] if t == typ]
        here = rows[slot - 1] if slot <= len(rows) else None
        key = (file.category, file.sha, file.poster, file.kind)
        target = (typ, group)
        if (key, target) not in matches:
            matches[key, target] = library.candidates(file, library.specs[target])
        existing = matches[key, target]
        if here and here[1] in existing:
            counts["keep"] += 1
            continue
        if existing:
            media = next((ident for _, ident in rows if ident in existing), existing[0])
        else:
            media = file.category + "/" + uploads.setdefault(key, file).upload_name
            allowed = library.specs[target]
            upload_specs[key] = upload_specs.get(key, allowed) & allowed
            if not upload_specs[key]:
                raise ValueError(f"{file.path.name} has incompatible target specifications")
        changes[loc, group][typ, slot] = (file.kind, media)
        counts["assign"] += 1
        print(f"{loc} {group} {typ} #{slot} <- {media}")
    planned = {k: desired_group(states[k[0]][k[1]], edits) for k, edits in changes.items()}
    if len({(f.kind, f.category, f.sha) for f in uploads.values()}) < len(uploads):
        raise ValueError("The same new video requests different poster frames; choose a shared poster before uploading")
    print(f"{version}: keep={counts['keep']} assign={counts['assign']} upload={len(uploads)}", flush=True)
    if apply:
        uploaded = {(file.kind, file.category + "/" + file.upload_name): (file.kind, library.upload(file, upload_specs[key]))
                    for key, file in uploads.items()}
        for (loc, group), wanted in planned.items():
            actual = [(typ, uploaded.get(asset, asset)) for typ, asset in wanted]
            apply_group(ids[loc], group, states[loc][group], actual)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--known-assets", type=Path, help="verified source SHA-256 index for legacy media")
    parser.add_argument("--apply", action="store_true", help="write the planned changes to the named draft")
    args = parser.parse_args()
    if args.apply:
        lock_path = ROOT / "build" / "asc-media-sync.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            sync(args.manifest, True, args.known_assets)
    else:
        sync(args.manifest, False, args.known_assets)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
