FROM ubuntu:bionic

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
# build dependencies
RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release dput
# install dependencies
RUN apt-get -y --no-install-recommends install java-common wget locales ca-certificates

# Pre-download and (docker-layer-)cache this as a way to 1) test local file support and 2) alleviate the load of developing against github
RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz

WORKDIR /opt/adoptopenjdk/build
COPY debian /opt/adoptopenjdk/build/debian

# Build the binary .debs. This is for testing only. -us -uc takes GPG out of the picture.
RUN debuild -us -uc

# Ok, take the resulting stuff out of there, moving it to /binaries
RUN mkdir -p /binaries && mv -v /opt/adoptopenjdk/adoptopenjdk* /binaries/

# Build the source package. This will be later used for signing and uploading to launchpad. -us -uc takes GPG out of the picture.
RUN debuild -S -us -uc

# Move the resulting to /sourcepkg
RUN mkdir -p /sourcepkg && mv -v /opt/adoptopenjdk/adoptopenjdk* /sourcepkg/

# El-quicko install just to make sure everything is working, at least for amd64/bionic
RUN dpkg -i /binaries/*installer*.deb
RUN dpkg -i /binaries/*set-default*.deb
RUN dpkg -i /binaries/*unlimited*.deb

# Just some sanity tests.
RUN java -version
RUN javac -version


# Hack: use volumes to "exfiltrate" the source files back to the host machine.
RUN mkdir -p /presign/empty

# Hack: use a volume to receive back the signed source files back from the host machine.
RUN mkdir -p /postsign/empty

# This is a very hackish script to copy from/to the presign/postsign.
COPY docker/sign_upload.sh /opt/sign_upload.sh

CMD /opt/sign_upload.sh

# curl "https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk8?os=linux&heap_size=normal&openjdk_impl=hotspot&type=jdk" > jdk.json

# On Launchpad:
#  AMD x86-64 (amd64)
#  ARM ARMv8 (arm64)
#  PowerPC64 Little-Endian (ppc64el)
#  IBM System z (s390x)
