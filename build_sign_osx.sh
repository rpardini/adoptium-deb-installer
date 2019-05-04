#!/bin/bash

set -e

declare -i SIGN_OSX=1
declare -i LAUNCHPAD=1
declare -i APT_REPO=1
declare -i PUSH_APT_REPO=1
declare NO_CACHE="--no-cache"
#declare NO_CACHE=""

# Make sure we can GPG sign stuff (eg, ask for yubikey PIN first)
# @TODO: maybe obtain the default key name and email here, and pass it down via ARGS to the Dockerfile.
echo "not important" | gpg --sign --armor
BASEDIR=${PWD}

if [[ "$OSTYPE" == "linux-gnu" ]]; then
    debsign --version || { apt-get -y update; apt-get -y install devscripts; }
fi


if [[ ${APT_REPO} -gt 0 ]]; then
  # clean it
  rm -rf ${PWD}/repo

  # clone the gh-pages branch of this repo in there
  # this assumes ssh-agent/gpg-agent(-ssh) is working, we do it first to minimize pinentry interruptions
  echo "Cloning gh-pages repo at ${PWD}/repo ..."
  git clone --branch gh-pages --single-branch git@github.com:rpardini/adoptopenjdk-deb-installer.git ${PWD}/repo
fi

# Clear the local dirs.
rm -rf ${PWD}/exfiltrated ${PWD}/generated

# Build the packages themselves.
docker build ${NO_CACHE} -t adoptopenjdk/deb:latest -f Dockerfile .

# Build the launchpad utility image.
[[ ${LAUNCHPAD} -gt 0 ]] && docker build ${NO_CACHE} -t adoptopenjdk/launchpad:latest -f Dockerfile.launchpad .

# Build the reprepro utility image.
[[ ${APT_REPO} -gt 0 ]] && docker build ${NO_CACHE} -t adoptopenjdk/reprepro:latest -f Dockerfile.reprepro .

# Run the packages image to copy over the packages to local system, using the "to_sign" directory as volume
docker run -it -v ${PWD}/exfiltrated/:/exfiltrate_to adoptopenjdk/deb:latest
# Now the local ${PWD}/exfiltrated dir contains all the packages. Unsigned!

# Run the reprepro utility image, it will create a debian repo from the packages.
# This is a huge, huge hack necessary because I sign the repo with a hardware token
# on the host machine.
if [[ ${APT_REPO} -gt 0 ]]; then
  # Run a script in the background that watches for signing requests from the container.
  osx/watch_and_sign.sh ${PWD}/repo/please_sign &

  # Run the reprepro utility image
  docker run -it -v ${PWD}/exfiltrated/binaries/:/to_repo -v ${PWD}/repo/:/repo adoptopenjdk/reprepro:latest

  # Wait for the watch_and_sign script to stop.
  wait

  # Remove the temp dir
  rm -rf ${PWD}/repo/please_sign

  # go in there, add everything to git, commit and push it to github (effectively publishing the repo)
  if [[ ${PUSH_APT_REPO} -gt 0 ]]; then
    cd ${PWD}/repo
    git add .
    git commit -m "Updating APT repo"
    git push origin gh-pages
  fi
fi

cd ${BASEDIR}
# sign the source packages for launchpad
if [[ ${SIGN_OSX} -gt 0 ]]; then
  echo "Signing Launchpad source packages locally..."
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    debsign --no-conf -S exfiltrated/sourcepkg/*_source.changes
  else
    osx/debsign_osx.sh --no-conf -S exfiltrated/sourcepkg/*_source.changes
  fi
  # Now the local ${PWD}/exfiltrated/sourcepkg contains signed source packages for Launchpad.
fi

# Run the Launchpad utility image, it will upload to Launchpad via dput.
if [[ ${LAUNCHPAD} -gt 0 ]]; then
  echo "Uploading to Launchpad..."
  docker run -it -v ${PWD}/exfiltrated/sourcepkg/:/to_upload adoptopenjdk/launchpad:latest
  # This is the final stop for Launchpad. Watch it build the source packages there!
fi
