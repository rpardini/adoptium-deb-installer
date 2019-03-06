#! /bin/bash

WATCHED_DIR=$1
rm -rf ${WATCHED_DIR}/done
echo "Watching for dir $WATCHED_DIR..."
while [[ ! -d ${WATCHED_DIR} ]]; do
  #echo "Still waiting..."
  sleep 1
done

echo "Great, dir ${WATCHED_DIR} found, lets do the signing."
sleep 2
PARAMS_FILE=${WATCHED_DIR}/params.sh

# Source it...
. ${PARAMS_FILE}

RELEASE_NEW=${WATCHED_DIR}/${RELEASE_NEW}
INRELEASE_NEW=${WATCHED_DIR}/${INRELEASE_NEW}
RELEASE_GPG=${WATCHED_DIR}/${RELEASE_GPG}

echo "RELEASE_NEW: $RELEASE_NEW "
echo "INRELEASE_NEW: $INRELEASE_NEW "
echo "RELEASE_GPG: $RELEASE_GPG "

echo "Signing ${RELEASE_NEW} ..."
gpg -a -s --clearsign ${RELEASE_NEW} # clearsign
mv ${RELEASE_NEW}.asc ${INRELEASE_NEW}
echo "Done signing ${RELEASE_NEW}."

echo "Signing ${RELEASE_GPG} ..."
gpg -a -b -s ${RELEASE_NEW}
mv ${RELEASE_NEW}.asc ${RELEASE_GPG}
echo "Done signing ${RELEASE_GPG}."

echo "Signing is done!"
sleep 2
# Signal that we're done.
mkdir -p ${WATCHED_DIR}/done
