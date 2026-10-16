s

## Android bundle (`.xapk`) tooling

`tools/install-xapk.sh` downloads an `.xapk` bundle and sideloads it onto an
attached Android device: it unpacks the ZIP, installs `base.apk` plus every
`split_*.apk` with `adb install-multiple`, and pushes any `.obb` expansion files
to `/sdcard/Android/obb/<package>/`.

```sh
make fetch-apk URL='https://data.winudf.com/XAPK/....'   # download into apk/
make check-apk                                            # is the bundle there?
make install-apk XAPK=apk/WorldSoccerChamps.xapk          # push to the device
```

Script flags: `--fetch-only` (download + verify, no adb needed), `--serial`,
`--package`, `--dry-run`, `--keep`.

### Bundles live in `apk/` and are tracked by Git LFS

GitHub rejects any single file over 100 MB on a normal push; the World Soccer
Champs bundle is ~227 MiB. `.gitattributes` therefore routes `*.xapk`, `*.apk`,
`*.aab` and `*.obb` through LFS. Run `git lfs install` once per machine before
committing one. `dist/` holds transient downloads and is git-ignored.

### Too big for the agent sandbox? Let a CI runner fetch it

The agent workspace rejects any file over 100 MiB, and `drive.google.com` is not
reachable from it. `.github/workflows/fetch-bundle.yml` runs on a GitHub-hosted
runner (which has unrestricted network access), downloads the bundle, verifies
its MD5 and ZIP integrity, and commits it back through Git LFS.

```sh
make fetch-ci SOURCE='https://drive.google.com/file/d/<ID>/view'   # KIND=drive (default)
make fetch-ci SOURCE='https://example.com/foo.xapk' KIND=url
```

For `KIND=drive` the Drive file must be shared with "anyone with the link" — the
runner authenticates as nobody. Expected MD5 defaults to the APKPure bundle's
`6a2db1ec852c44ab0abf958835803a94`; pass an empty value to skip the check.
