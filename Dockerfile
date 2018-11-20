FROM ubuntu:xenial

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
# build dependencies
RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release
# install dependencies
RUN apt-get -y --no-install-recommends install java-common wget locales ca-certificates

# Pre-download and cache this as to alleviate the load of developing against github
RUN mkdir -p /var/cache/adoptopenjdk-jdk8-installer
RUN wget --continue -O /var/cache/adoptopenjdk-jdk8-installer/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u192-b12/OpenJDK8U-jdk_x64_linux_hotspot_8u192b12.tar.gz

WORKDIR /opt/build
COPY . /opt/build/
RUN debuild -us -uc

RUN dpkg -i ../*installer*.deb
RUN dpkg -i ../*set-default*.deb
RUN dpkg -i ../*unlimited*.deb

# Some tests...
RUN java -version
RUN javac -version

CMD bash

# curl "https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk8?os=linux&heap_size=normal&openjdk_impl=hotspot&type=jdk" > jdk.json


# On Launchpad:
#  AMD x86-64 (amd64)
#  ARM ARMv8 (arm64)
#  PowerPC64 Little-Endian (ppc64el)
#  IBM System z (s390x)


