#!/bin/bash
# Copyright (c) 2025, Arm Limited and Contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 the "License";
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
BUILD_DIR="${PROJECT_ROOT}/build/native"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse command line arguments
BUILD_TYPE="Release"
CLEAN_BUILD=false
INSTALL_DEPS=false
CMAKE_ARGS=""
BUILD_TARGETS=()
GENERATOR="Ninja"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Vulkan Samples natively on Raspberry Pi 5 OS (or other Linux systems)

OPTIONS:
    -h, --help              Show this help message
    -d, --debug             Build in Debug mode (default: Release)
    -c, --clean             Clean build directory before building
    -i, --install-deps      Install required dependencies (requires sudo)
    -j, --jobs N            Number of parallel build jobs (default: auto)
    -t, --target TARGET     Build only specific target/sample (can be used multiple times)
    -g, --generator GEN     CMake generator (default: Ninja, alternatives: "Unix Makefiles")
    --cmake-args "ARGS"     Additional CMake arguments

EXAMPLES:
    $0                                          Build all samples in Release mode
    $0 -i                                       Install dependencies and build
    $0 -d                                       Build all in Debug mode
    $0 -t hello_triangle                        Build only hello_triangle sample
    $0 -t hello_triangle -t compute_nbody       Build multiple specific samples
    $0 -c                                       Clean build and rebuild
    $0 -g "Unix Makefiles"                      Use Make instead of Ninja
    $0 --cmake-args "-DVKB_BUILD_TESTS=ON"      Pass custom CMake args

AVAILABLE SAMPLE TARGETS:
    API: hello_triangle, compute_nbody, dynamic_uniform_buffers, texture_loading,
         hdr, instancing, terrain_tessellation, oit_linked_lists, etc.
    Extensions: ray_tracing_basic, mesh_shading, push_descriptors,
                fragment_shading_rate, graphics_pipeline_library, etc.
    Performance: swapchain_images, pipeline_cache, render_passes, msaa,
                 subpasses, pipeline_barriers, etc.

DEPENDENCIES:
    This script can automatically install required dependencies on Debian/Ubuntu-based systems.
    Run with -i or --install-deps to install them.

    Required packages:
    - build-essential, cmake, git, pkg-config
    - libwayland-dev, libxkbcommon-dev
    - libxrandr-dev, libxinerama-dev, libxcursor-dev, libxi-dev, libx11-dev
    - libglm-dev, libvulkan-dev
    - vulkan-tools, vulkan-validationlayers, mesa-vulkan-drivers
    - ninja-build (optional, for faster builds)
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--debug)
            BUILD_TYPE="Debug"
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -i|--install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -t|--target)
            BUILD_TARGETS+=("$2")
            shift 2
            ;;
        -g|--generator)
            GENERATOR="$2"
            shift 2
            ;;
        --cmake-args)
            CMAKE_ARGS="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
    print_step "Installing dependencies..."

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        print_info "Detected apt package manager (Debian/Ubuntu/Raspberry Pi OS)"

        sudo apt-get update
        sudo apt-get install -y \
            build-essential \
            cmake \
            git \
            pkg-config \
            libwayland-dev \
            libxkbcommon-dev \
            libxrandr-dev \
            libxinerama-dev \
            libxcursor-dev \
            libxi-dev \
            libx11-dev \
            libxxf86vm-dev \
            libglm-dev \
            libvulkan-dev \
            vulkan-tools \
            vulkan-validationlayers \
            mesa-vulkan-drivers \
            python3 \
            ninja-build

        print_info "Dependencies installed successfully!"
    else
        print_error "Unsupported package manager. Please install dependencies manually."
        print_info "See the dependency list with: $0 --help"
        exit 1
    fi
fi

# Check for required tools
print_step "Checking build environment..."

if ! command -v cmake &> /dev/null; then
    print_error "CMake not found. Install it with: sudo apt-get install cmake"
    exit 1
fi

if ! command -v git &> /dev/null; then
    print_error "Git not found. Install it with: sudo apt-get install git"
    exit 1
fi

if [ "$GENERATOR" = "Ninja" ] && ! command -v ninja &> /dev/null; then
    print_warn "Ninja not found, falling back to Unix Makefiles"
    GENERATOR="Unix Makefiles"
fi

print_info "CMake: $(cmake --version | head -n1)"
print_info "Generator: ${GENERATOR}"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    print_warn "Cleaning build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
fi

# Create build directory
mkdir -p "${BUILD_DIR}"

# Determine number of jobs
if [ -z "$JOBS" ]; then
    JOBS=$(nproc 2>/dev/null || echo 4)
fi

print_step "Configuring build..."
print_info "Build Type: ${BUILD_TYPE}"
print_info "Build Directory: ${BUILD_DIR}"
print_info "Parallel Jobs: ${JOBS}"

# Prepare target list for display and build
if [ ${#BUILD_TARGETS[@]} -eq 0 ]; then
    print_info "Build Targets: ALL"
    TARGET_BUILD_ARGS=""
else
    print_info "Build Targets: ${BUILD_TARGETS[*]}"
    TARGET_BUILD_ARGS=""
    for target in "${BUILD_TARGETS[@]}"; do
        TARGET_BUILD_ARGS="${TARGET_BUILD_ARGS} --target ${target}"
    done
fi

# Initialize git submodules if needed
print_step "Checking git submodules..."
cd "${PROJECT_ROOT}"
if [ -d ".git" ]; then
    git submodule update --init --recursive
    print_info "Git submodules initialized"
else
    print_warn "Not a git repository, skipping submodule initialization"
fi

# Configure CMake
print_step "Running CMake configuration..."
cmake -B "${BUILD_DIR}" \
    -G "${GENERATOR}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    ${CMAKE_ARGS}

# Build
print_step "Building..."
if [ -z "$TARGET_BUILD_ARGS" ]; then
    cmake --build "${BUILD_DIR}" --parallel ${JOBS}
else
    cmake --build "${BUILD_DIR}" --parallel ${JOBS} ${TARGET_BUILD_ARGS}
fi

# Success message
echo ""
print_info "============================================"
print_info "Build completed successfully!"
print_info "============================================"
print_info "Build directory: ${BUILD_DIR}"
print_info "Binaries: ${BUILD_DIR}/app/bin/"
echo ""

# Check if vulkan samples binary exists
if [ -f "${BUILD_DIR}/app/bin/vulkan_samples" ]; then
    print_info "Main executable: ${BUILD_DIR}/app/bin/vulkan_samples"
    print_info ""
    print_info "To run the samples:"
    print_info "  cd ${BUILD_DIR}/app/bin"
    print_info "  ./vulkan_samples"
elif [ ${#BUILD_TARGETS[@]} -gt 0 ]; then
    print_info "Individual sample binaries built in: ${BUILD_DIR}/app/bin/"
    print_info ""
    print_info "To run a specific sample:"
    print_info "  cd ${BUILD_DIR}/app/bin"
    for target in "${BUILD_TARGETS[@]}"; do
        if [ -f "${BUILD_DIR}/app/bin/${target}" ]; then
            print_info "  ./${target}"
        fi
    done
fi

# Verify Vulkan is available
echo ""
print_step "Verifying Vulkan installation..."
if command -v vulkaninfo &> /dev/null; then
    vulkaninfo --summary 2>/dev/null || print_warn "Vulkan may not be properly configured"
else
    print_warn "vulkaninfo not found. Install vulkan-tools to verify your Vulkan setup."
fi
