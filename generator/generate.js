const fs = require('fs').promises;
const path = require('path');
const mustache = require('mustache');

async function main () {
    var templateFiles = await walk("../templates");
    var generatedDirBase = "../generated";

    await processTemplates(templateFiles, "java8", `${generatedDirBase}/ubuntu/xenial`, {
        series: "xenial",
        version: "0.0.2"
    });
    await processTemplates(templateFiles, "java8", `${generatedDirBase}/ubuntu/trusty`, {
        series: "trusty",
        version: "0.0.3"
    });
}

async function walk (dir, filelist = [], dirbase = "") {
    const files = await fs.readdir(dir);
    for (let file of files) {
        const filepath = path.join(dir, file);
        /** @type {!fs.Stats} yeah... */
        const stat = await fs.stat(filepath);
        if (stat.isDirectory()) {
            filelist = await walk(filepath, filelist, (dirbase ? dirbase + "/" : "") + file);
        } else {
            filelist.push({file: file, dirs: dirbase, fullpath: filepath});
        }
    }
    return filelist;
}

async function processTemplates (templateFiles, javaVersionPkg, destPathBase, view) {
    for (let templateFile of templateFiles) {
        let destFileTemplated = templateFile.file.replace("javaX", javaVersionPkg);

        let destFileParentDir = destPathBase + "/" + templateFile.dirs;
        let fullDestPath = destPathBase + "/" + (templateFile.dirs ? templateFile.dirs + "/" : "") + destFileTemplated;
        console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir})`);

        let originalContents = await fs.readFile(templateFile.fullpath, 'utf8');
        let modifiedContents = mustache.render(originalContents, view);

        // ready to write to dest? lets go...
        await fs.mkdir(destFileParentDir, {recursive: true});
        await fs.writeFile(fullDestPath, modifiedContents, 'utf8');
    }
}

main().then(value => {
    console.log("done.");
    process.exit(0);
}).catch(reason => {
    console.error(reason);
    process.exit(1);
});