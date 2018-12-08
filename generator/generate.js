'use strict';


// we use promisified filesystem functions from node.js
const regular_fs = require('fs');
const fs = regular_fs.promises;
const path = require('path');

// moment for date formatting
const moment = require('moment');

// mustache to resolve the templates.
const mustache = require('mustache');

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


const architectures = new Set(['x64', 'aarch64', 'ppc64le', 's390x']);
const archMapJdkToDebian = {'x64': 'amd64', 'aarch64': 'arm64', 'ppc64le': 'ppc64el', 's390x': 's390x'}; //subtle differences
const wantedJavaVersions = new Set([8, 9, 10, 11]);
const linuxesAndDistros = new Set([
    {name: 'ubuntu', distros: new Set(['trusty', 'xenial', 'bionic'])},
    {name: 'debian', distros: new Set(['wheezy', 'jessie'])}
]);

// the date-based stuff. both the version and the changelog use it.
const buildDate = moment();
const buildDateTimestamp = buildDate.format('YYYYMMDDHHmm');
const buildDateYear = buildDate.format('YYYY');
const buildDateChangelog = buildDate.format('ddd, DD MMM YYYY HH:mm:ss ZZ');

// the person building and signing the packages.
const signerName = "Ricardo Pardini (Pardini Yubi 2017)";
const signerEmail = "ricardo@pardini.net";

async function main () {
    const basePath = path.dirname(__dirname) ;
    const templateFilesPerJava = await walk(`${basePath}/templates/per-java/`);
    const templateFilesPerArch = await walk(`${basePath}/templates/per-arch/`);
    const generatedDirBase = `${basePath}/generated`;

    const jdkBuildsPerArch = await getJDKInfosFromAdoptOpenJDKAPI();

    // who DOESN'T love 4 nested for-loops?
    for (const linux of linuxesAndDistros) {
        for (const distroLinux of linux.distros) {
            for (const javaX of jdkBuildsPerArch.values()) {
                // the per-Java templates...
                let destPath = `${generatedDirBase}/${linux.name}/java-${javaX.jdkVersion}/${distroLinux}/debian`;
                let fnView = {javaX: `java${javaX.jdkVersion}`};
                let javaXview = {
                    jdkVersion: javaX.jdkVersion,
                    allDebArches: javaX.allDebArches,
                    distribution: `${distroLinux}`,
                    version: `${javaX.baseJoinedVersion}~${distroLinux}`,
                    sourcePackageName: `adoptopenjdk-java${javaX.jdkVersion}-installer`,
                    setDefaultPackageName: `adoptopenjdk-java${javaX.jdkVersion}-set-default`,
                    debChangeLogArches: javaX.debChangeLogArches,
                    buildDateChangelog: buildDateChangelog,
                    buildDateYear: buildDateYear,
                    signerName: signerName,
                    signerEmail: signerEmail
                };

                await processTemplates(templateFilesPerJava, destPath, fnView, javaXview);

                for (const arch of javaX.arches.values()) {
                    let archFnView = Object.assign({archX: arch.debArch}, fnView);
                    let archXview = Object.assign(arch, javaXview); // yes, all of it.

                    await processTemplates(templateFilesPerArch, destPath, archFnView, archXview);
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
    let slugs = new Map();
    let allDebArches = [];
    let debChangeLogArches = [];

    for (let oneRelease of jsonContents) {
        if (!wantedArchs.has(oneRelease.architecture)) continue;
        let debArch = archMapJdkToDebian[oneRelease.architecture];
        let buildInfo = {
            jdkVersion: jdkVersion,
            arch: oneRelease.architecture,
            jdkArch: oneRelease.architecture,
            debArch: debArch,
            slug: oneRelease.release_name,
            cleanedSlug: oneRelease.release_name.replace("-", "").replace("jdk", "").replace("+", "b"), // cant have dashes in there...
            filename: oneRelease.binary_name,
            downloadUrl: oneRelease.binary_link,
            sha256sum: await getShaSum(oneRelease.checksum_link)
        };
        archData.set(buildInfo.arch, buildInfo);

        let slugKey = buildInfo.cleanedSlug;
        if (!slugs.has(slugKey)) slugs.set(slugKey, []);
        slugs.get(slugKey).push(buildInfo.jdkArch);

        allDebArches.push(debArch);
        debChangeLogArches.push(`  * For ${debArch} JDK version is ${oneRelease.release_name}`);
    }

    let finalVersion = calculateJoinedVersionForAllArches(slugs);
    console.log(`Composed version for JDK ${jdkVersion} is ${finalVersion}`);

    return {
        arches: archData,
        baseJoinedVersion: finalVersion,
        jdkVersion: jdkVersion,
        allDebArches: allDebArches.join(' '),
        debChangeLogArches: debChangeLogArches.join("\n")
    };
}

function calculateJoinedVersionForAllArches (slugs) {
    let slugArr = [];
    for (let oneSlugKey of slugs.keys()) {
        let arches = slugs.get(oneSlugKey);
        slugArr.push({slug: oneSlugKey, count: arches.length, archList: arches.sort().join(".")});
    }
    slugArr.sort((a, b) => b.count - a.count);

    let versionsByArch = [];
    let counter = 0;
    for (let oneArchesPlusSlug of slugArr) {
        let archList = oneArchesPlusSlug.archList + "~";
        if (counter === 0) archList = ""; // we wont list the most common combo
        versionsByArch.push(archList + oneArchesPlusSlug.slug);
        counter++;
    }

    return `${buildDateTimestamp}~${versionsByArch.join("+")}`;
}

async function getShaSum (url) {
    let httpResponse = await goodGuy(url);
    return httpResponse.body.trim().split(" ")[0];
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

async function processTemplates (templateFiles, destPathBase, fnView, view) {
    for (let templateFile of templateFiles) {

        let destFileTemplated = templateFile.file;
        for (let fnKey in fnView) {
            destFileTemplated = destFileTemplated.replace(fnKey, fnView[fnKey]);
        }

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