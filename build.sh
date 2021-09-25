#!/bin/bash

set -e
BASE_DIR="$(pwd)"

# Config
declare -i RUN_GENERATOR=${RUN_GENERATOR:-1}

echo "::group::Testing signing..."
echo "Testing signing" | gpg --sign --armor || true
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

cd "${BASE_DIR}"

echo "::group::Packages that will be built..."
find generated -mindepth 3 -maxdepth 3 -type d
echo "::endgroup::"

echo "Now build and sign packages in parallel..."
find generated -mindepth 3 -maxdepth 3 -type d | tr -s "/" '\n' | parallel -N 4 ./debuild.sh {2} {3} {4}

echo "Done building (signed) packages."
