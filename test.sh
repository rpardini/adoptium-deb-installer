#!/bin/bash

set -e
BASE_DIR="$(pwd)"

# Config
VERSION=${VERSION:-adoptium-8-jdk-hotspot}
TEST_IMAGE="${TEST_IMAGE:-ubuntu:hirsute}"

# Run via docker
cat <<EOD | docker run --rm -i -v $(pwd)/packages:/packages -e DEBIAN_FRONTEND=noninteractive "${TEST_IMAGE}" /bin/bash -e
#!/bin/bash
echo "::group::apt update"
apt-get -q update
echo "::endgroup::"

echo "::group::apt install"
apt-get -q -y install /packages/binaries/${VERSION}-installer_*.deb
echo "::endgroup::"

echo -e "\n"

echo "::group::Test java -version"
java -version
echo "::endgroup::"
EOD

echo "Test done."
