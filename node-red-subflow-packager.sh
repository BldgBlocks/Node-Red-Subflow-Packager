#!/bin/bash

# Default configuration
CONFIG_FILE="$HOME/.subflow_packager_config"
TEMP_DIR="/tmp/subflow_export_$$"  # Unique temp dir per run

# Usage
usage() {
    echo "Usage: $0 [from-folder|from-flows-file|pack|publish|update] <folder_path_or_file>"
    echo "  from-folder     - Process subflows from an existing folder"
    echo "  from-flows-file - Process subflows from a flows.json file and create module"
    echo "  pack            - Package as .tgz"
    echo "  publish         - Publish to npm"
    echo "  update          - Update on remote controllers"
    exit 1
}

# Check dependencies
command -v npm >/dev/null 2>&1 || { echo "npm is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# Load or set OUTPUT_DIR
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    if [ -z "$OUTPUT_DIR" ] && [ "$1" != "from-folder" ] && [ "$1" != "from-flows-file" ]; then
        echo "No output directory set. Run 'from-folder' or 'from-flows-file' first."
        exit 1
    fi
}

save_config() {
    echo "OUTPUT_DIR=\"$OUTPUT_DIR\"" > "$CONFIG_FILE"
    echo "MODULE_NAME=\"$MODULE_NAME\"" >> "$CONFIG_FILE"
    echo "SUBFLOW_FORMAT=\"$SUBFLOW_FORMAT\"" >> "$CONFIG_FILE"
    echo "USERNAME=\"$USERNAME\"" >> "$CONFIG_FILE"
    echo "SUBFLOW_CATEGORY=\"$SUBFLOW_CATEGORY\"" >> "$CONFIG_FILE"
    echo "VERSION=\"$VERSION\"" >> "$CONFIG_FILE"
}

# Prompt user for username, package name, and category
prompt_package_details() {
    read -p "Enter your npm username (e.g., johndoe): " USERNAME
    if [[ -z "$USERNAME" ]]; then
        echo "Username is required for scoped packages."
        exit 1
    fi
    read -p "Enter package name (e.g., node-red-contrib-compressor-sequencer): " PACKAGE_NAME
    if [[ -z "$PACKAGE_NAME" ]]; then
        PACKAGE_NAME="node-red-contrib-custom-subflows"
        echo "Using default package name: $PACKAGE_NAME"
    fi
    MODULE_NAME="@$USERNAME/$PACKAGE_NAME"
    OUTPUT_DIR="$HOME/@${USERNAME}/${PACKAGE_NAME}"
    read -p "Enter the category for the subflow (e.g., subflows, control, custom): " SUBFLOW_CATEGORY
    if [[ -z "$SUBFLOW_CATEGORY" ]]; then
        SUBFLOW_CATEGORY="subflows"
        echo "Using default category: $SUBFLOW_CATEGORY"
    fi
}

# Prompt user for subflow representation
prompt_subflow_format() {
    echo "How to represent subflows?"
    echo "1) One file with all subflows"
    echo "2) One file per subflow"
    read -p "Choose (1 or 2): " SUBFLOW_FORMAT
    if [[ "$SUBFLOW_FORMAT" != "1" && "$SUBFLOW_FORMAT" != "2" ]]; then
        SUBFLOW_FORMAT=1
        echo "Invalid choice, defaulting to one file (1)"
    fi
}

# Prompt user for version
prompt_version() {
    read -p "Enter the version (e.g., 1.0.0, press Enter for default 1.0.0): " VERSION
    if [[ -z "$VERSION" ]]; then
        VERSION="1.0.0"
        echo "Using default version: $VERSION"
    fi
    if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Invalid version format. Using default: 1.0.0"
        VERSION="1.0.0"
    fi
}

# Step 1a: Process subflows from existing folder
from_folder() {
    if [ -z "$2" ]; then
        echo "Please provide the folder path containing subflow JSON files."
        exit 1
    fi
    INPUT_FOLDER="$2"
    if [ ! -d "$INPUT_FOLDER" ]; then
        echo "Folder '$INPUT_FOLDER' does not exist."
        exit 1
    fi

    echo "Processing subflows from $INPUT_FOLDER..."
    echo "Output directory set to: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/subflows"

    SUBFLOW_FILES=$(find "$INPUT_FOLDER" -maxdepth 1 -name "*.json")
    if [ -z "$SUBFLOW_FILES" ]; then
        echo "No JSON files found in $INPUT_FOLDER."
        exit 1
    fi

    VALID_FILES=0
    if [[ "$SUBFLOW_FORMAT" == "1" ]]; then
        SUBFLOW_FILE="$OUTPUT_DIR/subflows/subflows.json"
        cat /dev/null > "$SUBFLOW_FILE"
        for file in $SUBFLOW_FILES; do
            ORIGINAL_NAME=$(basename "$file" .json)
            if ! jq -e . "$file" >/dev/null 2>&1; then
                echo "Warning: Skipping invalid JSON file: $file"
                continue
            fi
            jq -r --arg name "$ORIGINAL_NAME" --arg category "$SUBFLOW_CATEGORY" '
                . as $subflow |
                if $subflow.type == "subflow" then
                    {id: (if ($subflow.id | contains("-")) then $subflow.id else ($name + "-" + $subflow.id) end),
                     type: $subflow.type, name: $name, info: ($subflow.info // ""), category: $category, in: $subflow.in, out: $subflow.out, flow: $subflow.flow}
                else
                    empty
                end
            ' "$file" >> "$SUBFLOW_FILE.temp"
            ((VALID_FILES++))
        done
        if [ "$VALID_FILES" -eq 0 ]; then
            echo "Error: No valid subflow JSON files found."
            exit 1
        fi
        jq -s 'flatten' "$SUBFLOW_FILE.temp" > "$SUBFLOW_FILE"
        rm "$SUBFLOW_FILE.temp"
        echo "Combined $VALID_FILES subflows into $SUBFLOW_FILE"
    else
        for file in $SUBFLOW_FILES; do
            ORIGINAL_NAME=$(basename "$file" .json)
            SUBFLOW_FILE="$OUTPUT_DIR/subflows/${ORIGINAL_NAME}.json"
            if ! jq -e . "$file" >/dev/null 2>&1; then
                echo "Warning: Skipping invalid JSON file: $file"
                continue
            fi
            jq -r --arg name "$ORIGINAL_NAME" --arg category "$SUBFLOW_CATEGORY" '
                . as $subflow |
                if $subflow.type == "subflow" then
                    {id: (if ($subflow.id | contains("-")) then $subflow.id else ($name + "-" + $subflow.id) end),
                     type: $subflow.type, name: $name, info: ($subflow.info // ""), category: $category, in: $subflow.in, out: $subflow.out, flow: $subflow.flow}
                else
                    empty
                end
            ' "$file" > "$file.temp"
            if [ ! -s "$file.temp" ] || ! jq -e . "$file.temp" >/dev/null 2>&1; then
                echo "Warning: Failed to process subflow in $file - output is empty or invalid"
                rm "$file.temp"
                continue
            fi
            mv "$file.temp" "$SUBFLOW_FILE"
            echo "Processed $ORIGINAL_NAME to $SUBFLOW_FILE"
            ((VALID_FILES++))
        done
        if [ "$VALID_FILES" -eq 0 ]; then
            echo "Error: No valid subflow JSON files found."
            exit 1
        fi
    fi
    save_config
    echo "Next step: ./$(basename $0) pack"
}

# Step 1b: Process subflows from a flows.json file and create module
from_flows_file() {
    if [ -z "$2" ]; then
        echo "Please provide the path to the flows.json file."
        exit 1
    fi
    FLOWS_FILE="$2"
    if [ ! -f "$FLOWS_FILE" ]; then
        echo "File '$FLOWS_FILE' does not exist."
        exit 1
    fi

    echo "Processing subflows from $FLOWS_FILE..."
    mkdir -p "$TEMP_DIR"

    # Extract subflows and save as individual files
    SUBFLOW_COUNT=$(jq -r '[.[] | select(.type == "subflow")] | length' "$FLOWS_FILE")
    if [ "$SUBFLOW_COUNT" -eq 0 ]; then
        echo "No subflows found in $FLOWS_FILE."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "Found $SUBFLOW_COUNT subflows. Extracting..."
    jq -r '.[] | select(.type == "subflow") | .name' "$FLOWS_FILE" | sort -u | while read -r subflow_name; do
        SAFE_NAME=$(echo "$subflow_name" | tr -dc '[:alnum:]-_' | tr ' ' '-')
        OUTPUT_FILE="$TEMP_DIR/${SAFE_NAME}.json"
        jq -r --arg name "$subflow_name" --arg category "$SUBFLOW_CATEGORY" --arg fname "$SAFE_NAME" '
            [.[] | select(.type == "subflow" and .name == $name)][0] as $subflow |
            # Take the first instance info only
            [(.[] | select(.type == ("subflow:" + $subflow.id)) | .info? // empty)][0] as $instance_info |
            if $subflow then
                {
                    id: ($fname + "-" + $subflow.id),
                    type: $subflow.type,
                    name: $name,
                    info: ($instance_info // $subflow.info // ""),
                    category: $category,
                    in: $subflow.in,
                    out: $subflow.out,
                    flow: [.[] | select(.z? == $subflow.id)]
                }
            else
                empty
            end
        ' "$FLOWS_FILE" > "$OUTPUT_FILE"
        if [ ! -s "$OUTPUT_FILE" ] || ! jq -e . "$OUTPUT_FILE" >/dev/null 2>&1; then
            echo "Warning: Failed to extract subflow '$subflow_name' - output is empty or invalid"
            rm "$OUTPUT_FILE"
        else
            echo "Extracted $subflow_name to $OUTPUT_FILE"
        fi
    done

    # Process extracted files with from_folder and create module structure
    if [ -n "$(ls -A "$TEMP_DIR")" ]; then
        from_folder "" "$TEMP_DIR"
        echo "Creating npm module structure in $OUTPUT_DIR..."
        cd "$OUTPUT_DIR" || exit 1

        cat > package.json <<EOF
{
  "name": "$MODULE_NAME",
  "version": "$VERSION",
  "description": "Custom subflows for Node-RED",
  "keywords": ["node-red"],
  "node-red": {
    "version": ">=1.3.0",
    "nodes": ["subflows.js"]
  },
  "author": "$(whoami)",
  "license": "MIT"
}
EOF

        if [[ "$SUBFLOW_FORMAT" == "1" ]]; then
            cat > subflows.js <<EOF
module.exports = function(RED) {
    const fs = require('fs');
    const path = require('path');
    const subflowFile = path.join(__dirname, 'subflows/subflows.json');
    const subflows = JSON.parse(fs.readFileSync(subflowFile, 'utf8'));
    subflows.forEach(subflow => RED.nodes.registerSubflow(subflow));
};
EOF
        else
            cat > subflows.js <<EOF
module.exports = function(RED) {
    const fs = require('fs');
    const path = require('path');
    const subflowDir = path.join(__dirname, 'subflows');
    fs.readdirSync(subflowDir).forEach(file => {
        if (file.endsWith('.json')) {
            const subflow = JSON.parse(fs.readFileSync(path.join(subflowDir, file), 'utf8'));
            RED.nodes.registerSubflow(subflow);
        }
    });
};
EOF
        fi

        if [ ! -d "$OUTPUT_DIR/subflows" ] || [ -z "$(ls -A "$OUTPUT_DIR/subflows")" ]; then
            echo "Subflow directory empty. Something went wrong."
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        echo "Module structure created."
    else
        echo "No valid subflow files extracted from $FLOWS_FILE."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Clean up
    rm -rf "$TEMP_DIR"
    echo "Next step: ./$(basename $0) pack"
}

# Step 2: Package as .tgz
pack_module() {
    load_config
    echo "Packaging module as .tgz..."
    cd "$OUTPUT_DIR" || exit 1
    mkdir -p releases
    mv *.tgz releases/ 2>/dev/null || true
    npm pack
    echo "Packaged: $(ls *.tgz)"
    echo "Older versions in: $OUTPUT_DIR/releases/"
}

# Step 3: Publish to npm
publish_module() {
    load_config
    echo "Publishing to npm..."
    cd "$OUTPUT_DIR" || exit 1
    CURRENT_VERSION=$(jq -r .version package.json)
    NEW_VERSION=$(echo "$CURRENT_VERSION" | awk -F. '{$NF+=1; print $1"."$2"."$NF}')
    jq --arg v "$NEW_VERSION" '.version = $v' package.json > tmp.json && mv tmp.json package.json
    npm publish --access public
    echo "Published $MODULE_NAME@$NEW_VERSION to npm."
    echo "To list in Node-RED Library:"
    echo "1. Visit https://flows.nodered.org/add/node"
    echo "2. Submit with npm URL: https://www.npmjs.com/package/$MODULE_NAME"
}

# Step 4: Update remote controllers
update_controllers() {
    load_config
    echo "Updating remote controllers (edit this section for your setup)..."
    CONTROLLERS=("controller1.local" "controller2.local")
    TGZ_FILE="$OUTPUT_DIR/$(ls $OUTPUT_DIR/*.tgz | head -n 1)"
    for CONTROLLER in "${CONTROLLERS[@]}"; do
        echo "Updating $CONTROLLER..."
        scp "$TGZ_FILE" "$CONTROLLER:~/.node-red/"
        ssh "$CONTROLLER" "cd ~/.node-red && npm install $(basename "$TGZ_FILE") && systemctl restart nodered"
    done
    echo "Controllers updated."
}

# Prompt for package details, subflow format, and version once at the start, then load config for other commands
if [ "$1" == "from-folder" ] || [ "$1" == "from-flows-file" ]; then
    prompt_package_details
    prompt_subflow_format
    prompt_version
else
    load_config "$1"
fi

# Main logic
case "$1" in
    from-folder)     from_folder "$@" ;;
    from-flows-file) from_flows_file "$@" ;;
    pack)            pack_module ;;
    publish)         publish_module ;;
    update)          update_controllers ;;
    *)               usage ;;
esac