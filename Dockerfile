########################################################################################################################
## -- first we build and run the generator, which is responsible for producing all the source packages,
##    for all java versions, for all OS's (debian/ubuntu) and for all distribuitions (xenial/trusty/jessie/etc)
FROM node:10-alpine as generator

# First, only package.json and lockfile, so we docker-layer-cache npm dependencies.
ADD generator/package*.json /gen/generator/
WORKDIR /gen/generator
RUN npm install

# Then the rest of the generator app and the templates...
ADD generator /gen/generator
ADD templates /gen/templates
# ... and then run the generator.
RUN node generate.js


########################################################################################################################
## -- Now its the Ubuntu package builder's turn.
##    We use bionic here, but supposedly any could be used,
##    since the packages are so simple.
FROM ubuntu:bionic as ubuntuBuilder
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
# build-time dependencies
RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release figlet
# install-time dependencies (those are listed in Depends or Pre-Depends in debian/control file)
RUN apt-get -y --no-install-recommends install java-common wget locales ca-certificates

# Pre-download and (docker-layer-)cache this as a way to 1) test local file support and 2) alleviate the load of developing against github
RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz

RUN mkdir -p /var/cache/adoptopenjdk-jdk9-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk9-installer/OpenJDK9U-jdk_x64_linux_hotspot_9.0.4_11.tar.gz https://github.com/AdoptOpenJDK/openjdk9-binaries/releases/download/jdk-9.0.4%2B11/OpenJDK9U-jdk_x64_linux_hotspot_9.0.4_11.tar.gz

RUN mkdir -p /var/cache/adoptopenjdk-jdk10-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk10-installer/OpenJDK10_x64_Linux_jdk-10.0.2.13.tar.gz https://github.com/AdoptOpenJDK/openjdk10-releases/releases/download/jdk-10.0.2%2B13/OpenJDK10_x64_Linux_jdk-10.0.2.13.tar.gz

RUN mkdir -p /var/cache/adoptopenjdk-jdk11-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk11-installer/OpenJDK11U-jdk_x64_linux_hotspot_11.0.1_13.tar.gz https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.1%2B13/OpenJDK11U-jdk_x64_linux_hotspot_11.0.1_13.tar.gz



WORKDIR /opt/adoptopenjdk/ubuntu
COPY --from=generator /gen/generated/ubuntu /opt/adoptopenjdk/ubuntu
ADD docker/build_packages_multi.sh /opt/adoptopenjdk/
# those will be populated by the build script.
RUN mkdir -p /binaries /sourcepkg
RUN /opt/adoptopenjdk/build_packages_multi.sh


## ubuntuOnlyForNow ## ########################################################################################################################
## ubuntuOnlyForNow ## ## -- Now its the Debian package builder's turn.
## ubuntuOnlyForNow ## ##    We use jessie here, but supposedly any could be used,
## ubuntuOnlyForNow ## ##    since the packages are so simple.
## ubuntuOnlyForNow ## FROM debian:jessie as debianBuilder
## ubuntuOnlyForNow ## ENV DEBIAN_FRONTEND noninteractive
## ubuntuOnlyForNow ## RUN apt-get update
## ubuntuOnlyForNow ## # build-time dependencies
## ubuntuOnlyForNow ## RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release figlet
## ubuntuOnlyForNow ## # install-time dependencies (those are listed in Depends or Pre-Depends in debian/control file)
## ubuntuOnlyForNow ## RUN apt-get -y --no-install-recommends install java-common wget locales ca-certificates
## ubuntuOnlyForNow ##
## ubuntuOnlyForNow ## # Pre-download and (docker-layer-)cache this as a way to 1) test local file support and 2) alleviate the load of developing against github
## ubuntuOnlyForNow ## #RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
## ubuntuOnlyForNow ## #RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz
## ubuntuOnlyForNow ##
## ubuntuOnlyForNow ## WORKDIR /opt/adoptopenjdk/debian
## ubuntuOnlyForNow ## COPY --from=generator /gen/generated/debian /opt/adoptopenjdk/debian
## ubuntuOnlyForNow ## ADD docker/build_packages_multi.sh /opt/adoptopenjdk/
## ubuntuOnlyForNow ## # those will be populated by the build script.
## ubuntuOnlyForNow ## RUN mkdir -p /binaries /sourcepkg
## ubuntuOnlyForNow ## RUN /opt/adoptopenjdk/build_packages_multi.sh



########################################################################################################################
## -- the final image produced from this Dockerfile
##    is actually a simple Ubuntu image with dput
##    meant to be used to upload the signed stuff
##    to launchpad or a debian repo somewhere.
##    @TODO: maybe it could be `FROM SCRATCH`, and have a separate dput image later.
FROM ubuntu:bionic
RUN apt-get update && apt-get -y --no-install-recommends install dput tree && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /binaries /sourcepkg /sourcepkg/ubuntu
COPY --from=ubuntuBuilder /sourcepkg/* /sourcepkg/ubuntu/
COPY --from=ubuntuBuilder /binaries/* /binaries/ubuntu/
## ubuntuOnlyForNow ## COPY --from=debianBuilder /sourcepkg/* /sourcepkg/debian/
## ubuntuOnlyForNow ## COPY --from=debianBuilder /binaries/* /binaries/debian/
RUN tree /binaries/
RUN tree /sourcepkg/

# Hack: use volumes to "exfiltrate" the source files back to the host machine.
RUN mkdir -p /presign/empty

# Hack: use a volume to receive back the signed source files back from the host machine.
RUN mkdir -p /postsign/empty

# This is a very hackish script to copy from/to the presign/postsign.
COPY docker/sign_upload.sh /opt/sign_upload.sh

CMD /opt/sign_upload.sh
