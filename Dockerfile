FROM ubuntu:xenial

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update
# build dependencies
RUN apt-get -y --no-install-recommends install devscripts build-essential lintian debhelper fakeroot lsb-release
# install dependencies
RUN apt-get -y --no-install-recommends install java-common wget locales unzip

# @TODO: why unzip?

WORKDIR /opt/build
COPY . /opt/build/
RUN debuild -us -uc

RUN dpkg -i ../*installer*.deb
RUN dpkg -i ../*set-default*.deb
RUN dpkg -i ../*unlimited*.deb
