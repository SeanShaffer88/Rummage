#!/usr/bin/env python3
"""Verify tagged addon bytes before missing-only GitHub release publication (stdlib)."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile


class PublicationError(RuntimeError):
    pass


class ApiError(PublicationError):
    def __init__(self, message, status=None, exit_code=None):
        super().__init__(message)
        self.status, self.exit_code = status, exit_code


class GitHub:
    def __init__(self, repo):
        self.repo = repo

    def api(self, endpoint, body=None, binary=False):
        args = ["gh", "api", "--include", endpoint]
        if binary:
            args += ["-H", "Accept: application/octet-stream"]
        if body is not None:
            args += ["--method", "POST", "--input", "-"]
        r = subprocess.run(args, input=json.dumps(body).encode() if body is not None else None,
                           capture_output=True, timeout=120)
        output, status = r.stdout, None
        while output.startswith(b"HTTP/"):
            match = re.search(br"\r?\n\r?\n", output)
            if not match:
                raise ApiError("Malformed gh API response headers", exit_code=r.returncode)
            headers, output = output[:match.start()], output[match.end():]
            line = headers.splitlines()[0]
            found = re.match(br"HTTP/[^ ]+ ([0-9]{3})", line)
            status = int(found.group(1)) if found else None
        if r.returncode or status is None or not 200 <= status < 300:
            message = r.stderr.decode("utf-8", "replace").strip()
            raise ApiError("gh api %s failed (HTTP %s, exit %s): %s" %
                           (endpoint, status, r.returncode, message), status, r.returncode)
        return output if binary else json.loads(output)

    def tag_commit(self, tag):
        obj = self.api("repos/%s/git/ref/tags/%s" % (self.repo, urllib.parse.quote(tag, safe="")))["object"]
        for _ in range(8):
            if obj["type"] == "commit":
                return obj["sha"]
            if obj["type"] != "tag":
                break
            obj = self.api("repos/%s/git/tags/%s" % (self.repo, obj["sha"]))["object"]
        raise PublicationError("Tag does not resolve to a commit within eight annotated tags")

    def release(self, tag):
        try:
            return self.api("repos/%s/releases/tags/%s" % (self.repo, urllib.parse.quote(tag, safe="")))
        except ApiError as exc:
            if exc.status == 404:
                return None
            raise

    def create(self, tag, notes):
        return self.api("repos/%s/releases" % self.repo,
                        {"tag_name": tag, "name": "Rummage " + tag.removeprefix("v"), "body": notes})

    def download(self, asset):
        return self.api("repos/%s/releases/assets/%s" % (self.repo, asset["id"]), binary=True)

    def upload(self, tag, path):
        r = subprocess.run(["gh", "release", "upload", tag, str(path), "--repo", self.repo],
                           capture_output=True, timeout=120)
        if r.returncode:
            raise ApiError("gh release upload failed (exit %s): %s" %
                           (r.returncode, r.stderr.decode("utf-8", "replace").strip()), exit_code=r.returncode)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_inventory(root):
    files, directories = {}, {"Rummage/"}
    addon = root / "Rummage"
    for path in sorted(addon.rglob("*")):
        if path.is_symlink():
            raise PublicationError("Source symlinks are not supported: " + str(path))
        name = path.relative_to(root).as_posix()
        if path.is_dir():
            directories.add(name + "/")
        elif path.is_file():
            files[name] = path.read_bytes()
    if not files:
        raise PublicationError("Addon source inventory is empty")
    return files, directories


def content_matches(name, actual, expected):
    if actual == expected:
        return True
    path = PurePosixPath(name)
    # Compatibility with the verified historical Windows checkout packages only.
    if path.suffix.lower() not in {".lua", ".toc", ".xml", ".md", ".txt"} and path.name not in {"LICENSE", "COPYING", "COPYRIGHT", "NOTICE"}:
        return False
    if b"\0" in actual or b"\0" in expected or actual.startswith(b"\xef\xbb\xbf") or expected.startswith(b"\xef\xbb\xbf"):
        return False
    try:
        actual.decode("utf-8")
        expected.decode("utf-8")
    except UnicodeError:
        return False
    actual, expected = actual.replace(b"\r\n", b"\n"), expected.replace(b"\r\n", b"\n")
    return b"\r" not in actual and b"\r" not in expected and actual == expected


def verify_zip(data, files, directories):
    import io
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            seen, found = set(), set()
            for info in archive.infolist():
                name = info.filename
                parts = name.rstrip("/").split("/")
                if (info.orig_filename != name or not name or any(ord(c) < 32 for c in name) or "\\" in name or name.startswith("/") or
                        any(p in ("", ".", "..") or ":" in p for p in parts) or
                        PurePosixPath(name).is_absolute() or name in seen):
                    raise PublicationError("Unsafe or duplicate ZIP path: " + repr(name))
                seen.add(name)
                mode = (info.external_attr >> 16) & 0o170000
                if mode == 0o120000 or info.flag_bits & 1:
                    raise PublicationError("Symlink or encrypted ZIP entry: " + name)
                if info.is_dir():
                    if name not in directories:
                        raise PublicationError("Unexpected ZIP directory: " + name)
                elif name not in files or info.file_size > len(files[name]) * 2 or not content_matches(name, archive.read(info), files[name]):
                    raise PublicationError("ZIP file differs from tagged source: " + name)
                else:
                    found.add(name)
            if found != set(files):
                raise PublicationError("ZIP file set differs from tagged source")
    except (zipfile.BadZipFile, RuntimeError, OSError, ValueError) as exc:
        raise PublicationError("Invalid ZIP: " + str(exc)) from exc
    return sha(data)


def verify_checksum(data, name, digest):
    try:
        lines = data.decode("ascii").splitlines()
    except UnicodeError as exc:
        raise PublicationError("Checksum must be ASCII") from exc
    match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *]([^/\\]+)", lines[0]) if len(lines) == 1 else None
    if not match or match.group(2) != name or match.group(1).lower() != digest:
        raise PublicationError("Checksum asset does not match the verified ZIP and exact filename")


def inspect(api, release, tag, commit, zip_name, local_zip, files, directories):
    if release["tag_name"] != tag:
        raise PublicationError("Release tag mismatch")
    target = release.get("target_commitish", "")
    if re.fullmatch(r"[0-9a-fA-F]{40}", target) and target.lower() != commit.lower():
        raise PublicationError("Release target commit differs from the checked tag")
    assets = {}
    for asset in release.get("assets", []):
        if asset["name"] in (zip_name, "SHA256SUMS.txt"):
            if asset["name"] in assets:
                raise PublicationError("Duplicate expected release asset name")
            assets[asset["name"]] = asset
    zip_data = api.download(assets[zip_name]) if zip_name in assets else local_zip
    digest = verify_zip(zip_data, files, directories)
    if "SHA256SUMS.txt" in assets:
        verify_checksum(api.download(assets["SHA256SUMS.txt"]), zip_name, digest)
    return assets, zip_data, digest


def publish(api, root, tag, commit, zip_path, notes, verify_only=False, expected=None):
    files, directories = expected if expected is not None else source_inventory(root)
    local_zip = zip_path.read_bytes()
    verify_zip(local_zip, files, directories)
    verify_checksum((zip_path.parent / "SHA256SUMS.txt").read_bytes(), zip_path.name, sha(local_zip))
    if api.tag_commit(tag) != commit:
        raise PublicationError("Remote tag does not resolve to the exact tagged checkout commit")
    release = api.release(tag)
    if release is None:
        if verify_only:
            raise PublicationError("Release does not exist; verify-only performs no writes")
        try:
            release = api.create(tag, notes)
        except ApiError as exc:
            if exc.status not in (409, 422):
                raise
            release = api.release(tag)
            if release is None:
                raise exc
    for _ in range(4):
        assets, zip_data, digest = inspect(api, release, tag, commit, zip_path.name, local_zip, files, directories)
        missing = [name for name in (zip_path.name, "SHA256SUMS.txt") if name not in assets]
        if not missing:
            return {"tag": tag, "files": len(files), "sha256": digest, "verified": True}
        if verify_only:
            raise PublicationError("Missing release assets (verify-only): " + ", ".join(missing))
        name = missing[0]
        with tempfile.TemporaryDirectory(prefix="rummage-release-") as temp:
            path = Path(temp) / name
            path.write_bytes(local_zip if name == zip_path.name else (digest + "  " + zip_path.name + "\n").encode("ascii"))
            try:
                api.upload(tag, path)
            except ApiError as exc:
                # A competing publisher may have uploaded the same asset. Verify before treating it as success.
                raced = api.release(tag)
                if raced is None:
                    raise exc
                raced_assets, _, _ = inspect(api, raced, tag, commit, zip_path.name, local_zip, files, directories)
                if name not in raced_assets:
                    raise exc
                release = raced
                continue
        release = api.release(tag)
        if release is None:
            raise PublicationError("Release disappeared after asset upload")
    raise PublicationError("Release did not converge after bounded missing-only upload attempts")


def git(root, *args):
    r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, timeout=30)
    if r.returncode:
        raise PublicationError("git failed (exit %s): %s" % (r.returncode, r.stderr.strip()))
    return r.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    try:
        root = args.root.resolve()
        version = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", (root / "Rummage/Rummage.toc").read_text(), re.M)
        if not version or args.tag != "v" + version.group(1):
            raise PublicationError("Tag must exactly match the TOC version")
        commit = git(root, "rev-parse", "HEAD")
        if git(root, "rev-parse", "refs/tags/" + args.tag + "^{commit}") != commit:
            raise PublicationError("HEAD must be the requested existing local tag")
        if git(root, "status", "--porcelain", "--untracked-files=no", "--", "Rummage"):
            raise PublicationError("Addon checkout differs from its tagged commit")
        log = (root / "Rummage/CHANGELOG.md").read_text(encoding="utf-8")
        notes = re.search(r"^## .*?(?=^## |\Z)", log, re.M | re.S).group(0).strip()
        # Immutable Git blobs, not a merely clean/line-ending-normalized working tree, define the payload.
        names = git(root, "ls-tree", "-r", "--name-only", commit, "--", "Rummage").splitlines()
        files, directories = {}, {"Rummage/"}
        for name in names:
            blob = subprocess.run(["git", "-C", str(root), "show", commit + ":" + name], capture_output=True, timeout=30)
            if blob.returncode:
                raise PublicationError("Cannot read tagged blob: " + name)
            files[name] = blob.stdout
            for parent in PurePosixPath(name).parents:
                if str(parent) != ".":
                    directories.add(str(parent) + "/")
        result = publish(GitHub(args.repo), root, args.tag, commit,
                         root / ("dist/Rummage-%s.zip" % version.group(1)), notes, args.verify_only,
                         (files, directories))
        print(json.dumps(result, sort_keys=True))
        return 0
    except (PublicationError, OSError, subprocess.TimeoutExpired, KeyError, json.JSONDecodeError) as exc:
        print("Publication failed: " + str(exc), file=sys.stderr)
        return exc.exit_code if isinstance(exc, ApiError) and exc.exit_code else 1


if __name__ == "__main__":
    sys.exit(main())
