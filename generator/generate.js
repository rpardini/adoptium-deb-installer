'use strict';

// generator version; this is used to add to the generated package's version timestamp (in minutes)
// avoid bumping this too high.
const generatorVersionIncrement = 12;

// we use promisified filesystem functions from node.js
const regular_fs = require('fs');
const fs = regular_fs.promises;
const path = require('path');
const glob = require('glob-all');

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
    {
        name: 'ubuntu',
        distros: new Set(['trusty', 'xenial', 'bionic', 'cosmic', 'disco']),
        standardsVersion: "3.9.7",
        useDistroInVersion: true,
        singleBinaryForAllArches: false,
        postArchesHook: null
    },
    {
        name: 'debian',
        distros: new Set(['stable']),
        standardsVersion: "3.9.6",
        useDistroInVersion: false,
        singleBinaryForAllArches: true,
        postArchesHook: joinDebianPostinstForAllArches
    }
]);

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
                    provides: createProducesLine(javaX),
                    standardsVersion: linux.standardsVersion,
                    allDebArches: linux.singleBinaryForAllArches ? "all" : javaX.allDebArches,
                    distribution: `${distroLinux}`,
                    version: linux.useDistroInVersion ? `${javaX.baseJoinedVersion}~${distroLinux}` : javaX.baseJoinedVersion,
                    virtualPackageName: `adoptopenjdk-${javaX.jdkVersion}-installer`,
                    commentForVirtualPackage: javaX.isDefaultForVirtualPackage ? "" : "#",
                    sourcePackageName: `adoptopenjdk-${javaX.jdkJreVersionJvmType}-installer`,
                    setDefaultPackageName: `adoptopenjdk-${javaX.jdkJreVersionJvmType}-set-default`,
                    signerName: signerName,
                    signerEmail: signerEmail
                };
                let javaXview = Object.assign(javaX, javaXview_extra);

                await processTemplates(templateFilesPerJava, destPath, fnView, javaXview, true);

                let archProcessedTemplates = [];

                for (const arch of javaX.arches.values()) {
                    let archFnView = Object.assign({archX: arch.debArch}, fnView);
                    let archXview = Object.assign(arch, javaXview);
                    archProcessedTemplates[arch.debArch] = await processTemplates(templateFilesPerArch, destPath, archFnView, archXview, !linux.singleBinaryForAllArches);
                }

                if (linux.postArchesHook) await linux.postArchesHook(archProcessedTemplates, destPath, javaX);

                // Here we should make sure destPath and everything inside it have the version's timestamp.
                await recursiveChangeFileDate(destPath, javaX.buildDateTS.toDate());

            }
        }
    }
}

async function joinDebianPostinstForAllArches (archProcessedTemplates, destPath, javaX) {
    let postInstContents = [
        "#! /bin/bash",
        `# joined script for multi-arch postinst for ${javaX.jdkJreVersionJvmType}`,
        "DPKG_ARCH=$(dpkg --print-architecture)",
        "DID_FIND_ARCH=false"
    ];
    for (const debArch of Object.keys(archProcessedTemplates)) {
        postInstContents.push(`if [[ "$DPKG_ARCH" == "${debArch}" ]]; then`);
        postInstContents.push(`echo "Installing for arch '${debArch}'..."`);
        postInstContents.push((archProcessedTemplates[debArch]['adoptopenjdk-javaX-installer.postinst.archX']));
        postInstContents.push(`DID_FIND_ARCH=true`);
        postInstContents.push(`fi`);
    }
    postInstContents.push('if [[ "$DID_FIND_ARCH" == "false" ]]; then');
    postInstContents.push('  echo "Unsupported architecture ${DPKG_ARCH}"');
    postInstContents.push(`  exit 2`);
    postInstContents.push(`fi`);

    await writeTemplateFile(destPath, {
        dirs: "",
        executable: true
    }, `adoptopenjdk-${javaX.jdkJreVersionJvmType}-installer.postinst`, postInstContents.join("\n"));
}

function createProducesLine (javaX) {
    let prodArr = ['java-runtime', 'default-jre', 'default-jre-headless'];
    prodArr = prodArr.concat(createJavaProducesPrefixForVersion(javaX.jdkVersion, '-runtime'));
    prodArr = prodArr.concat(createJavaProducesPrefixForVersion(javaX.jdkVersion, '-runtime-headless'));
    // jre: java-runtime, default-jre, default-jre-headless, javaX-runtime, javaX-runtime-headless

    if (javaX.jdkJre === 'jdk') {
        // for jdk: java-compiler, default-jdk, default-jdk-headless, javaX-sdk, javaX-sdk-headless
        prodArr = prodArr.concat(['java-compiler', 'default-jdk', 'default-jdk-headless']);
        prodArr = prodArr.concat(createJavaProducesPrefixForVersion(javaX.jdkVersion, '-sdk'));
        prodArr = prodArr.concat(createJavaProducesPrefixForVersion(javaX.jdkVersion, '-sdk-headless'));
    }
    return prodArr.join(", ");
}

function createJavaProducesPrefixForVersion (javaVersion, suffix) {
    let javas = [`java${suffix}`, `java2${suffix}`];
    for (let i = 5; i < javaVersion + 1; i++) {
        javas.push(`java${i}${suffix}`)
    }
    return javas;
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
    let highestBuildTS = 0;

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

        let buildTS = moment(oneRelease.timestamp, moment.ISO_8601);
        let updatedTS = moment(oneRelease.updated_at, moment.ISO_8601);
        let highTS = (buildTS > updatedTS) ? buildTS : updatedTS;
        highestBuildTS = (highTS > highestBuildTS) ? highTS : highestBuildTS;

        let buildInfo = Object.assign(
            {
                arch: oneRelease.architecture,
                jdkArch: oneRelease.architecture,
                debArch: debArch,
                dirInsideTarGz: oneRelease.release_name, // release name from AOJ is most of the time correct
                dirInsideTarGzShort: oneRelease.release_name.split(/_openj9/)[0], // release name without openj9 part...
                dirInsideTarGzShortWithJdkJre: oneRelease.release_name.split(/_openj9/)[0]+`-${jdkOrJre}`, // release name without openj9 part, with -jre suffix...
                dirInsideTarGzWithJdkJre: `${oneRelease.release_name}-${jdkOrJre}`, // release name with '-jre' sometimes.
                slug: oneRelease.release_name,
                filename: oneRelease.binary_name,
                downloadUrl: oneRelease.binary_link,
                sha256sum: await getShaSum(oneRelease.checksum_link)
            },
            commonProps);

        archData.set(buildInfo.arch, buildInfo);

        // Hack, some builds have the openj9 version in them, some don't; normalize so none do
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

    // Hack: to allow the generator to produce packages with higher version number
    //       than the highest timestamp, eg, to fix bugs on the installer itself
    highestBuildTS.add(generatorVersionIncrement, 'minutes');

    let calcVersion = calculateJoinedVersionForAllArches(slugs, highestBuildTS);
    let finalVersion = calcVersion.finalVersion;
    let commonArches = calcVersion.commonArches;
    console.log(`Composed version for ${jdkJreVersionJvmType} is ${finalVersion} - common arches are ${commonArches}`);

    return Object.assign(
        {
            arches: archData,
            baseJoinedVersion: finalVersion,
            buildDateYear: highestBuildTS.format('YYYY'),
            buildDateChangelog: highestBuildTS.format('ddd, DD MMM YYYY HH:mm:ss ZZ'),
            buildDateTS: highestBuildTS,
            allDebArches: allDebArches.join(' '),
            debChangeLogArches: debChangeLogArches.join("\n")
        },
        commonProps);
}

function calculateJoinedVersionForAllArches (slugs, highestBuildTS) {
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

    return {
        finalVersion: `${highestBuildTS.format('YYYYMMDDHHmm')}~${versionsByArch.join("+")}`,
        commonArches: commonArches
    };
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

async function writeTemplateFile (destPathBase, templateFile, destFileTemplated, modifiedContents) {
    let destFileParentDir = destPathBase + "/" + templateFile.dirs;
    let fullDestPath = destPathBase + "/" + (templateFile.dirs ? templateFile.dirs + "/" : "") + destFileTemplated;
    //console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir}) [exec: ${templateFile.executable}]`);

    await fs.mkdir(destFileParentDir, {recursive: true});
    await fs.writeFile(fullDestPath, modifiedContents, {
        encoding: 'utf8',
        mode: templateFile.executable ? 0o777 : 0o666
    });
}

async function recursiveChangeFileDate (destPath, newDate) {
    let matchedFiles = await getFiles(destPath);
    for (let file of matchedFiles) {
        regular_fs.utimesSync(file, newDate, newDate);
    }
}

function getFiles (matcherPath) {
    return new Promise((resolve, reject) => {
        glob([`${matcherPath}/**`], {realpath: true}, (err, files) => {
            if (err) reject(err);
            else {
                resolve(files)
            }
        })
    })
}


async function processTemplates (templateFiles, destPathBase, fnView, view, writeFiles) {
    let ret = {};
    for (let templateFile of templateFiles) {

        let destFileTemplated = templateFile.file;
        for (let fnKey in fnView) {
            destFileTemplated = destFileTemplated.replace(fnKey, fnView[fnKey]);
        }

        let originalContents = await fs.readFile(templateFile.fullpath, 'utf8');
        let modifiedContents = mustache.render(originalContents, view);

        if (writeFiles) {
            await writeTemplateFile(destPathBase, templateFile, destFileTemplated, modifiedContents);
        }
        ret[templateFile.file] = modifiedContents;
    }
    return ret;
}

main().then(value => {
    console.log("done.");
    process.exit(0);
}).catch(reason => {
    console.error(reason);
    process.exit(1);
});
