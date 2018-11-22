#!/bin/bash

echo "Hello: $@"
BASE_DIR=$(pwd)
echo "pwd: ${BASE_DIR}"
ls -la .

# Every directory under pwd is a distribution (trusty/xenial/etc) we're building for.

for oneDistribution in *; do
  echo "Building Distribution: $oneDistribution"
  echo "$oneDistribution" | figlet
  cd ${BASE_DIR}/${oneDistribution}
  debuild -S -us -uc # do the build, man.
  cd ${BASE_DIR}
  ls -la
done