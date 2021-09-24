#!/bin/bash

set -e
BASE_DIR=$(pwd)/generated/$1
DEST_DIR="$(pwd)/packages"
cd "${BASE_DIR}"

if [[ "$1" == "debian" ]]; then
  BUILD_SOURCE_PACKAGES=false
  BUILD_BINARY_PACKAGES=true
fi

if [[ "$1" == "ubuntu" ]]; then
  BUILD_SOURCE_PACKAGES=true
  BUILD_BINARY_PACKAGES=false
fi

# Every directory under pwd should be a java version.
for version in *; do
  echo "Building version: ${version}"
  cd "${BASE_DIR}"/"${version}"
  # Every directory under that is a distribution (trusty/xenial/etc) we're building for.
  BUILD_BASE_DIR="$(pwd)"
  for oneDistribution in *; do
    echo "Building distro: $oneDistribution"
    if [[ "a$BUILD_BINARY_PACKAGES" == "atrue" ]]; then
      echo "::group::BINARY $version $oneDistribution"
      cd "${BUILD_BASE_DIR}"/"${oneDistribution}"
      eatmydata debuild # full build
      cd "${BUILD_BASE_DIR}"
      mkdir -p "${DEST_DIR}/binaries/"
      mv -v adoptium* "${DEST_DIR}/binaries/"
      echo "::endgroup::"
    fi
    if [[ "a$BUILD_SOURCE_PACKAGES" == "atrue" ]]; then
      echo "::group::SOURCE $version $oneDistribution"
      cd "${BUILD_BASE_DIR}"/"${oneDistribution}"
      eatmydata debuild -S  # source-only build
      cd "${BUILD_BASE_DIR}"
      mkdir -p "${DEST_DIR}/sourcepkg/"
      mv -v adoptium* "${DEST_DIR}/sourcepkg/"
      echo "::endgroup::"
    fi
  done
done
