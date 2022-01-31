'use strict';

// config
const architectures = new Set(['x64', 'aarch64', 'ppc64le', 's390x', 'arm']);
const archMapJdkToDebian = {'x64': 'amd64', 'aarch64': 'arm64', 'ppc64le': 'ppc64el', 's390x': 's390x', 'arm': 'armel'}; //subtle differences
const wantedJavaVersions = new Set([8, 11, 16, 17]); // official GA releases from adoptium
const linuxesAndDistros = new Set([
    {
        name: 'ubuntu',
        distros: new Set(['trusty', 'xenial', 'bionic', 'focal', 'jammy', 'impish']), // LTS ESM releases + last release + next, but not the ones frozen, like hir.sute or gro.ovy
        standardsVersion: "3.9.7",
        useDistroInVersion: true,
        singleBinaryForAllArches: false,
        postArchesHook: null
    },
    {
        name: 'debian',
        distros: new Set(['stable']), // Single distro for Debian
        standardsVersion: "3.9.6",
        useDistroInVersion: false,
        singleBinaryForAllArches: true,
        postArchesHook: joinDebianPostinstForAllArches
    }
]);

// the person building and signing the packages.
const signerName = process.env.PACKAGE_SIGNER_NAME || "Adoptium .deb Installer Key (Used for package signing)";
const signerEmail = process.env.PACKAGE_SIGNER_EMAIL || "adoptium.deb@pardini.net";

// generator version; this is used to add to the generated package's version timestamp (in minutes)
const generatorVersionIncrement = 2;

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
// so that I don't hammer adoptium API during development
let goodGuyDiskCache = require("good-guy-disk-cache");
const goodGuy = require('good-guy-http')({
    maxRetries: 5,
    timeout: 5000,
    cache: new goodGuyDiskCache("adoptium-deb-generator"),
    forceCaching: {
        cached: true,
        timeToLive: 60 * 60 * 1000, // in milliseconds
        mustRevalidate: false
    },
});


async function main() {
    let allPromises = [];
    allPromises.push(generateForGivenKitAndJVM("jdk", "hotspot"));
    allPromises.push(generateForGivenKitAndJVM("jre", "hotspot"));
    // adoptium does not carry openj9 anymore, that's a separate project now.
    //allPromises.push(generateForGivenKitAndJVM("jdk", "openj9"));
    //allPromises.push(generateForGivenKitAndJVM("jre", "openj9"));
    await Promise.all(allPromises);
}

async function generateForGivenKitAndJVM(jdkOrJre, hotspotOrOpenJ9) {
    console.log(`Generating for ${jdkOrJre}+${hotspotOrOpenJ9}...`);

    const basePath = path.dirname(__dirname);
    const templateFilesPerJava = await walk(`${basePath}/templates/per-java/`);
    const templateFilesPerArch = await walk(`${basePath}/templates/per-arch/`);
    const generatedDirBase = `${basePath}/generated`;

    const jdkBuildsPerArch = await getJDKInfosFromAdoptiumAPI(jdkOrJre, hotspotOrOpenJ9);

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
                    virtualPackageName: `adoptium-${javaX.jdkVersion}-installer`,
                    commentForVirtualPackage: javaX.isDefaultForVirtualPackage ? "" : "#",
                    sourcePackageName: `adoptium-${javaX.jdkJreVersionJvmType}-installer`,
                    setDefaultPackageName: `adoptium-${javaX.jdkJreVersionJvmType}-set-default`,
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

async function joinDebianPostinstForAllArches(archProcessedTemplates, destPath, javaX) {
    let postInstContents = [
        "#! /bin/bash",
        `# joined script for multi-arch postinst for ${javaX.jdkJreVersionJvmType}`,
        "DPKG_ARCH=$(dpkg --print-architecture)",
        "DID_FIND_ARCH=false"
    ];
    for (const debArch of Object.keys(archProcessedTemplates)) {
        postInstContents.push(`if [[ "$DPKG_ARCH" == "${debArch}" ]]; then`);
        postInstContents.push(`echo "Installing for arch '${debArch}'..."`);
        postInstContents.push((archProcessedTemplates[debArch]['adoptium-javaX-installer.postinst.archX']));
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
    }, `adoptium-${javaX.jdkJreVersionJvmType}-installer.postinst`, postInstContents.join("\n"));
}

function createProducesLine(javaX) {
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

function createJavaProducesPrefixForVersion(javaVersion, suffix) {
    let javas = [`java${suffix}`, `java2${suffix}`];
    for (let i = 5; i < javaVersion + 1; i++) {
        javas.push(`java${i}${suffix}`)
    }
    return javas;
}

async function getJDKInfosFromAdoptiumAPI(jdkOrJre, hotspotOrOpenJ9) {
    let javaBuildArchsPerVersion = new Map();

    for (let wantedJavaVersion of wantedJavaVersions) {
        // Hack, 16+ does not have JRE anymore, don't even try.
        if ((wantedJavaVersion >= 16) && (jdkOrJre === "jre")) continue;
        try {
            let apiData = await processAPIData(wantedJavaVersion, architectures, jdkOrJre, hotspotOrOpenJ9);
            javaBuildArchsPerVersion.set(wantedJavaVersion, apiData);
        } catch (e) {
            console.error(`Error getting release data for ${wantedJavaVersion} ${jdkOrJre} ${hotspotOrOpenJ9}: ${e.message}`);
        }
    }
    return javaBuildArchsPerVersion;
}

async function processAPIData(jdkVersion, wantedArchs, jdkOrJre, hotspotOrOpenJ9) {
    let jsonStringAPIResponse;

    let apiURL = `https://api.adoptium.net/v3/assets/feature_releases/${jdkVersion}/ga?release=latest&jvm_impl=hotspot&vendor=adoptium&image_type=${jdkOrJre}&os=linux`;
    try {
        let httpResponse = await goodGuy(apiURL);
        jsonStringAPIResponse = httpResponse.body;
    } catch (e) {
        throw new Error(`${e.message} from URL ${apiURL}`)
    }

    let jsonContentsFull = JSON.parse(jsonStringAPIResponse);

    // Massage the data. v3 assets/feature_releases is different from v2 assets, it groups by release.
    // So I gotta flatten, and keep only the latest per-architecture.
    // Understand: "aarch64" might only have a binary in a release that is NOT the latest.
    let binaryPerArch = {};
    let releaseCounter = 0;
    for (let jsonRelease of jsonContentsFull) {
        releaseCounter++;
        for (let jsonBinary of jsonRelease.binaries) {
            let arch = jsonBinary.architecture;
            if (binaryPerArch[arch]) {
                //console.warn(`Already got release for arch ${arch} !`);
                continue;
            } else {
                if (releaseCounter > 1) {
                    console.warn(`Got a release arch ${arch} of release counter ${releaseCounter} for release ${jdkVersion} jvm ${hotspotOrOpenJ9} type ${jdkOrJre}`);
                }
                binaryPerArch[arch] = {release: jsonRelease, binary: jsonBinary};
            }

        }
    }

    let archData = new Map(); // builds per-architecture
    let slugs = new Map();
    let allDebArches = [];
    let debChangeLogArches = [];
    let highestBuildTS = 0;

    let jdkJreVersionJvmType = `${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`;

    let commonProps = {
        jdkVersion: jdkVersion,
        destDir: `adoptium-${jdkVersion}-${jdkOrJre}-${hotspotOrOpenJ9}`,
        jdkJre: jdkOrJre,
        JDKorJREupper: jdkOrJre.toUpperCase(),
        jvmType: hotspotOrOpenJ9,
        jvmTypeDesc: (hotspotOrOpenJ9 === "openj9" ? "OpenJ9" : "Hotspot"),
        jdkJreVersionJvmType: jdkJreVersionJvmType,
    };

    commonProps.fullHumanTitle = `Adoptium Temurin ${commonProps.JDKorJREupper} ${commonProps.jdkVersion} with ${commonProps.jvmTypeDesc}`;
    commonProps.isDefaultForVirtualPackage = (jdkOrJre === "jdk" && hotspotOrOpenJ9 === "hotspot");

    let relCounter = 0;
    for (let oneRelease of Object.values(binaryPerArch)) {
        let sha256sum = oneRelease.binary.package.checksum;

        if (!wantedArchs.has(oneRelease.binary.architecture)) {
            console.warn(`Unhandled architecture: ${oneRelease.binary.architecture} for ${jdkJreVersionJvmType} `);
            continue;
        }

        let debArch = archMapJdkToDebian[oneRelease.binary.architecture];

        let buildTS = moment(oneRelease.release.timestamp, moment.ISO_8601);
        let updatedTS = moment(oneRelease.binary.updated_at, moment.ISO_8601);
        let highTS = (buildTS > updatedTS) ? buildTS : updatedTS;
        highestBuildTS = (highTS > highestBuildTS) ? highTS : highestBuildTS;

        let buildInfo = Object.assign(
            {
                arch: oneRelease.binary.architecture,
                jdkArch: oneRelease.binary.architecture,
                debArch: debArch,
                slug: oneRelease.release.release_name,
                filename: oneRelease.binary.package.name,
                downloadUrl: oneRelease.binary.package.link,
                sha256sum: sha256sum
            },
            commonProps);

        archData.set(buildInfo.arch, buildInfo);

        // Hack, some builds have the openj9 version in them, some don't; normalize so none do
        let slugKey = oneRelease.release.release_name.split(/_openj9/)[0]
            .replace("-", "")
            .replace("jdk", "")
            .replace("jre", "")
            .replace("+", "b");

        if (!slugs.has(slugKey)) slugs.set(slugKey, []);
        slugs.get(slugKey).push(buildInfo.jdkArch);

        allDebArches.push(debArch);
        debChangeLogArches.push(`  * Exact version for architecture ${debArch}: ${oneRelease.release.release_name}`);
        relCounter++;
    }

    if (relCounter === 0) {
        throw new Error(`No valid releases found for ${jdkJreVersionJvmType}`);
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

function calculateJoinedVersionForAllArches(slugs, highestBuildTS) {
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

async function walk(dir, filelist = [], dirbase = "") {
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

async function writeTemplateFile(destPathBase, templateFile, destFileTemplated, modifiedContents) {
    let destFileParentDir = destPathBase + "/" + templateFile.dirs;
    let fullDestPath = destPathBase + "/" + (templateFile.dirs ? templateFile.dirs + "/" : "") + destFileTemplated;
    //console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir}) [exec: ${templateFile.executable}]`);

    await fs.mkdir(destFileParentDir, {recursive: true});
    await fs.writeFile(fullDestPath, modifiedContents, {
        encoding: 'utf8',
        mode: templateFile.executable ? 0o777 : 0o666
    });
}

async function recursiveChangeFileDate(destPath, newDate) {
    let matchedFiles = await getFiles(destPath);
    for (let file of matchedFiles) {
        regular_fs.utimesSync(file, newDate, newDate);
    }
}

function getFiles(matcherPath) {
    return new Promise((resolve, reject) => {
        glob([`${matcherPath}/**`], {realpath: true}, (err, files) => {
            if (err) reject(err);
            else {
                resolve(files)
            }
        })
    })
}


async function processTemplates(templateFiles, destPathBase, fnView, view, writeFiles) {
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
