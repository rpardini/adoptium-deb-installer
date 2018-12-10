# The utility image for Launchpad uploads (dput).
# It expects a volume to be mounted at /to_upload
FROM ubuntu:bionic
RUN apt-get update && apt-get -y --no-install-recommends install dput tree && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hack: use a volume to receive back the signed source files back from the host machine.
# This is just a marker directory to avoid mistakes when mounting volumes.
RUN mkdir -p /to_upload/empty

# This is the script that does the actual work, from docker run.
COPY docker/upload_to_launchpad.sh /opt/upload_to_launchpad.sh
CMD /opt/upload_to_launchpad.sh
