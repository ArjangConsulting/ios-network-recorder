#!/bin/bash
set -e

echo "Creating static libraries from existing build products..."

BUILD_DIR=".build/apple/Products/Release"
OUTPUT_DIR="/Users/maniramezan/Developer/novalingo/mobile/iOS/Frameworks"

mkdir -p "$OUTPUT_DIR"

# Create static libraries from .o files
for MODULE in APITraceCore APITraceDebug APITraceNoop; do
    echo "Creating lib${MODULE}.a..."
    ar -rcs "$OUTPUT_DIR/lib${MODULE}.a" "$BUILD_DIR/${MODULE}_Module.o"
    
    # Copy Swift module files
    echo "Copying ${MODULE}.swiftmodule..."
    cp -R "$BUILD_DIR/${MODULE}.swiftmodule" "$OUTPUT_DIR/"
done

echo "✅ Static libraries created in $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
