#!/bin/bash

set -e

declare -i SIGN_OSX=0
declare -i LAUNCHPAD=0
declare -i APT_REPO=1

# Make sure we can GPG sign stuff (eg, ask for yubikey PIN first)
# @TODO: maybe obtain the default key name and email here, and pass it down via ARGS to the Dockerfile.
echo "not important" | gpg --sign --armor

# Build the packages themselves.
docker build -t adoptopenjdk/deb:latest -f Dockerfile .

# Build the exfiltrator image.
docker build -t adoptopenjdk/exfiltrator:latest -f Dockerfile.exfiltrator .

# Build the launchpad utility image.
[[ ${LAUNCHPAD} -gt 0 ]] && docker build -t adoptopenjdk/launchpad:latest -f Dockerfile.launchpad .

# Build the reprepro utility image.
[[ ${APT_REPO} -gt 0 ]] && docker build -t adoptopenjdk/reprepro:latest -f Dockerfile.reprepro .

# Clear the local dir.
rm -rf ${PWD}/exfiltrated

# Run the utility image to copy over the packages to local system, using the "to_sign" directory as volume
docker run -it -v ${PWD}/exfiltrated/:/exfiltrate_to adoptopenjdk/exfiltrator:latest
# Now the local ${PWD}/exfiltrated dir contains all the packages. Unsigned!

# sign the source packages for launchpad
if [[ ${SIGN_OSX} -gt 0 ]]; then
  osx/debsign_osx.sh --no-conf -S exfiltrated/sourcepkg/*_source.changes
  # Now the local ${PWD}/exfiltrated/sourcepkg contains signed source packages for Launchpad.
fi

# Run the Launchpad utility image, it will upload to Launchpad via dput.
if [[ ${LAUNCHPAD} -gt 0 ]]; then
  docker run -it -v ${PWD}/exfiltrated/sourcepkg/:/to_upload adoptopenjdk/launchpad:latest
  # This is the final stop for Launchpad. Watch it build the source packages there!
fi

# Run the Reprepro utility image, it will create a debian repo from the packages.
if [[ ${APT_REPO} -gt 0 ]]; then
  rm -rf ${PWD}/repo
  mkdir ${PWD}/repo

  # Run a script in the background that watches for signing requests from the container.
  osx/watch_and_sign.sh ${PWD}/repo/please_sign &

  docker run -it -v ${PWD}/exfiltrated/binaries/:/to_repo -v ${PWD}/repo/:/repo adoptopenjdk/reprepro:latest

  # Wait for the watch_and_sign script to stop.
  wait

  # Remove the temp dir
  rm -rf ${PWD}/repo/please_sign
fi
