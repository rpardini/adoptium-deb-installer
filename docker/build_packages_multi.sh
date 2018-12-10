#!/bin/bash

set -e
BASE_DIR=$(pwd)

BUILD_BINARY_PACKAGES=true
TEST_INSTALL_BINARY=false
BUILD_SOURCE_PACKAGES=true

if [[ "$1" == "debian" ]]; then
  BUILD_SOURCE_PACKAGES=false
  TEST_INSTALL_BINARY=false
  TEST_INSTALL_DISTRO=noonecares
  TEST_INSTALL_ARCH="all"
fi

if [[ "$1" == "ubuntu" ]]; then
  TEST_INSTALL_DISTRO=$(lsb_release -c -s)
  BUILD_BINARY_PACKAGES=false
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
      debuild -us -uc # binary build, no signing.
      cd ${BUILD_BASE_DIR}

      if [[ "a$TEST_INSTALL_BINARY" == "atrue" ]]; then
        # check if we can install these binaries. this serves as a basic sanity check.
        # in practice this only "tests" amd64 packages, and for the distro in the FROM ubuntu:xxx
        # line in the dockerfile, but is better than nothing.
        # @TODO: make this a separate step.
        if [[ "$TEST_INSTALL_DISTRO" == "$oneDistribution" ]]; then
          ls -la adoptopenjdk-*-installer_*_${TEST_INSTALL_ARCH}.deb || true
          dpkg -i adoptopenjdk-*-installer_*_${TEST_INSTALL_ARCH}.deb
        fi
      fi

      mv -v adoptopenjdk* /binaries/
    fi

    if [[ "a$BUILD_SOURCE_PACKAGES" == "atrue" ]]; then
      echo "SOURCE $oneJavaVersion $oneDistribution" | figlet  1>&2
      cd ${BUILD_BASE_DIR}/${oneDistribution}
      debuild -S -us -uc # source-only build, no signing.
      cd ${BUILD_BASE_DIR}
      mv -v adoptopenjdk* /sourcepkg/
    fi

  done

done