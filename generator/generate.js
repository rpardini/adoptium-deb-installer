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


const architectures = new Set(['x64', 'aarch64', 'ppc64le', 's390x', 'arm']);
// @TODO: is 'arm' really 'armel'?
const archMapJdkToDebian = {'x64': 'amd64', 'aarch64': 'arm64', 'ppc64le': 'ppc64el', 's390x': 's390x', 'arm': 'armel'}; //subtle differences
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
    let allPromises = [];
    allPromises.push(generateForGivenKitAndJVM("jdk", "hotspot"));
    allPromises.push(generateForGivenKitAndJVM("jdk", "openj9"));
    allPromises.push(generateForGivenKitAndJVM("jre", "hotspot"));
    allPromises.push(generateForGivenKitAndJVM("jre", "openj9"));
    await Promise.all(allPromises);
}

async function generateForGivenKitAndJVM (jdkOrJre, hotspotOrOpenJ9) {
    console.log(`Generating for ${jdkOrJre}+${hotspotOrOpenJ9}...`);

    const basePath = path.dirname(__dirname);
    const templateFilesPerJava = await walk(`${basePath}/templates/per-java/`);
    const templateFilesPerArch = await walk(`${basePath}/templates/per-arch/`);
    const generatedDirBase = `${basePath}/generated`;

    const jdkBuildsPerArch = await getJDKInfosFromAdoptOpenJDKAPI(jdkOrJre, hotspotOrOpenJ9);

    // who DOESN'T love 4 nested for-loops?
    for (const linux of linuxesAndDistros) {
        for (const distroLinux of linux.distros) {
            for (const javaX of jdkBuildsPerArch.values()) {
                // the per-Java templates...
                let destPath = `${generatedDirBase}/${linux.name}/${javaX.jdkJreVersionJvmType}/${distroLinux}/debian`;
                let fnView = {javaX: `${javaX.jdkJreVersionJvmType}`};
                let javaXview_extra = {
                    distribution: `${distroLinux}`,
                    version: `${javaX.baseJoinedVersion}~${distroLinux}`,
                    virtualPackageName: `adoptopenjdk-${javaX.jdkVersion}-installer`,
                    commentForVirtualPackage: javaX.isDefaultForVirtualPackage ? "" : "#",
                    sourcePackageName: `adoptopenjdk-${javaX.jdkJreVersionJvmType}-installer`,
                    setDefaultPackageName: `adoptopenjdk-${javaX.jdkJreVersionJvmType}-set-default`,
                    buildDateChangelog: buildDateChangelog,
                    buildDateYear: buildDateYear,
                    signerName: signerName,
                    signerEmail: signerEmail
                };
                let javaXview = Object.assign(javaXview_extra, javaX); // yes, all of it.

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


async function getJDKInfosFromAdoptOpenJDKAPI (jdkOrJre, hotspotOrOpenJ9) {
    let javaBuildArchsPerVersion = new Map();
    for (let wantedJavaVersion of wantedJavaVersions) {
        try {
            let apiData = await processAPIData(wantedJavaVersion, architectures, jdkOrJre, hotspotOrOpenJ9);
            javaBuildArchsPerVersion.set(wantedJavaVersion, apiData);
        } catch (e) {
            console.error(`Error getting release data for ${wantedJavaVersion} ${jdkOrJre} ${hotspotOrOpenJ9}: ${e.message}`);
        }
    }
    return javaBuildArchsPerVersion;
}

async function processAPIData (jdkVersion, wantedArchs, jdkOrJre, hotspotOrOpenJ9) {

    let jsonStringAPIResponse;
    let apiURL = `https://api.adoptopenjdk.net/v2/latestAssets/releases/openjdk${jdkVersion}?os=linux&heap_size=normal&openjdk_impl=${hotspotOrOpenJ9}&type=${jdkOrJre}`;

    try {
        let httpResponse = await goodGuy(apiURL);
        jsonStringAPIResponse = httpResponse.body;
    } catch (e) {
        throw new Error(`${e.message} from URL ${apiURL}`)
    }

    let jsonContents = JSON.parse(jsonStringAPIResponse);

    let archData = new Map(); // builds per-architecture
    let slugs = new Map();
    let allDebArches = [];
    let debChangeLogArches = [];

    let jdkJreVersionJvmType = `${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`;

    let commonProps = {
        jdkVersion: jdkVersion,
        destDir: `adoptopenjdk-${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`,
        jdkJre: jdkOrJre,
        JDKorJREupper: jdkOrJre.toUpperCase(),
        jvmType: hotspotOrOpenJ9,
        jvmTypeDesc: (hotspotOrOpenJ9 === "openj9" ? "OpenJ9" : "Hotspot"),
        jdkJreVersionJvmType: jdkJreVersionJvmType,
    };

    commonProps.fullHumanTitle = `AdoptOpenJDK ${commonProps.JDKorJREupper} ${commonProps.jdkVersion} with ${commonProps.jvmTypeDesc}`;
    commonProps.isDefaultForVirtualPackage = (jdkOrJre === "jdk" && hotspotOrOpenJ9 === "hotspot");

    for (let oneRelease of jsonContents) {
        if (!wantedArchs.has(oneRelease.architecture)) {
            console.warn(`Unhandled architecture: ${oneRelease.architecture} for ${jdkJreVersionJvmType} `);
            continue;
        }
        let debArch = archMapJdkToDebian[oneRelease.architecture];

        // Hack, some builds have the openj9 version in them, some don't; normalize so none do
        let buildInfo = Object.assign(
            {
                arch: oneRelease.architecture,
                jdkArch: oneRelease.architecture,
                debArch: debArch,
                dirInsideTarGz: oneRelease.release_name,
                dirInsideTarGzShort: oneRelease.release_name.split(/_openj9/)[0],
                dirInsideTarGzWithJdkJre: `${oneRelease.release_name}-${jdkOrJre}`,
                slug: oneRelease.release_name,
                filename: oneRelease.binary_name,
                downloadUrl: oneRelease.binary_link,
                sha256sum: await getShaSum(oneRelease.checksum_link)
            },
            commonProps);
        archData.set(buildInfo.arch, buildInfo);

        let slugKey = oneRelease.release_name.split(/_openj9/)[0]
            .replace("-", "")
            .replace("jdk", "")
            .replace("jre", "")
            .replace("+", "b");

        if (!slugs.has(slugKey)) slugs.set(slugKey, []);
        slugs.get(slugKey).push(buildInfo.jdkArch);

        allDebArches.push(debArch);
        debChangeLogArches.push(`  * Exact version for architecture ${debArch}: ${oneRelease.release_name}`);
    }

    let calcVersion = calculateJoinedVersionForAllArches(slugs);
    let finalVersion = calcVersion.finalVersion;
    let commonArches = calcVersion.commonArches;
    console.log(`Composed version for ${jdkJreVersionJvmType} is ${finalVersion} - common arches are ${commonArches}`);

    return Object.assign(
        {
            arches: archData,
            baseJoinedVersion: finalVersion,
            allDebArches: allDebArches.join(' '),
            debChangeLogArches: debChangeLogArches.join("\n")
        },
        commonProps);
}

function calculateJoinedVersionForAllArches (slugs) {
    let slugArr = [];
    for (let oneSlugKey of slugs.keys()) {
        let arches = slugs.get(oneSlugKey);
        slugArr.push({slug: oneSlugKey, count: arches.length, archList: arches.sort().join("+")});
    }
    slugArr.sort((a, b) => b.count - a.count);

    let versionsByArch = [];
    let commonArches = null;
    let counter = 0;
    for (let oneArchesPlusSlug of slugArr) {
        let archList = oneArchesPlusSlug.archList + "~";
        if (counter === 0) {
            commonArches = oneArchesPlusSlug.archList;
            archList = "";
        } // we wont list the most common combo
        versionsByArch.push(archList + oneArchesPlusSlug.slug);
        counter++;
    }

    return {finalVersion: `${buildDateTimestamp}~${versionsByArch.join("+")}`, commonArches: commonArches};
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
        //console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir}) [exec: ${templateFile.executable}]`);

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