import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("asc_media", Path(__file__).resolve().parents[1] / "sync-asc-media.py")
sync = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = sync
spec.loader.exec_module(sync)


class MockASC:
    def __init__(self):
        self.media = {}
        self.rows = {"en-US": [], "ar-SA": []}
        self.writes = []
        self.serial = 0

    def add(self, ident, data, name, category=sync.STORE, kind="images", poster=None):
        self.media[ident] = (kind, {
            "id": ident, "attributes": {"fileName": name, "referenceName": name, "fileSize": len(data),
            "specId": category + kind, "category": category, "state": "APPROVED", "previewFrameTimeCode": poster}
        }, hashlib.md5(data).hexdigest())

    def __call__(self, *args):
        def arg(flag):
            return args[args.index(flag) + 1]
        if args[:2] == ("versions", "list"):
            return {"data": [{"id": "version", "attributes": {"versionString": "2.0", "appVersionState": "PREPARE_FOR_SUBMISSION"}}]}
        if args[:2] == ("localizations", "list"):
            return {"data": [{"id": loc, "attributes": {"locale": loc}} for loc in self.rows]}
        if args[:2] == ("asset-library", "view"):
            return {"data": {"id": "library"}}
        if args[:2] == ("asset-library", "specs"):
            group = sync.GROUPS["APP_IPHONE_DUO"]
            mappings = [{"placementTypeId": typ, "specMappings": [{"placementGroupId": grp, "specs": [s]}]}
                        for typ, grp, s in [(sync.SHOTS, group, sync.STORE + "images"), (sync.PREVIEW, group, sync.STORE + "videos"),
                                            (sync.HEADER, "DEFAULT_PROFILE", sync.CREATIVE + "videos")]]
            return {"data": [{"attributes": {"placementTypes": mappings}}]}
        if args[:2] == ("api", "GET"):
            return {"data": {"attributes": {"sourceFileChecksum": self.media[args[2].split("/")[-1]][2]}}}
        if args[0] == "asset-library" and args[2] == "list":
            rows = [r for k, r, _ in self.media.values() if k == args[1]]
            if "--reference-name" in args:
                rows = [r for r in rows if r["attributes"]["referenceName"] == arg("--reference-name")]
            return {"data": rows}
        if args[0] == "asset-library" and args[2] == "upload":
            file = Path(arg("--file"))
            asset = "upload-" + file.name
            self.add(asset, file.read_bytes(), file.name, arg("--category"), args[1])
            self.writes.append("upload")
            return {"imageId" if args[1] == "images" else "videoId": asset, "ready": True,
                    "specId": arg("--category") + args[1]}
        if args[:2] == ("localizations", "placements"):
            rows = self.rows[arg("--localization-id")]
            if args[2] == "list":
                data = []
                for typ, group, ident, pid in rows:
                    medium = "image" if self.media[ident][0] == "images" else "video"
                    data.append({"id": pid, "attributes": {"placementType": typ, "placementGroup": group,
                                "mediaType": medium.upper(), "state": "ACTIVE"}, "relationships": {medium: {"data": {"id": ident}}}})
                return {"data": data}
            self.writes.append(args[2])
            if args[2] == "reorder":
                order = arg("--placement-ids").split(",")
                by_id = {r[-1]: r for r in rows}
                sequence = iter(order)
                rows[:] = [by_id[next(sequence)] if r[1] == arg("--placement-group") else r for r in rows]
                return {}
            ident = arg("--image-id" if "--image-id" in args else "--video-id")
            self.serial += 1
            if args[2] == "swap":
                old, = [r for r in rows if r[-1] == arg("--placement-id")]
                rows[rows.index(old)] = (*old[:2], ident, str(self.serial))
            elif args[2] == "create":
                rows.append((arg("--placement-type"), arg("--placement-group"), ident, str(self.serial)))
            else:
                raise AssertionError(args)
            return {}
        raise AssertionError(args)


class IncrementalMediaTests(unittest.TestCase):
    def test_plan_apply_and_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            api = MockASC()
            group = sync.GROUPS["APP_IPHONE_DUO"]
            api.add("a", b"one", "old-a.png")
            api.add("b", b"two", "old-b.png")
            api.add("old", b"obsolete", "03.png")
            api.add("duplicate-b", b"two", "duplicate.png")
            api.add("archived", b"new", "archived.png")
            api.media["archived"][1]["attributes"]["state"] = "ARCHIVED"
            api.add("preview", b"video", "localized.mp4", kind="videos", poster="00:00:05:00")
            api.rows["en-US"] = [(sync.PREVIEW, group, "preview", "preview-pid")] + [
                (sync.SHOTS, group, ident, "pid-" + ident) for ident in ("a", "b", "old")]
            api.rows["ar-SA"] = [(sync.SHOTS, group, "duplicate-b", "arabic-pid")]
            entries = []

            def entry(rel, data, **fields):
                file = root / rel
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(data)
                entries.append(dict(path=rel, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data), **fields))

            for loc in api.rows:
                for slot, data in enumerate((b"two", b"one", b"new"), 1):
                    entry(f"screenshots/{loc}/APP_IPHONE_DUO/{slot:02d}-renamed.png", data)
            entry("promotional-video/Header/shared.mp4", b"header")
            entry("previews/en-US/IPHONE_DUO/demo.mp4", b"video", posterFrameTimeCode="00:00:05.000")
            path = root / "manifest.json"
            path.write_text(json.dumps(dict(appId="app", version="2.0", storefronts=list(api.rows), assets=entries)))
            with patch.object(sync, "asc", api), contextlib.redirect_stdout(io.StringIO()) as out:
                sync.sync(path, False)
                self.assertIn("upload=2", out.getvalue())
                self.assertEqual(api.writes, [])
                # Both uploads finished, but the first placement request was interrupted.
                with patch.object(sync, "apply_group", side_effect=subprocess.CalledProcessError(1, "asc")):
                    with self.assertRaises(subprocess.CalledProcessError):
                        sync.sync(path, True)
                sync.sync(path, True)
                self.assertEqual(api.writes.count("upload"), 2)
                self.assertIn("reorder", api.writes)
                self.assertIn("swap", api.writes)
                self.assertEqual([r[2] for r in api.rows["en-US"] if r[0] == sync.SHOTS][:2], ["b", "a"])
                self.assertIn((sync.SHOTS, group, "duplicate-b", "arabic-pid"), api.rows["ar-SA"])
                api.writes.clear()
                sync.sync(path, True)
                self.assertEqual(api.writes, [])
                self.assertIn("keep=9 assign=0 upload=0", out.getvalue())

    def test_sparse_manifest_preserves_unspecified_slots(self):
        old = [(sync.SHOTS, ("images", str(i)), str(i)) for i in (1, 2, 3)]
        wanted = sync.desired_group(old, {(sync.SHOTS, 2): ("images", "new")})
        self.assertEqual([asset[1] for _, asset in wanted], ["1", "new", "3"])
        with self.assertRaises(ValueError):
            sync.desired_group(old, {(sync.SHOTS, 5): ("images", "gap")})

    def test_shared_video_poster_and_legacy_creative_require_evidence(self):
        api = MockASC()
        data = b"the same movie"
        api.add("preview", data, "old.mp4", kind="videos", poster="00:00:04:00")
        api.add("header", data, "old-header.mp4", kind="videos", category=sync.CREATIVE)
        with patch.object(sync, "asc", api):
            lib = sync.Library("library", {})
            f = sync.File(Path("new.mp4"), len(data), hashlib.sha256(data).hexdigest(),
                          hashlib.md5(data).hexdigest(), "videos", sync.STORE, "00:00:05:00")
            with self.assertRaisesRegex(ValueError, "different shared poster"):
                lib.candidates(f, {sync.STORE + "videos"})
            creative = sync.dataclasses.replace(f, category=sync.CREATIVE, poster="")
            with self.assertRaisesRegex(ValueError, "verified source SHA-256"):
                lib.candidates(creative, {sync.CREATIVE + "videos"})
            lib.hashes["header"] = creative.sha
            self.assertEqual(lib.candidates(creative, {sync.CREATIVE + "videos"}), ["header"])
            self.assertEqual(api.writes, [])


if __name__ == "__main__":
    unittest.main()
