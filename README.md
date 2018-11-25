# Debian/Ubuntu installer packages for AdoptOpenJDK

# TL;DR

This repo produces Ubuntu (and Debian) packages which download and install AdoptOpenJDK from 
their official releases, using the AdoptOpenJDK API.

- for Ubuntu: check out [ppa:rpardini/adoptopenjdk](https://launchpad.net/~rpardini/+archive/ubuntu/adoptopenjdk) 
  or see instructions below
- for Debian: _I'm looking for a package hoster (a la Launchpad) for Debian, let me know._

# Info for final users

This is far from production ready!
Use these packages at your own risk.

## For Ubuntu:

```bash
# only use this on test/throwaway machines as of December/2018, until we get more testing done
sudo add-apt-repository --yes ppa:rpardini/adoptopenjdk
sudo apt-get update
sudo apt-get install adoptopenjdk-java8-installer adoptopenjdk-java8-set-default 
# also avaiable in java9, java10, java11 flavors
```

## For Debian:

@TODO, I don't really use Debian anymore.

# For developers/builders

This repo produces **source** packages which are then uploaded to Launchpad, 
where they're built and hosted. The final packages produced are essentially
just downloader scripts, and try to handle proxy usage, SHA256 checksumming,
`update-alternatives` and `update-java-alternatives` as per `java-common` standards.

A huge amount of the actual installer scripting was stolen from [Alin Andrei](https://launchpad.net/~webupd8team/+archive/ubuntu/java)
's `oracle-java8-installer`
and it shows -- all the update-alternatives, manpages, etc stuff is clearly in need of work.
The proxy handling also needs to be confirmed; a few of his provisions like using a custom 
`wgetrc` was kept, but a lot of cosmetic stuff like icons were removed.

Due to the way Launchpad works, a big part of this is calculating a single set/version
from many possible JDK builds for different architectures. It seems common that `aarch64` 
and/or `s390x` archs have different AdoptOpenJDK builds than other architectures, at least
for Java 8 and Java 11. 

For this reason (and also cause I'm a bit of a codegen freak) I implemented a Node.js
script that consume [AdoptOpenJDK's releases API](https://api.adoptopenjdk.net/) and process sets 
of templates to produce final source packages.

Also due to Launchpad's requirements, I build a lot of (otherwise identical) packages for
different distributions/series (trusty, xenial, bionic, etc).

I use Docker extensively for the package building in this repo, but, unfortunately, 
there's no reliable way to GPG sign packages inside Docker, especially with my setup,
which involves a hardware token (Yubikey). To work around that I _exfiltrate_ the final
results back to the host machine (which in my case is a Mac) via Docker Volumes, 
GPG-sign them (via `osx/debsign_osx.sh` and a few brew utilities) and again use Docker
for `dput`ing them to Launchpad. All this back-and-forth is automated in `build_sign_osx.sh`.

## Build steps

These are automated in `build_sign_osx.sh`.

1. Build the multi-stage Dockerfile.
   1. _generator_ stage builds and runs the Node.js `generate.js` script. See below for details.
   2. _ubuntuBuilder_ stage gets the generated packages and builds them, both in source form
      and binary form (for amd64); it also installs the packages for basic sanity checking.
      This process is mostly handled by the `docker/build_packages_multi.sh`.
   3. _debianBuilder_ stage does mostly the same but using a Debian image. @TODO: Debian stuff
      is not really handled yet (commented-out) until I find a hoster for these packages.
   4. The final stage contains only the final built packages and sets up the hackish 
      `docker/sign_upload.sh` for the steps below.
2. Copy the resulting packages back to host machine via Docker volumes.
3. GPG-sign the packages on the host.
4. Copy the signed packages back to Docker and upload them via `dput` to Launchpad.

### The Node.js generator script

This turned out to be a bit of a beast. It's badly written. It's buggy. And it makes *a lot*
of assumptions. Here's some details:

- Is mostly written with `async/await` since I hate callbacks with a passion
- It uses/requires:
  - `fs.promises` for filesystem reading/writing
  - `moustache` for the templating
  - `good-guy-http` for talking to AOJ API and getting the SHA256 sums from Github, while using
    a disk cache to avoid overwhelming those with requests during development
  - `moment.js` for date handling (date timestamp and changelog timestamp)
- `calculateJoinedVersionForAllArches` is some of the worst code I've ever written
  - what it does is produce a single string like `8u192b12+aarch64~8u191b12` given
    * `arm64` version at `jdk8u191-b12`
    * `ppc64el` version at `jdk8u192-b12`
    * `amd64` version at `jdk8u192-b12`
    * `s390x` version at `jdk8u192-b12`
  - of course it's buggy and untested. what happens if every arch has it's own version at a certain point?
- there is a lot of `consts` there that should be parametrized somehow 
  - builder name/email, which is essential for GPG-signing
  - JDK-arch-to-Debian-arch conversion. Did you know AOJ calls one `ppc64le` while Debian calls the same `ppc64el`?
  - Distributions/series like xenial, trusty are hardcoded too
- the templates it processes live in the `templates` directory
  - `per-java` templates are use for each JDK version (8,9,10,11)
  - `per-arch` template (only the install script actually) are per-JDK-version but also per-arch (`amd64` etc)

You can run the generator outside of Docker to see what it does or hack on it,
but you'll need specific Node.js version, npm install, and patience. Check out the Dockerfile
for details.


# Upcoming work

* Investigate actual upgrade path on production machines which currently use `oracle-jdk8-installer`
* Supporting both Hotspot and OpenJ9 builds would be awesome; but it would require splitting packages...
* Actually test on `ppc64el` and `s390x`; I only have access to `amd64` and `aarch64` at home
* Making sure all the update-alternatives stuff is actually working
* Make sure stuff is properly cleaned-up on package removal
* Check how these packages interact with other JDK packages (eg, OpenJDK from stock Ubuntu, etc)
* Find a way to host the Debian packages
* Maybe support more architectures (eg, `arm`, I bet the RaspberryPi folks would enjoy that)
  If I understand correctly, AdoptOpenJDK only has ARM32 builds for Java 10, but why not?
* Find a better versioning scheme to use in place of the timestamp I'm using now
* Investigate and _maybe_ support the "large heap" builds
* Investigate `/usr/lib/jvm/default-java` and its implications
* If in download mode, emit instructions for the final user on how to use pre-downloaded file mode.
* Figure out the actual copyright for this, it says GPL-3 but I'm not sure

# Credits

* Of course, [AdoptOpenJDK](https://adoptopenjdk.net/) for all of actual amazing work, and for the API.
* [Alin Andrei/webupd8](https://launchpad.net/~webupd8team/+archive/ubuntu/java) for the original `oracle-jdk8-installer` from which I started this work
* Jesper Birkestrøm for providing [debsign_osx.sh](https://gist.github.com/birkestroem/ad4866ae7b823820bf51)
* Launchpad for actually building on many architectures and hosting the whole thing
