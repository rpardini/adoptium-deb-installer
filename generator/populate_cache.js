'use strict';

// I use 'good-guy-http', lol, this does quick and easy disk caching of the URLs
// so that I don't hammer adoptopenjdk during development
// the interactions with docker-layer-cache are a bit confusing though
let goodGuyDiskCache = require("good-guy-disk-cache");
const goodGuy = require('good-guy-http')({
    cache: new goodGuyDiskCache("adoptopenjdk-deb-generator"),
    forceCaching: {
        cached: true,
        timeToLive: 60 * 60 * 1000, // in milliseconds
        mustRevalidate: false
    },
});

const wantedJavaVersions = new Set([8, 9, 10, 11, 12]);

let mkdirs = [];
let wgets = [];

async function main () {
    await cacheForGivenKitAndJVM("jdk", "hotspot");
    await cacheForGivenKitAndJVM("jdk", "openj9");
    await cacheForGivenKitAndJVM("jre", "hotspot");
    await cacheForGivenKitAndJVM("jre", "openj9");
    console.log("RUN mkdir -p " + mkdirs.join(" "));
    console.log(`RUN (${wgets.join(";")}) | parallel -j ${wgets.length} --progress --eta --line-buffer`);
}

async function cacheForGivenKitAndJVM (jdkOrJre, hotspotOrOpenJ9) {
    for (let jdkVersion of wantedJavaVersions) {
        let destDir = `adoptopenjdk-${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`;
        try {
            let apiUrl = `https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk${jdkVersion}?os=linux&heap_size=normal&openjdk_impl=${hotspotOrOpenJ9}&type=${jdkOrJre}`;
            console.log(`# API: ${apiUrl}`);
            let httpResponse = await goodGuy(apiUrl);
            let jsonContents = JSON.parse(httpResponse.body);

            for (let oneRelease of jsonContents) {
                try {
                    await goodGuy(oneRelease.checksum_link); // just to populate on-disk-cache
                    if (oneRelease.architecture === 'x64') { // @TODO: actually should be arch we're running on.
                        let filename = oneRelease.binary_name;
                        let downloadUrl = oneRelease.binary_link;

                        let mkdir = `/var/cache/${destDir}-installer`;
                        let wget = `echo wget --continue --local-encoding=UTF-8 -O /var/cache/${destDir}-installer/${filename} "${downloadUrl}"`;
                        mkdirs.push(mkdir);
                        wgets.push(wget);
                    }
                } catch (e) {
                    console.error(`# SHA256SUM: ${destDir}: Unavailable (${e.message}): ${e.request.url}`);
                }
            }
        } catch (e) {
            console.error(`# ${destDir}: Unavailable (${e.message}): ${e.request.url}`);
        }
    }
}

main().then(value => {
    console.log("done.");
    process.exit(0);
}).catch(reason => {
    console.error(reason);
    process.exit(1);
});