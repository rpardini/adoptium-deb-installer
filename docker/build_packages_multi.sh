#!/bin/bash

set -e
BASE_DIR=$(pwd)

if [[ "$1" == "debian" ]]; then
  BUILD_SOURCE_PACKAGES=false
  BUILD_BINARY_PACKAGES=true
  TEST_INSTALL_BINARY=false
  TEST_INSTALL_DISTRO=stable
  TEST_INSTALL_ARCH="all"
fi

if [[ "$1" == "ubuntu" ]]; then
  BUILD_SOURCE_PACKAGES=true
  BUILD_BINARY_PACKAGES=false
  TEST_INSTALL_BINARY=false
  TEST_INSTALL_DISTRO=$(lsb_release -c -s)
  TEST_INSTALL_ARCH=$(dpkg --print-architecture)
fi

# Every directory under pwd should be a java version.
for oneJavaVersion in *; do
  cd ${BASE_DIR}/${oneJavaVersion}

  # Every directory under *that* is a distribution (trusty/xenial/etc) we're building for.
  BUILD_BASE_DIR=$(pwd)

  for oneDistribution in *; do
    echo "Building Distribution: $oneDistribution"

    if [[ "a$BUILD_BINARY_PACKAGES" == "atrue" ]]; then
      echo "BINARY $oneJavaVersion $oneDistribution" | figlet 1>&2
      cd ${BUILD_BASE_DIR}/${oneDistribution}
      #eatmydata debuild -us -uc # binary build, no signing. # @TODO: introduce signing!
      eatmydata debuild
      cd ${BUILD_BASE_DIR}

      #ls -laR

      if [[ "a$TEST_INSTALL_BINARY" == "atrue" ]]; then
        # check if we can install these binaries. this serves as a basic sanity check.
        # in practice this only "tests" amd64 packages, and for the distro in the FROM ubuntu:xxx
        # line in the dockerfile, but is better than nothing.
        # @TODO: make this a separate step.
        if [[ "$TEST_INSTALL_DISTRO" == "$oneDistribution" ]]; then
          echo "INSTALL BINARY $oneJavaVersion $oneDistribution" | figlet 1>&2
          dpkg -i adoptium-*-installer_*_${TEST_INSTALL_ARCH}.deb || {
            echo "FAILED $oneJavaVersion" | figlet 1>&2
            exit 1
          }
        fi
      fi

      mv -v adoptium* /binaries/
    fi

    if [[ "a$BUILD_SOURCE_PACKAGES" == "atrue" ]]; then
      echo "SOURCE $oneJavaVersion $oneDistribution" | figlet 1>&2
      cd ${BUILD_BASE_DIR}/${oneDistribution}
      eatmydata debuild -S -us -uc # source-only build, no signing.
      #ls -laR
      cd ${BUILD_BASE_DIR}
      mv -v adoptium* /sourcepkg/
    fi

  done

done
