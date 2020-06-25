// @ts-check
// Create a tar asset for publishing to the Office feed

const fs = require("fs");
const path = require("path");
const execSync = require("child_process").execSync;
const {pkgJsonPath, publishBranchName, gatherVersionInfo} = require('./versionUtils');

function exec(command) {
  try {
    console.log(`Running command: ${command}`);
    return execSync(command, {
      stdio: "inherit"
    });
  } catch (err) {
    process.exitCode = 1;
    console.log(`Failure running: ${command}`);
    throw err;
  }
}

function doPublish(fakeMode) {
  console.log(`Target branch to publish to: ${publishBranchName}`);

  const {releaseVersion, branchVersionSuffix} = gatherVersionInfo()

  const onlyTagSource = !!branchVersionSuffix;
  if (!onlyTagSource) {
    // -------- Generating Android Artifacts with JavaDoc
    exec(path.join(process.env.BUILD_SOURCESDIRECTORY, "gradlew") + " installArchives");

    // undo uncommenting javadoc setting
    exec("git checkout ReactAndroid/gradle.properties");
  }

  // Create tar file
  exec(`npm pack`);

  const npmTarFileName = `react-native-${releaseVersion}.tgz`;
  const npmTarPath = path.resolve(__dirname, '..', npmTarFileName);
  const finalTarPath = path.join(process.env.BUILD_STAGINGDIRECTORY, 'final', npmTarFileName);
  console.log(`Copying tar file ${npmTarPath} to: ${finalTarPath}`)
  
  if(fakeMode) {
    if (!fs.existsSync(npmTarPath))
      throw "The final artefact to be published is missing.";
  } else {
    console.log(`Successfully published.`)
    
    // TODO:: Uncomment before merging the PR.
    // fs.copyFileSync(npmTarPath, finalTarPath);
  }
}

var args = process.argv.slice(2);

let fakeMode = false;
console.log(args.toString());
if (args.length > 0 && args[0] === '--fake')
  fakeMode = true;

doPublish(fakeMode);