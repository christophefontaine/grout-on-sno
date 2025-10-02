#!/bin/bash

# Script to convert butane files to YAML and copy other YAML files to openshift folder

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUTANE_DIR="$SCRIPT_DIR/butane"
OPENSHIFT_DIR="$SCRIPT_DIR/openshift"

# Check if butane directory exists
if [ ! -d "$BUTANE_DIR" ]; then
    echo "Error: butane directory not found at $BUTANE_DIR"
    exit 1
fi

# Create openshift directory
echo "Creating openshift directory..."
mkdir -p "$OPENSHIFT_DIR"

# Check if butane command is available
if ! command -v butane &> /dev/null; then
    echo "Error: butane command not found. Please install butane first."
    echo "You can install it from: https://github.com/coreos/butane"
    exit 1
fi

echo "Processing files in $BUTANE_DIR..."

# Process each file in the butane directory
for file in "$BUTANE_DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        
        if [[ "$filename" == *.bu ]]; then
            # Convert butane file to YAML
            yaml_filename="${filename%.bu}.yaml"
            echo "Converting $filename to $yaml_filename..."
            butane --pretty --strict "$file" > "$OPENSHIFT_DIR/$yaml_filename"
            echo "  ✓ Converted $filename -> $yaml_filename"
        elif [[ "$filename" == *.yaml ]] || [[ "$filename" == *.yml ]]; then
            # Copy YAML file directly
            echo "Copying $filename..."
            cp "$file" "$OPENSHIFT_DIR/$filename"
            echo "  ✓ Copied $filename"
        else
            echo "  ⚠ Skipping $filename (not a .bu or .yaml file)"
        fi
    fi
done

echo ""
echo "✅ Processing complete!"
echo "Generated files in $OPENSHIFT_DIR:"
ls -la "$OPENSHIFT_DIR"