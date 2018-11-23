'use strict';

// we use promisified filesystem functions from node.js
const regular_fs = require('fs');
const fs = regular_fs.promises;
const path = require('path');

// mustache to resolve the templates.
const mustache = require('mustache');

// I use 'good-guy-http', lol, this does quick and easy disk caching of the URLs
// so that I don't hammer adoptopenjdk during development
// the interactions with docker-layer-cache are a bit confusing though
const DiskCache = require("good-guy-disk-cache");
const GoodGuy = require('good-guy-http');
const diskCache = new DiskCache("adoptopenjdk-deb-generator");
const goodGuy = GoodGuy({
    cache: diskCache,
    forceCaching: {
        cached: true,
        timeToLive: 60 * 60 * 1000, // in milliseconds
        mustRevalidate: false
    },
});


const architectures = new Set(['x64', 'aarch64', 'ppc64le', 's390x']);
const archMapJdkToDebian = {'x64': 'amd64', 'aarch64': 'arm64', 'ppc64le': 'ppc64el', 's390x': 's390x'}; //subtle differences
//const wantedJavaVersions = new Set([8, /*9, 10,*/ 11]);
const wantedJavaVersions = new Set([8]);
const linuxesAndDistros = new Set([
    {name: 'ubuntu', distros: new Set([/*'trusty',*/ 'xenial', 'bionic'])},
    {name: 'debian', distros: new Set(['wheezy', 'jessie'])}
]);

async function main () {
    const templateFiles = await walk("../templates");
    const generatedDirBase = "../generated";

    const jdkBuildsPerArch = await getJDKInfosFromAdoptOpenJDKAPI();

    // who DOESN'T love 4 nested for-loops?
    for (const jdkVersion of jdkBuildsPerArch.values()) {
        for (const archJdkVersion of jdkVersion.values()) {
            for (const linux of linuxesAndDistros) {
                for (const distroLinux of linux.distros) {
                    console.log(linux, distroLinux, archJdkVersion);

                    await processTemplates(
                        templateFiles,
                        `java${archJdkVersion.jdkVersion}`,
                        `${generatedDirBase}/${linux.name}/java-${archJdkVersion.jdkVersion}/${archJdkVersion.arch}/${distroLinux}/debian`, {
                            jdkVersion: archJdkVersion.jdkVersion,
                            debArch: archJdkVersion.debArch,
                            jdkArch: archJdkVersion.jdkArch,
                            slug: archJdkVersion.slug,
                            distribution: `${distroLinux}`,
                            version: `0.0.4~${distroLinux}~${archJdkVersion.jdkArch}~${archJdkVersion.cleanedSlug}`,
                            sourcePackageName: `adoptopenjdk-java${archJdkVersion.jdkVersion}-installer`,
                            setDefaultPackageName: `adoptopenjdk-java${archJdkVersion.jdkVersion}-set-default`,
                            unlimitedPackageName: `adoptopenjdk-java${archJdkVersion.jdkVersion}-unlimited-jce-policy`,

                        }
                    );

                }
            }
        }
    }
}


async function getJDKInfosFromAdoptOpenJDKAPI () {
    let javaBuildArchsPerVersion = new Map();
    for (let wantedJavaVersion of wantedJavaVersions) {
        javaBuildArchsPerVersion.set(wantedJavaVersion, await processAPIData(wantedJavaVersion, architectures));
    }
    return javaBuildArchsPerVersion;
}

async function processAPIData (jdkVersion, wantedArchs) {

    let httpResponse = await goodGuy(`https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk${jdkVersion}?os=linux&heap_size=normal&openjdk_impl=hotspot&type=jdk`);
    let jsonContents = JSON.parse(httpResponse.body);

    let archData = new Map(); // builds per-architecture
    for (let oneRelease of jsonContents) {
        if (wantedArchs.has(oneRelease.architecture)) {
            let buildInfo = {
                jdkVersion: jdkVersion,
                arch: oneRelease.architecture,
                jdkArch: oneRelease.architecture,
                debArch: archMapJdkToDebian[oneRelease.architecture],
                slug: oneRelease.release_name,
                cleanedSlug: oneRelease.release_name.replace("-", "~"), // cant have dashes in there...
                filename: oneRelease.binary_name,
                downloadUrl: oneRelease.binary_link,
                sha256sum: await getShaSum(oneRelease.checksum_link)
            };
            archData.set(buildInfo.arch, buildInfo);
        }
    }
    return archData;
}

async function getShaSum (url) {
    let httpResponse = await goodGuy(url);
    return httpResponse.body.trim().split(" ")[0].toUpperCase();
}

async function walk (dir, filelist = [], dirbase = "") {
    const files = await fs.readdir(dir);
    for (let file of files) {
        const filepath = path.join(dir, file);
        /** @type {!fs.Stats} yeah... */
        const stat = await fs.stat(filepath);
        let isExecutable = false;
        try {
            await fs.access(filepath, regular_fs.constants.X_OK); // text for x-bit in file mode
            isExecutable = true;
        } catch (e) {
            // ignored.
        }
        if (stat.isDirectory()) {
            filelist = await walk(filepath, filelist, (dirbase ? dirbase + "/" : "") + file);
        } else {
            filelist.push({file: file, dirs: dirbase, fullpath: filepath, executable: isExecutable});
        }
    }
    return filelist;
}

async function processTemplates (templateFiles, javaVersionPkg, destPathBase, view) {
    for (let templateFile of templateFiles) {
        let destFileTemplated = templateFile.file.replace("javaX", javaVersionPkg);

        let destFileParentDir = destPathBase + "/" + templateFile.dirs;
        let fullDestPath = destPathBase + "/" + (templateFile.dirs ? templateFile.dirs + "/" : "") + destFileTemplated;
        console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir}) [exec: ${templateFile.executable}]`);

        let originalContents = await fs.readFile(templateFile.fullpath, 'utf8');
        let modifiedContents = mustache.render(originalContents, view);

        // ready to write to dest? lets go...
        await fs.mkdir(destFileParentDir, {recursive: true});
        await fs.writeFile(fullDestPath, modifiedContents, {
            encoding: 'utf8',
            mode: templateFile.executable ? 0o777 : 0o666
        });
    }
}

main().then(value => {
    console.log("done.");
    process.exit(0);
}).catch(reason => {
    console.error(reason);
    process.exit(1);
});