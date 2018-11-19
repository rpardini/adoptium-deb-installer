FROM ubuntu:xenial

WORKDIR /usr/src
RUN mkdir -p /usr/src/adoptopenjdk-java8-installer
WORKDIR /usr/src/adoptopenjdk-java8-installer

RUN apt-get update
RUN apt-get -y install devscripts build-essential lintian debhelper


COPY debian /usr/src/adoptopenjdk-java8-installer/debian
RUN ls -la
RUN debuild -us -uc
RUN ls -la ../