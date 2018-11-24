#!/bin/bash

set -e
BASE_DIR=$(pwd)

# Every directory under pwd should be a java version.
for oneJavaVersion in *; do
  cd ${BASE_DIR}/${oneJavaVersion}

  # Every directory under *that* is a distribution (trusty/xenial/etc) we're building for.
  BUILD_BASE_DIR=$(pwd)

  for oneDistribution in *; do
    echo "Building Distribution: $oneDistribution"

    echo "BINARY $oneJavaVersion $oneDistribution" | figlet
    cd ${BUILD_BASE_DIR}/${oneDistribution}
    debuild -us -uc # binary build, no signing.
    cd ${BUILD_BASE_DIR}

    # check if we can install these binaries. this serves as a basic sanity check.
    # in practive this only "tests" amd64 packages, and for the distro in the FROM ubuntu:xxx
    # line in the dockerfile, but is better than nothing.
    #if [[ "${oneJavaVersion}" == "java-11" ]]; then
      if [[ "$(lsb_release -c -s)" == "$oneDistribution" ]]; then
        dpkg -i adoptopenjdk-java*-installer_*_amd64.deb
      fi
    #fi

    mv -v adoptopenjdk* /binaries/

    echo "$oneJavaVersion $oneDistribution" | figlet
    cd ${BUILD_BASE_DIR}/${oneDistribution}
    debuild -S -us -uc # source-only build, no signing.
    cd ${BUILD_BASE_DIR}
    # we dont need these .build or .buildinfo files, thanks.

    # turns out DPUT needs these guys. I wonder why.
    # rm adoptopenjdk*.build adoptopenjdk*.buildinfo || true # debian does not generate them, so ignore errors
    mv -v adoptopenjdk* /sourcepkg/
  done

done