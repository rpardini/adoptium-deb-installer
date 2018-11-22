const regular_fs = require('fs');
const fs = regular_fs.promises;
const path = require('path');
const mustache = require('mustache');

async function main () {
    var templateFiles = await walk("../templates");
    var generatedDirBase = "../generated";

    await processTemplates(templateFiles, "java8", `${generatedDirBase}/ubuntu/xenial/debian`, {
        distribution: "xenial",
        version: "0.0.2~xenial"
    });
    await processTemplates(templateFiles, "java8", `${generatedDirBase}/ubuntu/trusty/debian`, {
        distribution: "trusty",
        version: "0.0.3~trusty"
    });
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
        await fs.writeFile(fullDestPath, modifiedContents, {encoding: 'utf8', mode: templateFile.executable? 0o777 : 0o666});
    }
}

main().then(value => {
    console.log("done.");
    process.exit(0);
}).catch(reason => {
    console.error(reason);
    process.exit(1);
});