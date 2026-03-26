#!/bin/bash

# ObjectBox Code Generator Script for SlideCore Package
# This script runs the ObjectBox code generator with public visibility for the generated code

# Set the working directory to the SlideCore package
cd "$(dirname "$0")/SlideCore" || exit 1

# Run the ObjectBox generator plugin with public visibility
# swift package --allow-writing-to-package-directory generate-objectbox-models \
#     --visibility public

swift package plugin --allow-writing-to-package-directory --allow-network-connections all objectbox-generator --target SlideDatabase --visibility public

echo "ObjectBox code generation completed with public visibility"