const fs = require('fs').promises;
const path = require('path');

const walk = async (dir, filelist = [], dirbase = "") => {
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
};

async function main () {
    var templateFiles = await walk("../templates");
    //console.log(aff);

    let destPathBase = "../debian";
    for (let templateFile of templateFiles) {
        //console.log(templateFile);

        let destFileTemplated = templateFile.file; // @TODO: maybe do some replacement here. eg javaX to java8, java9 etc
        let destFileParentDir = destPathBase + "/" + templateFile.dirs;
        let fullDestPath = destPathBase + "/" + (templateFile.dirs ? templateFile.dirs + "/" : "") + destFileTemplated;
        console.log(`--> ${templateFile.fullpath} to ${fullDestPath} (in path ${destFileParentDir})`);

        let originalContents = await fs.readFile(templateFile.fullpath, 'utf8');
        //console.log(originalContents);

        let modifiedContents = originalContents; // @TODO: do the template processing here. its gonna be all globals.

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