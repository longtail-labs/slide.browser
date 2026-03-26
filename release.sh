#!/bin/bash
# Local build and release script for Slide

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# Check if we're in the right directory
if [ ! -f "conveyor.conf" ] || [ ! -d "Slide" ]; then
    print_error "Error: This script must be run from the SlideNative root directory"
    exit 1
fi

# Function to validate version format
validate_version() {
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Invalid version format. Please use semantic versioning (e.g., 1.0.0)"
        return 1
    fi
    return 0
}

# Welcome message
echo ""
print_info "==================================="
print_info "    Slide Local Release Builder    "
print_info "==================================="
echo ""

# Determine version from version.txt and bump build number
VERSION_FILE="version.txt"

if [ ! -f "$VERSION_FILE" ]; then
    print_warning "No $VERSION_FILE found. Creating one with default version 0.1.0"
    echo "0.1.0" > "$VERSION_FILE"
fi

# Read and trim whitespace/newlines
CURRENT_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

if ! validate_version "$CURRENT_VERSION"; then
    print_error "Version in $VERSION_FILE is invalid. Expected MAJOR.MINOR.BUILD (e.g., 0.1.0)"
    exit 1
fi

IFS='.' read -r MAJOR MINOR BUILD <<< "$CURRENT_VERSION"

if [[ -z "$MAJOR" || -z "$MINOR" || -z "$BUILD" ]]; then
    print_error "Failed to parse version from $VERSION_FILE"
    exit 1
fi

if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    print_error "Build number (third segment) must be numeric"
    exit 1
fi

BUILD=$((BUILD + 1))
VERSION="${MAJOR}.${MINOR}.${BUILD}"

# Persist bumped version back to file
echo "$VERSION" > "$VERSION_FILE"
print_success "✓ Bumped version: $CURRENT_VERSION -> $VERSION (saved to $VERSION_FILE)"

# Summary
echo ""
print_info "Build Configuration:"
echo "  Version: $VERSION"
echo "  Version file: $VERSION_FILE"
echo "  Config: conveyor.local.conf"
echo ""
print_warning "Press Enter to continue or Ctrl+C to cancel..."
read -r

# Step 1: Clean previous builds
print_info "\n📧 Cleaning previous builds..."
rm -rf build/
rm -rf Slide/Slide/build/
rm -rf output/
print_success "✓ Clean complete"

# Step 2: Build Swift Package
print_info "\n📦 Building Swift Package..."
cd SlideCore
swift build -c release
cd ..
print_success "✓ Swift Package built"

# Step 3: Update version in Xcode project
print_info "\n🔢 Updating version to $VERSION..."
cd Slide/Slide
xcrun agvtool new-marketing-version "$VERSION"
xcrun agvtool new-version -all "$VERSION"
cd ../..
print_success "✓ Version updated"

# Step 4: Build macOS app
print_info "\n🔨 Building macOS app..."

# Build locally with development signing instead of CI signing
cd Slide/Slide

# Clean build folder
rm -rf build

# Resolve dependencies
xcodebuild -resolvePackageDependencies \
    -project "Slide.xcodeproj" \
    -scheme "Slide" \
    -derivedDataPath build

# Build without code signing (Conveyor will handle signing)
xcodebuild build \
    -project "Slide.xcodeproj" \
    -scheme "Slide" \
    -configuration "Release" \
    -derivedDataPath build \
    -destination 'platform=macOS' \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    COMPILER_INDEX_STORE_ENABLE=NO

cd ../..
print_success "✓ macOS app built"

# Step 5: Copy built app to expected location
print_info "\n📦 Preparing app bundle..."
mkdir -p build/Build/Products/Release

if [ -d "Slide/Slide/build/Build/Products/Release/Slide.app" ]; then
    cp -R "Slide/Slide/build/Build/Products/Release/Slide.app" "build/Build/Products/Release/"
    print_success "✓ App bundle copied"
else
    print_error "Build failed! App bundle not found."
    exit 1
fi

print_info "\n📋 App bundle contents:"
ls -la build/Build/Products/Release/Slide.app/Contents/

# Step 6: Run Conveyor
print_info "\n📦 Packaging with Conveyor..."

# Set build version for Conveyor
export BUILD_VERSION="$VERSION"

# Run Conveyor
if command -v conveyor &> /dev/null; then
    print_info "Creating release package..."
    conveyor -f conveyor.local.conf -Kapp.machines=mac.aarch64 make copied-site
    print_success "✓ Conveyor packaging complete"
else
    print_error "Conveyor not found. Please install Conveyor first:"
    echo "  https://www.hydraulic.dev/docs/installation"
    exit 1
fi

# Show output location
if [ -d "output" ]; then
    print_info "\n📁 Output files:"
    ls -la output/*.{dmg,zip} 2>/dev/null || true
fi

# Step 7: Create a git tag for this release
print_info "\n🏷️  Creating git tag for this release..."
TAG_NAME="v$VERSION"
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    print_warning "Tag $TAG_NAME already exists; skipping tag creation"
else
    git tag -a "$TAG_NAME" -m "Release version $VERSION"
    print_success "✓ Created tag: $TAG_NAME"
    print_info "To push the tag: git push origin $TAG_NAME"
fi

# Final summary
echo ""
print_success "==================================="
print_success "        Build Complete! 🎉         "
print_success "==================================="
echo ""
print_info "Version: $VERSION"

if [ -d "output" ]; then
    print_info "\nDistribution files:"
    ls output/*.{dmg,zip} 2>/dev/null | while read -r file; do
        echo "  - $(basename "$file") ($(du -h "$file" | cut -f1))"
    done
fi

echo ""
