#! /bin/bash
set -e

PACKAGES_DIR="$(pwd)"/packages/binaries
REPO_DIR="$(pwd)"/repo

[[ ! -d "${PACKAGES_DIR}" ]] && echo "Packages dir ${PACKAGES_DIR} is not there." && exit 2
mkdir -p "${REPO_DIR}" "${REPO_DIR}"/pool

echo "Creating repository with packages from ${PACKAGES_DIR} using key ${PACKAGE_SIGNER_KEYID}"
cd "${PACKAGES_DIR}"
ls -la *.deb

# Configure reprepro
mkdir -p ${REPO_DIR}/conf
cat <<EOD >${REPO_DIR}/conf/distributions
Origin: deb.adoptium.net
Label: deb.adoptium.net
Codename: stable
Architectures: amd64 ppc64el arm64 armel s390x source
Components: main
Description: Adoptium Debian Installer Packages
SignWith: ${PACKAGE_SIGNER_KEYID}
EOD

# Determine a list of binary debs to include in the repo
# reprepro does not accept identical package(-names) with different contents (sha1)
# our build does generate different contents (in different runs) and I'd like to keep old versions around
LIST_DEBS_NEW=""
for ONE_DEB in ${PACKAGES_DIR}/*.deb; do
  echo "Considering adding to repo: $ONE_DEB"
  BASE_ONE_DEB=$(basename ${ONE_DEB})
  EXISTING_DEB_IN_REPO=$(find ${REPO_DIR}/pool -type f -name ${BASE_ONE_DEB})
  if [[ "a${EXISTING_DEB_IN_REPO}" == "a" ]]; then
    echo "- New .deb to include in repo: ${BASE_ONE_DEB}"
    LIST_DEBS_NEW="${LIST_DEBS_NEW} ${ONE_DEB}"
  else
    echo "- Existing .deb: ${BASE_ONE_DEB}"
  fi
done

echo "** Final list of DEBs to include: ${LIST_DEBS_NEW}"
if [[ "a${LIST_DEBS_NEW}a" == "aa" ]]; then
  echo "No new packages, nothing to do."
else
  echo "New packages, running reprepro..."
  reprepro -b "${REPO_DIR}" includedeb stable ${LIST_DEBS_NEW} # 'stable' = distro name
  echo "Repository generated at ${REPO_DIR}/"
fi
