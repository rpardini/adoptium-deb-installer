# The utility image to create a Debian Repository
# It expects a volume to be mounted at /to_repo
FROM debian:jessie
RUN apt-get update && apt-get -y --no-install-recommends install reprepro tree && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hack: use a volume to receive back the signed packages back from the host machine.
# This is just a marker directory to avoid mistakes when mounting volumes.
RUN mkdir -p /to_repo/empty
RUN mkdir -p /repo/empty

# This is the script that does the actual work, from docker run.
COPY docker/create_apt_repo.sh /opt/create_apt_repo.sh
COPY docker/sign_repo_async.sh /opt/sign_repo_async.sh
CMD /opt/create_apt_repo.sh
