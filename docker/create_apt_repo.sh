#! /bin/bash
set -e
if [[ ! -d /to_repo/empty ]]; then
  if [[ ! -d /repo/empty ]]; then
    echo "/to_repo is mounted. Creating repository with those packages."
    tree /to_repo
    cd /to_repo
    ls -la *.deb

    # Lets initialize the reprepro config...
    mkdir -p /repo/conf
    cat << EOD > /repo/conf/distributions
Origin: deb.adoptopenjdk.net
Label: deb.adoptopenjdk.net
Codename: stable
Architectures: amd64 ppc64el arm64 armel s390x source
Components: main
Description: AdoptOpenJDK Debian Installer Packages
SignWith: ! /opt/sign_repo_async.sh
EOD

    reprepro -b /repo includedeb stable /to_repo/*.deb

    echo "Repository generated at /repo/"

  else
    echo "Could not find /repo volume."  1>&2
    exit 2
  fi
else
  echo "Could not find /to_repo volume."  1>&2
  exit 1
fi
