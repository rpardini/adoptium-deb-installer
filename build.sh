#!/bin/bash

set -e
BASE_DIR="$(pwd)"

# Config
declare -i RUN_GENERATOR=${RUN_GENERATOR:-1}
declare -i BUILD_PACKAGES=${BUILD_PACKAGES:-1}

echo "::group::Testing signing..."
echo "Testing signing" | gpg --sign --armor
echo "::endgroup::"

if [[ ${RUN_GENERATOR} -gt 0 ]]; then
  if [[ ! -d generator/node_modules ]]; then
    echo "::group::Running npm ci"
    cd generator
    npm ci
    cd "${BASE_DIR}"
    echo "::endgroup::"
  fi

  echo "::group::Running package generator"
  rm -rf generated packages || true
  node generator/generate.js
  echo "::endgroup::"
fi

if [[ ${BUILD_PACKAGES} -gt 0 ]]; then
  ./build_packages.sh ubuntu
  ./build_packages.sh debian
fi


echo "Done building (signed) packages."
