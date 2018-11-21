#!/bin/bash

set -e

docker build -t adoptopenjdk/deb:latest .
rm -rf to_sign
docker run -it -v ${PWD}/to_sign/:/presign adoptopenjdk/deb:latest
osx/debsign_osx.sh --no-conf -S to_sign/adoptopenjdk-java8-installer_*_source.changes
docker run -it -v ${PWD}/to_sign/:/postsign adoptopenjdk/deb:latest
