# Debian/Ubuntu installer packages for Eclipse Adoptium

This uses the Eclipse Adoptium API to produce Ubuntu/Debian packages which download and install Eclipse Adoptium from
their official releases.

- Ubuntu: check out [ppa:rpardini/adoptium-installers](https://launchpad.net/~rpardini/+archive/ubuntu/adoptium-installers)
  or see instructions below. The Debian instructions also work for Ubuntu if you'd rather avoid PPA's.
- Debian: there's an APT repo hosted at GitHub Pages, see below for instructions.

Use these packages at your own risk. These are NOT official packages.

## For Ubuntu:

```bash
# Make sure 'add-apt-repository' is available
[[ ! -f /usr/bin/add-apt-repository ]] && sudo apt-get -y install software-properties-common
sudo add-apt-repository --yes ppa:rpardini/adoptium-installers
sudo apt-get install adoptium-17-jdk-hotspot-installer # and you're done!
```

## For Debian:

```bash
# update and install support for https:// sources if not already installed
[[ ! -f /usr/lib/apt/methods/https ]] && sudo apt-get update && sudo apt-get install apt-transport-https

# install requirements for apt update and apt-key when missing
[[ ! -f /etc/ssl/certs/ca-certificates.crt ]] && sudo apt-get install ca-certificates
[[ ! -f /usr/bin/dirmngr ]] && sudo apt-get install dirmngr
[[ ! -f /usr/bin/gnupg ]] && sudo apt-get install gnupg

# add my key to trusted APT keys 
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A1EAC8B7
# add the package repo to sources 
echo 'deb https://rpardini.github.io/adoptium-deb-installer stable main' > /etc/apt/sources.list.d/rpardini-adoptium.list 
# update from sources
sudo apt-get update
# install a JDK, see above instructions for Ubuntu for other variants as well
sudo apt-get install adoptium-17-jdk-hotspot-installer
```

# For developers/builders

This repo produces **source** packages which are then uploaded to Launchpad, where they're built and hosted. The final
packages produced are essentially just downloader scripts, and try to handle proxy usage, SHA256 checksumming,
`update-alternatives` and `update-java-alternatives` as per `java-common` standards.

A huge amount of the actual installer scripting was stolen from
[Alin Andrei](https://launchpad.net/~webupd8team/+archive/ubuntu/java)'s `oracle-java8-installer`
and it shows -- all the update-alternatives, manpages, etc stuff is clearly in need of work. The proxy handling also
needs to be confirmed; a few of his provisions like using a custom
`wgetrc` was kept, but a lot of cosmetic stuff like icons were removed.

Due to the way Launchpad works, a big part of this is calculating a single set/version from many possible JDK builds for
different architectures. It seems common that `aarch64`
and/or `s390x` archs have different Eclipse Adoptium builds than other architectures, at least for Java 8 and Java 11.

For this reason (and also cause I'm a bit of a codegen freak) I implemented a Node.js script that
consumes [Eclipse Adoptium's releases API](https://api.adoptium.net/) and process sets of templates to produce final
source packages.

Also due to Launchpad's requirements, I build a lot of (otherwise identical) packages for different
distributions/series (trusty, xenial, bionic, etc).

# Credits

* Of course, [Eclipse Adoptium](https://adoptium.net/) for all of actual amazing work, and for the API.
* [Alin Andrei/webupd8](https://launchpad.net/~webupd8team/+archive/ubuntu/java) for the
  original `oracle-jdk8-installer` from which I started this work
* Launchpad for actually building on many architectures and hosting the whole thing for Ubuntu
* GitHub for repo, Github Actions, and hosting the Debian repo with GitHub Pages. Please don't ban me.
