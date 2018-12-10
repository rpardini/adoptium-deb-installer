#! /bin/bash

set -e

# Signal the watcher
mkdir -p /repo/please_sign

cat << EOD > /repo/please_sign/params.sh
RELEASE_NEW=../..$1
INRELEASE_NEW=../..$2
RELEASE_GPG=../..$3
EOD

# Now enter a loop and wait for the watcher to complete.
while [[ ! -d /repo/please_sign/done ]]; do
  echo "Waiting for the watcher to finish signing..."
  sleep 1
done

exit 0
