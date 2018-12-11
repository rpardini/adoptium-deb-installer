#! /bin/sh

set -e

if [[ ! -d /exfiltrate_to/empty ]]; then
  echo "Destination volume is mounted. Copying packages there..."
  mkdir -p /exfiltrate_to/sourcepkg /exfiltrate_to/binaries
  cp -vr /sourcepkg/* /exfiltrate_to/sourcepkg/
  cp -vr /binaries/* /exfiltrate_to/binaries/
  echo "Packages copied."
  exit 0
else
  echo "Could not find exfiltrate_to volume."  1>&2
  exit 1
fi
