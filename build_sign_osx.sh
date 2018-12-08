#!/bin/bash

set -e

# Make sure we can GPG sign stuff (eg, ask for yubikey PIN first)
echo "not important" | gpg --sign --armor

docker build -t adoptopenjdk/deb:latest .
rm -rf to_sign
docker run -it -v ${PWD}/to_sign/:/presign adoptopenjdk/deb:latest
osx/debsign_osx.sh --no-conf -S to_sign/ubuntu/adoptopenjdk-*-installer_*_source.changes
docker run -it -v ${PWD}/to_sign/:/postsign adoptopenjdk/deb:latest

