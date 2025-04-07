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
    read -p "Enter package name (e.g., node-red-contrib-custom-control): " PACKAGE_NAME
    if [[ -z "$PACKAGE_NAME" ]]; then
        PACKAGE_NAME="node-red-contrib-custom-control"
        echo "Using default package name: $PACKAGE_NAME"
    fi
    MODULE_NAME="@$USERNAME/$PACKAGE_NAME"
    OUTPUT_DIR="$HOME/@${USERNAME}/${PACKAGE_NAME}"
    read -p "Enter the category for the subflows (e.g., subflows, control, custom): " SUBFLOW_CATEGORY
    if [[ -z "$SUBFLOW_CATEGORY" ]]; then
        SUBFLOW_CATEGORY="control"
        echo "Using default category: $SUBFLOW_CATEGORY"
    fi
}

# Prompt user for subflow representation (keeping for compatibility, but we'll override)
prompt_subflow_format() {
    echo "Note: This script now uses one .js file per subflow, packaged in a single archive."
    SUBFLOW_FORMAT=2  # Force multi-file style internally, but we'll adapt
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
    mkdir -p "$OUTPUT_DIR"

    SUBFLOW_FILES=$(find "$INPUT_FOLDER" -maxdepth 1 -name "*.json")
    if [ -z "$SUBFLOW_FILES" ]; then
        echo "No JSON files found in $INPUT_FOLDER."
        exit 1
    fi

    VALID_FILES=0
    NODE_ENTRIES=""
    for file in $SUBFLOW_FILES; do
        ORIGINAL_NAME=$(basename "$file" .json | tr '[:upper:]' '[:lower:]')  # Lowercase for consistency
        SUBFLOW_FILE="$OUTPUT_DIR/${ORIGINAL_NAME}.json"
        JS_FILE="$OUTPUT_DIR/${ORIGINAL_NAME}.js"
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
        ' "$file" > "$SUBFLOW_FILE"
        if [ ! -s "$SUBFLOW_FILE" ] || ! jq -e . "$SUBFLOW_FILE" >/dev/null 2>&1; then
            echo "Warning: Failed to process subflow in $file - output is empty or invalid"
            rm "$SUBFLOW_FILE"
            continue
        fi

        # Create .js file for this subflow
        cat > "$JS_FILE" <<EOF
const fs = require('fs');
const path = require('path');

module.exports = function(RED) {
    const subflowFile = path.join(__dirname, '${ORIGINAL_NAME}.json');
    const subflowContents = fs.readFileSync(subflowFile, 'utf8');
    const subflowJSON = JSON.parse(subflowContents);
    RED.nodes.registerSubflow(subflowJSON);
};
EOF

        echo "Processed $ORIGINAL_NAME to $SUBFLOW_FILE and $JS_FILE"
        NODE_ENTRIES="$NODE_ENTRIES\"$ORIGINAL_NAME\": \"${ORIGINAL_NAME}.js\","
        ((VALID_FILES++))
    done

    if [ "$VALID_FILES" -eq 0 ]; then
        echo "Error: No valid subflow JSON files found."
        exit 1
    fi

    # Create package.json with all nodes
    NODE_ENTRIES=${NODE_ENTRIES%,}  # Remove trailing comma
    cat > "$OUTPUT_DIR/package.json" <<EOF
{
  "name": "$MODULE_NAME",
  "version": "$VERSION",
  "description": "Custom subflows packaged for Node-RED",
  "keywords": ["node-red", "custom", "control"],
  "node-red": {
    "version": ">=1.3.0",
    "nodes": { $NODE_ENTRIES }
  },
  "author": "$USERNAME",
  "license": "MIT"
}
EOF

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

    SUBFLOW_COUNT=$(jq -r '[.[] | select(.type == "subflow")] | length' "$FLOWS_FILE")
    if [ "$SUBFLOW_COUNT" -eq 0 ]; then
        echo "No subflows found in $FLOWS_FILE."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo "Found $SUBFLOW_COUNT subflows. Extracting..."
    jq -r '.[] | select(.type == "subflow") | .name' "$FLOWS_FILE" | sort -u | while read -r subflow_name; do
        SAFE_NAME=$(echo "$subflow_name" | tr -dc '[:alnum:]-_' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        OUTPUT_FILE="$TEMP_DIR/${SAFE_NAME}.json"
        jq -r --arg name "$subflow_name" --arg category "$SUBFLOW_CATEGORY" --arg fname "$SAFE_NAME" '
            [.[] | select(.type == "subflow" and .name == $name)][0] as $subflow |
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
                    flow: [.[] | select(.z? == $subflow.id)]  # Collect all nodes in one array
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

    if [ -n "$(ls -A "$TEMP_DIR")" ]; then
        echo "Creating npm module structure in $OUTPUT_DIR..."
        mkdir -p "$OUTPUT_DIR"
        NODE_ENTRIES=""
        VALID_FILES=0

        for file in "$TEMP_DIR"/*.json; do
            if [ ! -f "$file" ]; then continue; fi
            ORIGINAL_NAME=$(basename "$file" .json)
            SUBFLOW_FILE="$OUTPUT_DIR/${ORIGINAL_NAME}.json"
            JS_FILE="$OUTPUT_DIR/${ORIGINAL_NAME}.js"
            mv "$file" "$SUBFLOW_FILE"
            
            cat > "$JS_FILE" <<EOF
const fs = require('fs');
const path = require('path');

module.exports = function(RED) {
    const subflowFile = path.join(__dirname, '${ORIGINAL_NAME}.json');
    const subflowContents = fs.readFileSync(subflowFile, 'utf8');
    const subflowJSON = JSON.parse(subflowContents);
    RED.nodes.registerSubflow(subflowJSON);
};
EOF

            echo "Processed $ORIGINAL_NAME to $SUBFLOW_FILE and $JS_FILE"
            NODE_ENTRIES="$NODE_ENTRIES\"$ORIGINAL_NAME\": \"${ORIGINAL_NAME}.js\","
            ((VALID_FILES++))
        done

        if [ "$VALID_FILES" -eq 0 ]; then
            echo "Error: No valid subflow JSON files extracted."
            rm -rf "$TEMP_DIR"
            exit 1
        fi

        NODE_ENTRIES=${NODE_ENTRIES%,}
        cat > "$OUTPUT_DIR/package.json" <<EOF
{
  "name": "$MODULE_NAME",
  "version": "$VERSION",
  "description": "Custom control subflows packaged for Node-RED",
  "keywords": ["node-red", "custom", "control"],
  "node-red": {
    "version": ">=1.3.0",
    "nodes": { $NODE_ENTRIES }
  },
  "author": "$USERNAME",
  "license": "MIT"
}
EOF

        save_config
        echo "Module structure created."
    else
        echo "No valid subflow files extracted from $FLOWS_FILE."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

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