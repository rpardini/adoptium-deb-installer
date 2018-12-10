#! /bin/bash

set -e

if [[ ! -d /to_upload/empty ]]; then
  echo "/to_upload is mounted. Uploading packages from there."
  cd /to_upload
  ls -la *_source.changes
  dput --unchecked ppa:rpardini/adoptopenjdk *_source.changes
else
  echo "Could not find /to_upload volume."  1>&2
  exit 1
fi
