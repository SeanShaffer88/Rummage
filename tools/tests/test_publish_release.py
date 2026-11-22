#!/usr/bin/env python3
"""Offline publication contract tests: fake API, real ZIP bytes; never contacts GitHub."""
import importlib.util
import io
from pathlib import Path
import tempfile
import sys
import warnings
import unittest
from unittest import mock
from types import SimpleNamespace
import zipfile

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "publish_release.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
COMMIT = "a" * 40


class FakeAPI:
    def __init__(self, assets=None, absent=False):
        self.data = dict(assets or {})
        self.absent, self.writes = absent, []
        self.lookup_error = self.create_error = self.upload_error = None
        self.create_race = self.upload_race = False

    def tag_commit(self, tag):
        return COMMIT

    def release(self, tag):
        if self.lookup_error:
            raise self.lookup_error
        if self.absent:
            return None
        return {"id": 1, "tag_name": tag, "target_commitish": COMMIT,
                "assets": [{"id": name, "name": name} for name in self.data]}

    def create(self, tag, notes):
        self.writes.append(("create", tag))
        if self.create_error:
            raise self.create_error
        self.absent = False
        if self.create_race:
            raise P.ApiError("already exists", 422, 1)
        return self.release(tag)

    def download(self, asset):
        return self.data[asset["id"]]

    def upload(self, tag, path):
        self.writes.append(("upload", path.name))
        if self.upload_error:
            raise self.upload_error
        if path.name in self.data:
            raise AssertionError("Attempted to overwrite a published asset")
        self.data[path.name] = path.read_bytes()
        if self.upload_race:
            raise P.ApiError("asset now exists", 422, 1)


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="rummage-publication-tests-")
        self.root = Path(self.tmp.name)
        (self.root / "Rummage").mkdir()
        (self.root / "Rummage/Test.lua").write_bytes(b"return true\n")
        (self.root / "dist").mkdir()
        self.name = "Rummage-1.2.3.zip"
        self.zip = self.root / "dist" / self.name
        self.zip.write_bytes(self.archive())
        (self.zip.parent / "SHA256SUMS.txt").write_bytes(self.checksum(self.zip.read_bytes()))

    def tearDown(self):
        self.tmp.cleanup()

    def archive(self, content=b"return true\n", year=2020, extra=None, duplicate=False):
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr(zipfile.ZipInfo("Rummage/Test.lua", (year, 1, 1, 0, 0, 0)), content)
            if extra:
                z.writestr(extra, b"bad")
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    z.writestr("Rummage/Test.lua", content)
        return out.getvalue()

    def checksum(self, archive):
        return (P.sha(archive) + "  " + self.name + "\n").encode()

    def run_publish(self, api, verify=False):
        return P.publish(api, self.root, "v1.2.3", COMMIT, self.zip, "Notes", verify)

    def complete(self, archive=None):
        archive = archive or self.zip.read_bytes()
        return {self.name: archive, "SHA256SUMS.txt": self.checksum(archive)}

    def test_absent_release_creates_and_uploads_once_then_rerun_is_read_only(self):
        api = FakeAPI(absent=True)
        self.assertTrue(self.run_publish(api)["verified"])
        self.assertEqual(api.writes, [("create", "v1.2.3"), ("upload", self.name), ("upload", "SHA256SUMS.txt")])
        api.writes.clear()
        self.run_publish(api)
        self.assertEqual(api.writes, [])

    def test_complete_existing_different_timestamp_is_valid_and_untouched(self):
        remote = self.archive(year=2024)
        self.assertNotEqual(remote, self.zip.read_bytes())
        api = FakeAPI(self.complete(remote))
        result = self.run_publish(api)
        self.assertEqual(result["sha256"], P.sha(remote))
        self.assertEqual(api.writes, [])

    def test_missing_checksum_uses_verified_existing_archive_hash(self):
        remote = self.archive(year=2024)
        api = FakeAPI({self.name: remote})
        self.run_publish(api)
        self.assertEqual(api.writes, [("upload", "SHA256SUMS.txt")])
        self.assertEqual(api.data["SHA256SUMS.txt"], self.checksum(remote))

    def test_missing_zip_with_matching_checksum_adds_only_zip(self):
        api = FakeAPI({"SHA256SUMS.txt": self.checksum(self.zip.read_bytes())})
        self.run_publish(api)
        self.assertEqual(api.writes, [("upload", self.name)])

    def test_checksum_without_zip_that_cannot_match_local_bytes_fails_before_write(self):
        api = FakeAPI({"SHA256SUMS.txt": self.checksum(self.archive(year=2024))})
        with self.assertRaises(P.PublicationError):
            self.run_publish(api)
        self.assertEqual(api.writes, [])

    def test_remote_changed_content_even_matching_checksum_fails_before_write(self):
        for data in (self.archive(b"evil"), self.archive(extra="Rummage/Extra.lua"), b"not zip"):
            with self.subTest(data=data[:20]):
                api = FakeAPI(self.complete(data))
                with self.assertRaises(P.PublicationError):
                    self.run_publish(api)
                self.assertEqual(api.writes, [])

    def test_missing_file_and_unsafe_or_duplicate_archive_paths_are_rejected(self):
        for data in (self.archive(extra="../bad"), self.archive(extra="/bad"), self.archive(extra="Rummage\\bad"),
                     self.archive(duplicate=True)):
            with self.subTest(data=data[:20]):
                with self.assertRaises(P.PublicationError):
                    self.run_publish(FakeAPI(self.complete(data)))
        empty = io.BytesIO()
        with zipfile.ZipFile(empty, "w"):
            pass
        with self.assertRaises(P.PublicationError):
            self.run_publish(FakeAPI(self.complete(empty.getvalue())))

    def test_nul_truncated_names_and_symlink_attributes_are_rejected(self):
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as archive:
            archive.writestr("Rummage/Test.luaX", b"return true\n")
        malicious = out.getvalue().replace(b"Rummage/Test.luaX", b"Rummage/Test.lua\0")
        with self.assertRaises(P.PublicationError):
            self.run_publish(FakeAPI(self.complete(malicious)))
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as archive:
            item = zipfile.ZipInfo("Rummage/Test.lua")
            item.create_system = 3
            item.external_attr = 0o120777 << 16
            archive.writestr(item, b"return true\n")
        with self.assertRaises(P.PublicationError):
            self.run_publish(FakeAPI(self.complete(out.getvalue())))

    def test_wrong_checksum_name_hash_or_extra_lines_fail_before_writes(self):
        for checksum in (b"0" * 64 + b"  wrong.zip\n", b"0" * 64 + b"  " + self.name.encode() + b"\n", self.checksum(self.zip.read_bytes()) * 2):
            api = FakeAPI({self.name: self.zip.read_bytes(), "SHA256SUMS.txt": checksum})
            with self.assertRaises(P.PublicationError):
                self.run_publish(api)
            self.assertEqual(api.writes, [])

    def test_network_or_permission_lookup_failure_is_never_treated_as_absence(self):
        for status in (None, 401, 403, 429, 500):
            api = FakeAPI(absent=True)
            api.lookup_error = P.ApiError("lookup failed", status, 7)
            with self.assertRaises(P.ApiError):
                self.run_publish(api)
            self.assertEqual(api.writes, [])

    def test_create_and_upload_races_are_reread_and_verified(self):
        api = FakeAPI(absent=True)
        api.create_race = api.upload_race = True
        self.assertTrue(self.run_publish(api)["verified"])
        self.assertEqual(len(api.writes), 3)

    def test_failed_upload_without_raced_asset_fails_and_retains_exit_code(self):
        api = FakeAPI()
        api.upload_error = P.ApiError("network", None, 9)
        with self.assertRaises(P.ApiError) as failure:
            self.run_publish(api)
        self.assertEqual(failure.exception.exit_code, 9)
        self.assertEqual(api.data, {})

    def test_verify_only_is_zero_mutation_and_requires_complete_assets(self):
        api = FakeAPI(self.complete())
        self.assertTrue(self.run_publish(api, True)["verified"])
        self.assertEqual(api.writes, [])
        for api in (FakeAPI(absent=True), FakeAPI({self.name: self.zip.read_bytes()})):
            with self.assertRaises(P.PublicationError):
                self.run_publish(api, True)
            self.assertEqual(api.writes, [])

    def test_remote_tag_or_release_target_mismatch_fails_without_mutation(self):
        api = FakeAPI(self.complete())
        api.tag_commit = lambda tag: "b" * 40
        with self.assertRaises(P.PublicationError):
            self.run_publish(api)
        self.assertEqual(api.writes, [])
        api = FakeAPI(self.complete())
        original = api.release
        def release(tag):
            value = original(tag); value["target_commitish"] = "b" * 40; return value
        api.release = release
        with self.assertRaises(P.PublicationError):
            self.run_publish(api)
        self.assertEqual(api.writes, [])

    def test_historical_utf8_text_crlf_checkout_is_verified_without_overwrite(self):
        remote = self.archive(b"return true\r\n")
        api = FakeAPI(self.complete(remote))
        result = self.run_publish(api)
        self.assertEqual(result["sha256"], P.sha(remote))
        self.assertEqual(api.writes, [])
        self.assertTrue(P.content_matches("Rummage/LICENSE", b"License\r\n", b"License\n"))
        self.assertTrue(P.content_matches("Rummage/Test.lua", b"return true\n", b"return true\r\n"))

    def test_eol_compatibility_never_accepts_binary_encoding_or_non_eol_changes(self):
        cases = [
            ("Rummage/Icon.png", b"image\r\n", b"image\n"),
            ("Rummage/unknown.asset", b"text\r\n", b"text\n"),
            ("Rummage/Test.lua", b"a\0b\r\n", b"a\0b\n"),
            ("Rummage/Test.lua", b"a\xff\r\n", b"a\xff\n"),
            ("Rummage/Test.lua", b"\xef\xbb\xbfreturn true\r\n", b"return true\n"),
            ("Rummage/Test.lua", b"return false\r\n", b"return true\n"),
            ("Rummage/Test.lua", b"return true\r", b"return true\n"),
        ]
        for name, actual, expected in cases:
            with self.subTest(name=name, actual=actual):
                self.assertFalse(P.content_matches(name, actual, expected))
        api = FakeAPI(self.complete(self.archive(b"return false\r\n")))
        with self.assertRaises(P.PublicationError):
            self.run_publish(api)
        self.assertEqual(api.writes, [])

    def test_cli_adapter_only_treats_actual_http_404_as_absence(self):
        api = P.GitHub("Owner/Repo")
        for status in (401, 403, 429, 500):
            reply = SimpleNamespace(returncode=1, stdout=("HTTP/2.0 %s Error\r\nContent-Type: application/json\r\n\r\n{}" % status).encode(), stderr=b"denied")
            with mock.patch.object(P.subprocess, "run", return_value=reply):
                with self.assertRaises(P.ApiError) as result:
                    api.release("v1.2.3")
                self.assertEqual(result.exception.status, status)
        reply = SimpleNamespace(returncode=1, stdout=b"HTTP/2.0 404 Not Found\r\n\r\n{}", stderr=b"not found")
        with mock.patch.object(P.subprocess, "run", return_value=reply):
            self.assertIsNone(api.release("v1.2.3"))
        reply = SimpleNamespace(returncode=7, stdout=b"", stderr=b"network mentions 404 but has no HTTP response")
        with mock.patch.object(P.subprocess, "run", return_value=reply):
            with self.assertRaises(P.ApiError) as result:
                api.release("v1.2.3")
            self.assertIsNone(result.exception.status)
            self.assertEqual(result.exception.exit_code, 7)

    def test_cli_adapter_resolves_annotated_tag_and_preserves_download_bytes(self):
        api = P.GitHub("Owner/Repo")
        calls = []
        def fake(endpoint, body=None, binary=False):
            calls.append(endpoint)
            return {"object": {"type": "tag", "sha": "tagobject"}} if "/ref/" in endpoint else {"object": {"type": "commit", "sha": COMMIT}}
        api.api = fake
        self.assertEqual(api.tag_commit("v1.2.3"), COMMIT)
        self.assertEqual(len(calls), 2)
        api = P.GitHub("Owner/Repo")
        payload = b"PK\x00\xff\r\nHTTP/fake"
        reply = SimpleNamespace(returncode=0, stdout=b"HTTP/2.0 200 OK\r\nContent-Type: application/octet-stream\r\n\r\n" + payload, stderr=b"")
        with mock.patch.object(P.subprocess, "run", return_value=reply):
            self.assertEqual(api.download({"id": 9}), payload)

    def test_duplicate_expected_asset_names_are_not_overwritten_or_trusted(self):
        api = FakeAPI(self.complete())
        original = api.release
        def release(tag):
            value = original(tag); value["assets"].append(dict(value["assets"][0])); return value
        api.release = release
        with self.assertRaises(P.PublicationError):
            self.run_publish(api)
        self.assertEqual(api.writes, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
