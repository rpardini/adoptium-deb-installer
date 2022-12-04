#!/bin/bash

set -e
DEST_DIR="$(pwd)/packages"
os="$1"
jdkVersion="$2"
distribution="$3"

# Some juggling so there are no shared output directories...
BUILD_OUTPUT_DIR="$(pwd)/generated/${os}/${jdkVersion}/build.${os}_${jdkVersion}_${distribution}"
mkdir -p "${BUILD_OUTPUT_DIR}"
cp -rp "generated/${os}/${jdkVersion}/${distribution}" "${BUILD_OUTPUT_DIR}"/
cd "${BUILD_OUTPUT_DIR}/${distribution}"

if [[ "${os}" == "debian" ]]; then
	BUILD_SOURCE_PACKAGES=false
	BUILD_BINARY_PACKAGES=true
fi

if [[ "${os}" == "ubuntu" ]]; then
	BUILD_SOURCE_PACKAGES=true
	BUILD_BINARY_PACKAGES=false
fi

if [[ "a$BUILD_BINARY_PACKAGES" == "atrue" ]]; then
	echo "::group::BINARY $jdkVersion $distribution"
	# For binaries, passing -Zxz to debuild is not enough; see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=998010
	# So there's stuff in debian/rules for this
	eatmydata debuild -Zxz # full build; use xz compression, not zstd (which is default in Ubuntu 22+)
	echo "Build done! Moving packages..."
	mkdir -p "${DEST_DIR}/binaries/"
	file "${BUILD_OUTPUT_DIR}"/adoptium* || true
	mv -v "${BUILD_OUTPUT_DIR}"/adoptium* "${DEST_DIR}/binaries/"
	echo "::endgroup::"
fi

if [[ "a$BUILD_SOURCE_PACKAGES" == "atrue" ]]; then
	echo "::group::SOURCE $jdkVersion $distribution"
	eatmydata debuild -S -Zxz # source-only build; use xz compression, not zstd (which is default in Ubuntu 22+)
	echo "Build done! Moving packages..."
	mkdir -p "${DEST_DIR}/sourcepkg/"
	file "${BUILD_OUTPUT_DIR}"/adoptium* || true
	mv -v "${BUILD_OUTPUT_DIR}"/adoptium* "${DEST_DIR}/sourcepkg/"
	echo "::endgroup::"
fi

# Cleanup
rm -rf "${BUILD_OUTPUT_DIR}"
