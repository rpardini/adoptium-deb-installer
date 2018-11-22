########################################################################################################################
## -- first we build and run the generator, which is responsible for producing all the source packages,
##    for all java versions, for all OS's (debian/ubuntu) and for all distribuitions (xenial/trusty/jessie/etc)
FROM node:10-alpine as generator
# @TODO: get the json from the adoptopenjdk API here, so its docker-layer-cached.

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
#RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
#RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz

WORKDIR /opt/adoptopenjdk/ubuntu
COPY --from=generator /gen/generated/ubuntu /opt/adoptopenjdk/ubuntu
ADD docker/build_packages_multi.sh /opt/adoptopenjdk/
# those will be populated by the build script.
RUN mkdir -p /binaries /sourcepkg
RUN /opt/adoptopenjdk/build_packages_multi.sh


########################################################################################################################
## -- Now its the Debian package builder's turn.
##    We use jessie here, but supposedly any could be used,
##    since the packages are so simple.
FROM debian:jessie as debianBuilder
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
# build-time dependencies
RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release figlet
# install-time dependencies (those are listed in Depends or Pre-Depends in debian/control file)
RUN apt-get -y --no-install-recommends install java-common wget locales ca-certificates

# Pre-download and (docker-layer-)cache this as a way to 1) test local file support and 2) alleviate the load of developing against github
#RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
#RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz

WORKDIR /opt/adoptopenjdk/debian
COPY --from=generator /gen/generated/debian /opt/adoptopenjdk/debian
ADD docker/build_packages_multi.sh /opt/adoptopenjdk/
# those will be populated by the build script.
RUN mkdir -p /binaries /sourcepkg
RUN /opt/adoptopenjdk/build_packages_multi.sh



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
COPY --from=debianBuilder /sourcepkg/* /sourcepkg/debian/
RUN tree /sourcepkg/

### # Build the binary .debs. This is for testing only. -us -uc takes GPG out of the picture.
### RUN debuild -us -uc
###
### # Ok, take the resulting stuff out of there, moving it to /binaries
### RUN mkdir -p /binaries && mv -v /opt/adoptopenjdk/adoptopenjdk* /binaries/
###
### # Build the source package. This will be later used for signing and uploading to launchpad. -us -uc takes GPG out of the picture.
### RUN debuild -S -us -uc
###
### # Move the resulting to /sourcepkg
### RUN mkdir -p /sourcepkg && mv -v /opt/adoptopenjdk/adoptopenjdk* /sourcepkg/
###
### # El-quicko install just to make sure everything is working, at least for amd64/bionic
### RUN dpkg -i /binaries/*installer*.deb
### RUN dpkg -i /binaries/*set-default*.deb
### RUN dpkg -i /binaries/*unlimited*.deb
###
### # Just some sanity tests.
### RUN java -version
### RUN javac -version
###
###
### # Hack: use volumes to "exfiltrate" the source files back to the host machine.
### RUN mkdir -p /presign/empty
###
### # Hack: use a volume to receive back the signed source files back from the host machine.
### RUN mkdir -p /postsign/empty
###
### # This is a very hackish script to copy from/to the presign/postsign.
### COPY docker/sign_upload.sh /opt/sign_upload.sh
###
### CMD /opt/sign_upload.sh
###
### # curl "https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk8?os=linux&heap_size=normal&openjdk_impl=hotspot&type=jdk" > jdk.json
###
### # On Launchpad:
### #  AMD x86-64 (amd64)
### #  ARM ARMv8 (arm64)
### #  PowerPC64 Little-Endian (ppc64el)
### #  IBM System z (s390x)
###