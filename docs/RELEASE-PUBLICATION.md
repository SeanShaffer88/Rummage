# Release Publication Contract

`tools/publish_release.py` uses Python's standard library and the configured GitHub CLI. The release workflow first runs the addon gate, fake-API publication tests, tag/TOC comparison and package creation. Only then may the helper call release creation/upload APIs. The GitHub token remains in the existing workflow environment.

The helper resolves the remote tag (including annotated tags), requires the exact checked local tag/HEAD, and derives expected package file bytes from immutable Git blobs. A published ZIP must contain exactly those `Rummage/` files, with safe unique relative paths and byte-identical contents, except the explicit historical checkout compatibility rule below. Its checksum asset must name the expected archive and match its actual SHA256. Archive timestamps/compression may differ without causing a false content mismatch.

The approved legacy compatibility exception accepts only exact CRLF↔LF checkout differences in UTF-8 files with extensions `.lua`, `.toc`, `.xml`, `.md`, `.txt`, or names `LICENSE`, `COPYING`, `COPYRIGHT`, `NOTICE`. Comparison changes only CRLF pairs to LF; lone CR, BOM differences, NUL-containing data, invalid UTF-8, unlisted extensions and other text changes remain unequal. Binary assets stay byte-exact. The actual published ZIP hash still drives checksum verification; this exception never rewrites an existing archive or asset.

Existing valid complete releases succeed without writes. Existing partial releases are inspected before any missing-only upload; a checksum missing beside an existing ZIP is generated from that verified published ZIP, not a new archive. A checksum without ZIP must agree with the local tagged archive before it can be completed. The helper never deletes releases/assets, overwrites published assets or uses `--clobber`. Unrelated assets are preserved.

Only an actual HTTP 404 means release absence. Authentication, rate-limit, network and malformed-response failures stop with a diagnostic that retains the CLI exit code when provided. A competing create/upload is accepted only after re-reading and validating the resulting release/assets. Upload attempts are bounded. No public release is used to test these paths.

## Interfaces

Publishing is the workflow invocation: `python3 -I tools/publish_release.py --repo Owner/Repo --tag v1.2.3`. Run only from the corresponding clean tagged checkout after producing `dist/Rummage-1.2.3.zip` and `dist/SHA256SUMS.txt` through the existing packager.

Read-only verification: add `--verify-only`; this shares the same tag/source/ZIP/checksum checks and never calls create/upload. It requires the existing release's two expected assets to be complete. The injectable `publish(api, root, tag, commit, zip_path, notes, verify_only=True, expected=None)` interface also supports independently supplied tagged inventories, without a shell or service mutation. Repository roots/destinations are explicit; owned temporary upload files are removed after each call.

Tests: `python3 -I tools/tests/test_publish_release.py`. Nineteen offline cases use fake API responses plus real ZIP bytes to cover new/complete/partial releases, timestamp-only differences, unsafe/corrupt/duplicate/NUL-truncated/symlink archives, mismatched source/checksums/targets, authentication/network errors, annotated tags, raw binary downloads and create/upload races. These tests do not certify live GitHub service behavior. Existing published assets can be checked separately with the read-only mode; no tag or release is created just for verification.
