# Android bundles

Drop the `.xapk` here. Files in this directory are tracked by Git LFS
(see `.gitattributes`) — GitHub refuses any single file over 100 MB on a
plain push, and this bundle is ~227 MiB.

    make fetch-apk URL="https://data.winudf.com/XAPK/...."   # or tools/install-xapk.sh
    make check-apk
    make install-apk XAPK=apk/WorldSoccerChamps.xapk
