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

const wantedJavaVersions = new Set([8, 9, 10, 11]);

async function main () {
    await cacheForGivenKitAndJVM("jdk", "hotspot");
    await cacheForGivenKitAndJVM("jdk", "openj9");
    await cacheForGivenKitAndJVM("jre", "hotspot");
    await cacheForGivenKitAndJVM("jre", "openj9");
}

async function cacheForGivenKitAndJVM (jdkOrJre, hotspotOrOpenJ9) {
    for (let jdkVersion of wantedJavaVersions) {
        let destDir = `adoptopenjdk-${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`;
        try {
            let httpResponse = await goodGuy(`https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk${jdkVersion}?os=linux&heap_size=normal&openjdk_impl=${hotspotOrOpenJ9}&type=${jdkOrJre}`);
            let jsonContents = JSON.parse(httpResponse.body);

            for (let oneRelease of jsonContents) {
                await goodGuy(oneRelease.checksum_link); // just to populate on-disk-cache
                if (oneRelease.architecture === 'x64') { // @TODO: actually should be arch we're running on.
                    let filename = oneRelease.binary_name;
                    let downloadUrl = oneRelease.binary_link;
                    console.log(`RUN mkdir -p /var/cache/${destDir}-installer`);
                    console.log(`RUN wget --continue -O /var/cache/${destDir}-installer/${filename} "${downloadUrl}"`);
                }
            }
        } catch (e) {
            console.error(`# Unavailable (${e.message}): ${destDir}`);
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