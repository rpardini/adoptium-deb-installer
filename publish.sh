#!/bin/bash

set -e
BASE_DIR="$(pwd)"

# Config
declare -i CLEAN_APT_REPO=${CLEAN_APT_REPO:-0}
declare -i PUSH_APT_REPO=${PUSH_APT_REPO:-0}
declare -i UPLOAD_LAUNCHPAD=${UPLOAD_LAUNCHPAD:-0}

GH_PAGES_BRANCH="${GH_PAGES_BRANCH:-repo-adoptium}"
GH_PAGES_REPO_URL="${GH_PAGES_BRANCH:-git@github.com:rpardini/adoptium-deb-installer.git}"
export PACKAGE_SIGNER_KEYID=${PACKAGE_SIGNER_KEYID:-63FF2EEC3156A973} # For reprepro

echo "::group::Testing signing..."
echo "Testing signing" | gpg --sign --armor || true
echo "::endgroup::"

if [[ ${UPLOAD_LAUNCHPAD} -gt 0 ]]; then
  echo "::group::Uploading Ubuntu (source) packages to Launchpad..."
  cd packages/sourcepkg
  dput --unchecked ppa:rpardini/adoptium-installers ./*_source.changes
  cd "${BASE_DIR}"
  echo "::endgroup::"
fi

if [[ ! -d repo ]]; then
  echo "'repo' dir is not there, cloning..."
  echo "Cloning gh-pages repo at ${PWD}/repo ..."
  git clone --branch "${GH_PAGES_BRANCH}" --single-branch "${GH_PAGES_REPO_URL}" repo
fi

if [[ ${CLEAN_APT_REPO} -gt 0 ]]; then
  echo "Cleaning repo contents..."
  rm -rf repo/conf repo/db repo/dists repo/pool
fi

echo "::group::Creating repo for debian packages..."
./apt_repo.sh
echo "::endgroup::"

# go in there, add everything to git, commit and push it
if [[ ${PUSH_APT_REPO} -gt 0 ]]; then
  echo "::group::Publish repo for debian packages via git/github pages..."
  cd repo
  git add .
  git commit -m "Updating adoptium repo" || true # commit fails if there's nothing to commit
  git push origin "${GH_PAGES_BRANCH}" || true   # push fails if there's nothing to push
  cd "${BASE_DIR}"
  echo "::endgroup::"
fi

echo "Done publishing."
