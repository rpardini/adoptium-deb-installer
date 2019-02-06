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

    # Determine a list of binary debs to include in the repo
    # reprepro does not accept identical package(-names) with different contents (sha1)
    # our build does generate different contents (in different runs) due to file dates and so. @TODO
    LIST_DEBS_NEW=""
    for ONE_DEB in /to_repo/*.deb; do
      echo "Considering adding to repo: $ONE_DEB"
      BASE_ONE_DEB=$(basename ${ONE_DEB})
      EXISTING_DEB_IN_REPO=$(find /repo/pool -type f -name ${BASE_ONE_DEB})
      if [[ "a${EXISTING_DEB_IN_REPO}" == "a" ]]; then
        echo "New DEB: ${ONE_DEB}"
        LIST_DEBS_NEW="${LIST_DEBS_NEW} ${ONE_DEB}"
      else
        echo "DEB already in repo: ${ONE_DEB}"
      fi
    done

    echo "Final list of DEBs to include: ${LIST_DEBS_NEW}"
    reprepro -b /repo includedeb stable ${LIST_DEBS_NEW}

    echo "Repository generated at /repo/"

  else
    echo "Could not find /repo volume."  1>&2
    exit 2
  fi
else
  echo "Could not find /to_repo volume."  1>&2
  exit 1
fi
