#!/bin/bash
# shellcheck disable=SC2002 # My cats are not useless, thank you.

set -e
BASE_DIR="$(pwd)"

# Config
declare -i CLEAN_APT_REPO=${CLEAN_APT_REPO:-0}
declare -i PUSH_APT_REPO=${PUSH_APT_REPO:-0}
declare -i UPLOAD_LAUNCHPAD=${UPLOAD_LAUNCHPAD:-1}

GH_PAGES_BRANCH="${GH_PAGES_BRANCH:-repo-adoptium}"
GH_PAGES_REPO_URL="${GH_PAGES_REPO_URL:-git@github.com:rpardini/adoptium-deb-installer.git}"
export PACKAGE_SIGNER_KEYID=${PACKAGE_SIGNER_KEYID:-63FF2EEC3156A973} # For reprepro

echo "::group::Testing signing..."
echo "Testing signing" | gpg --sign --armor
echo "::endgroup::"

if [[ ! -d repo ]]; then
  echo "'repo' dir is not there, cloning..."
  echo "Cloning gh-pages repo at ${PWD}/repo ..."
  git clone --branch "${GH_PAGES_BRANCH}" --single-branch "${GH_PAGES_REPO_URL}" repo
fi

if [[ ${CLEAN_APT_REPO} -gt 0 ]]; then
  echo "Cleaning repo contents..."
  rm -rf repo/conf repo/db repo/dists repo/pool
fi

if [[ ${UPLOAD_LAUNCHPAD} -gt 0 ]]; then
  echo "::group::Uploading Ubuntu (source) packages to Launchpad..."
  cd packages/sourcepkg

  # Let's not overwhelm launchpad with uploads for unchanged packages.
  # We'll keep a list of the uploaded file names in the apt repo (otherwise unrelated)
  declare -i NUMBER_PACKAGES_TO_UPLOAD
  PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE="${BASE_DIR}/repo/launchpad.list"
  CURRENTLY_GENERATED_LAUNCHPAD_PACKAGES_FILE="${BASE_DIR}/repo/currently_generated_launchpad.list"
  TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE="${BASE_DIR}/repo/to_upload_launchpad.list"

  # Write this-run filenames to the new file...
  find . -type f -name \*.changes | sort -u >"${CURRENTLY_GENERATED_LAUNCHPAD_PACKAGES_FILE}"

  # If the old file does not exist, just do them all.
  if [[ ! -f "${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}" ]]; then
    echo "No previous uploaded packages list, uploading all newly built packages."
    cat "${CURRENTLY_GENERATED_LAUNCHPAD_PACKAGES_FILE}" | sort -u >"${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}"
  else
    # We have a list of previously-uploaded, compare with new one and do only new packages.
    # 'comm' is nice, but it wants sorted inputs.
    comm -13 "${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}" "${CURRENTLY_GENERATED_LAUNCHPAD_PACKAGES_FILE}" >"${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}"
  fi

  NUMBER_PACKAGES_TO_UPLOAD="$(cat "${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}" | wc -l)"
  echo "::notice file=publish.sh::Will upload ${NUMBER_PACKAGES_TO_UPLOAD} to Launchpad."

  if [[ ${NUMBER_PACKAGES_TO_UPLOAD} -gt 0 ]]; then
    echo "- Actually Uploading ${NUMBER_PACKAGES_TO_UPLOAD} to Launchpad..."

    cat "${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}" | xargs dput --unchecked ppa:rpardini/adoptium-installers

    echo "- dput done, marking ${NUMBER_PACKAGES_TO_UPLOAD} packages as uploaded..."
    # This will be pushed together with the apt repo below
    cat "${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}" >>"${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}"
    cat "${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}" | sort -u >"${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}.sorted"
    mv "${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}.sorted" "${PREVIOUSLY_UPLOADED_LAUNCHPAD_PACKAGES_FILE}"
  else
    echo "- Zero packages to upload. Doing nothing."
  fi

  # Cleanup work files
  rm -f "${CURRENTLY_GENERATED_LAUNCHPAD_PACKAGES_FILE}" "${TO_UPLOAD_LAUNCHPAD_PACKAGES_FILE}"

  cd "${BASE_DIR}"
  echo "::endgroup::"
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
