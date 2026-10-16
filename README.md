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
