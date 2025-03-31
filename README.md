# Node-RED Subflow Packager

![Bash](https://img.shields.io/badge/Bash-Script-green)
![Node-RED](https://img.shields.io/badge/Node--RED-Compatible-red)
![License](https://img.shields.io/badge/license-MIT-blue)

A Bash script to transform Node-RED subflows into reusable npm packages with ease. Made with GROK with my studious direction.

## Overview

The `node-red-subflow-packager.sh` script simplifies the process of packaging Node-RED subflows (Node-Red Experimental) into npm modules. Whether you’re working with a single `flows.json` file or a folder of subflow JSONs, this tool extracts, processes, and bundles your subflows into a ready-to-publish package.

### Problem:

Coming from a Sedona/Niagara background in the building controls industry of kits, modules, palettes...
- Subflows can be packaged as nodes into npm modules but this is experimental and requires some tedious manual work.
- Exporting is either all as one or one by one. Too tedious to update 10's or 100's of subflows.
- Without packaging as a module, updates and portability suffer.
- Creating custom nodes is great, but creating subflows is a powerful feature.

### Workflow:

Create 'kits' or 'libraries' of your subflow functions by using a tab as a workspace. Setup your subflows in a demostration type manner as you build and test. Export/backup, convert, package with a version, publish to npm if you desire... 

From inside Node-Red, in the 'Manage Palette' view, you can upload a local archive, .tgz file, to the platform, with version, and effectively update or add your subflows as nodes. 

Simply export the entire tab/workspace as a flows.json (you can name it what you want). This is useful for backups and easy to do. Then run this script with the 'from-flows-file' command so essentially this will:
1. Prompt you for needed configuration data
2. Export all the subflows to individually named files.
   - (from-flows-file uses the name set in the 'edit properties' view within the subflow wiresheet)
3. Modify the format of the json files according to documentation.
   - (https://nodered.org/docs/creating-nodes/subflow-modules#adding-subflow-metadata)
4. Prefix the 'id' field with the subflow name so you can tell what it is in the 'Manage Palette' view of used nodes.
5. Create a folder structure, package.json, and a subflows.js to read and wrap the subflows.

Then use the pack command and others to
- Create a .tgz archive for distribution.
- Publish to npm. (not tested)
- Manually update to Node-Red. (Automatic update not tested)

### Features

- **Flexible Input**: Process subflows from a `flows.json` file or a folder of JSON files.
- **Customizable Output**: Choose between one combined file or individual files per subflow.
- **NPM Ready**: Generates `package.json` and `subflows.js` for seamless Node-RED integration.
- **Version Control**: Specify your package version at creation.
- **Multi-Step Workflow**: Extract, pack, publish, or update remote controllers.

## Prerequisites

- **Node.js & npm**: For packaging and publishing.
- **jq**: For JSON processing (`sudo apt-get install jq` on Debian-based systems).
- **Node-RED**: To test your subflows (optional).

## Installation

 1. Download or clone this repository:

   ```
   git clone https://github.com/yourusername/node-red-subflow-packager.git
   cd node-red-subflow-packager
   Make the script executable:
   chmod +x node-red-subflow-packager.sh
   ```

## Usage

The script supports multiple commands:
 ```bash
 ./node-red-subflow-packager.sh [from-folder|from-flows-file|pack|publish|update] <folder_path_or_file>
 ```

## Commands

### from-flows-file <flows.json>
Extracts subflows from a Node-RED flows.json file, processes them, and creates the npm module structure.

Prompts for username, package name, category, subflow format, and version.

Example:
You can provide absolut paths here.
 ``` 
 ./node-red-subflow-packager.sh from-flows-file ~/flows.json
 ```
### from-folder <folder>
Processes pre-extracted subflow JSON files from a folder into an npm module.

Example:
You can provide absolut paths here.
 ```
 ./node-red-subflow-packager.sh from-folder ~/subflows
 ```

### pack
Packages the module into a .tgz file.

Example:
You need to navigate to the directory and invoke the script.
 ```
 ./node-red-subflow-packager.sh pack
 ```
### publish (untested)
Publishes the package to npm (increments patch version).

Example:
 ```
 ./node-red-subflow-packager.sh publish
 ```
### update (untested)
Deploys the package to remote Node-RED controllers (edit CONTROLLERS array in script).

Example:
 ```
 ./node-red-subflow-packager.sh update
 ```

## Example Workflow

### Export
Export a tab/workspace to the local file system from within Node-Red. (/home/youruser/.node-red/lib/flows/MyDevelopmentTab/flows.json)

### Create a Package
```
/home/youruser/scripts/node-red-subflow-packager.sh from-flows-file /home/youruser/.node-red/lib/flows/MyDevelopmentTab/flows.json
```

Answer prompts (e.g., yourname, node-red-contrib-myflow, control, 2, 1.0.0).

Outputs to ~/@yourname/node-red-contrib-myflow.

### Package It
Navigate to the directory that was created then,
 ```
 /home/youruser/scripts/node-red-subflow-packager.sh pack
 ```
Creates node-red-contrib-myflow-1.0.0.tgz.

Using Visual Studio Code you can 'Download' this archive since Node-Red doesn't provide an option to upload from an archive that is local.

Go back to Node-Red > Top Right Hamburger Menu > Manage Palette > Click on the Install Tab > Click the button for 'Upload module tgz file' > Upload

### Publish (Optional)
 ```
 npm login
 /home/youruser/scripts/node-red-subflow-packager.sh publish
 ```
Publishes to npm as @yourname/node-red-contrib-myflow.

## How It Works

### from-flows-file
Extracts subflows from a flows.json file into temporary files.

Processes them into the target directory with proper IDs and structure.

Generates package.json and subflows.js for Node-RED compatibility.

### from-folder
Takes existing subflow JSONs, ensures unique IDs from file name, and organizes them.

Supports combining into one file or keeping separate files.

ID Handling: Prevents double-prefixing by checking existing IDs.

Config Persistence: Saves settings to ~/.subflow_packager_config for subsequent steps.

## Script Details
Dependencies: npm, jq.

Output: ~/@<username>/<package-name> with subflows/, package.json, and subflows.js.

Subflow Format Options:
1: One subflows.json file with all subflows.

2: One JSON file per subflow in subflows/.

## Contributing
Found a bug or have a feature idea? Open an issue or submit a pull request on GitHub. Contributions are appreciated!

## License
This script is licensed under the MIT License. See the LICENSE file for details.

## Acknowledgments
- Inspired by the Node-RED community
- Thanks to the jq team for a powerful JSON processor.
- Thank you Grok.

