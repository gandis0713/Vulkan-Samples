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
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
DOCKER_IMAGE="vulkan-samples-rpi5:latest"
BUILD_DIR="${PROJECT_ROOT}/build/rpi5"
CONTAINER_NAME="vulkan-samples-rpi5-build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Parse command line arguments
BUILD_TYPE="Release"
CLEAN_BUILD=false
INTERACTIVE=false
CMAKE_ARGS=""
BUILD_TARGETS=()

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build Vulkan Samples for Raspberry Pi 5 OS using Docker

OPTIONS:
    -h, --help              Show this help message
    -d, --debug             Build in Debug mode (default: Release)
    -c, --clean             Clean build directory before building
    -i, --interactive       Start an interactive shell in the container
    -j, --jobs N            Number of parallel build jobs (default: auto)
    -t, --target TARGET     Build only specific target/sample (can be used multiple times)
    --cmake-args "ARGS"     Additional CMake arguments

EXAMPLES:
    $0                                          Build all samples in Release mode
    $0 -d                                       Build all in Debug mode
    $0 -t hello_triangle                        Build only hello_triangle sample
    $0 -t hello_triangle -t compute_nbody       Build multiple specific samples
    $0 -c                                       Clean build and rebuild
    $0 -i                                       Start interactive shell
    $0 --cmake-args "-DVKB_BUILD_TESTS=ON"      Pass custom CMake args

AVAILABLE SAMPLE TARGETS:
    API: hello_triangle, compute_nbody, dynamic_uniform_buffers, texture_loading,
         hdr, instancing, terrain_tessellation, oit_linked_lists, etc.
    Extensions: ray_tracing_basic, mesh_shading, push_descriptors,
                fragment_shading_rate, graphics_pipeline_library, etc.
    Performance: swapchain_images, pipeline_cache, render_passes, msaa,
                 subpasses, pipeline_barriers, etc.

    Run with -i and execute 'cmake --build build/rpi5 --target help' to see all targets
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
        -i|--interactive)
            INTERACTIVE=true
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

# Build Docker image
print_info "Building Docker image for Raspberry Pi 5..."
docker build \
    -f "${SCRIPT_DIR}/Dockerfile.rpi5" \
    -t "${DOCKER_IMAGE}" \
    "${SCRIPT_DIR}"

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    print_warn "Cleaning build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
fi

# Create build directory
mkdir -p "${BUILD_DIR}"

# Interactive mode
if [ "$INTERACTIVE" = true ]; then
    print_info "Starting interactive shell in Raspberry Pi 5 build container..."
    docker run --rm -it \
        --name "${CONTAINER_NAME}" \
        -v "${PROJECT_ROOT}:/workspace" \
        -w /workspace \
        "${DOCKER_IMAGE}" \
        /bin/bash
    exit 0
fi

# Determine number of jobs
if [ -z "$JOBS" ]; then
    JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

print_info "Building Vulkan Samples for Raspberry Pi 5..."
print_info "Build Type: ${BUILD_TYPE}"
print_info "Build Directory: ${BUILD_DIR}"
print_info "Parallel Jobs: ${JOBS}"

# Prepare target list for display and build
if [ ${#BUILD_TARGETS[@]} -eq 0 ]; then
    print_info "Build Targets: ALL"
    TARGET_BUILD_CMD="cmake --build build/rpi5 --parallel ${JOBS}"
else
    print_info "Build Targets: ${BUILD_TARGETS[*]}"
    TARGET_LIST=""
    for target in "${BUILD_TARGETS[@]}"; do
        TARGET_LIST="${TARGET_LIST} --target ${target}"
    done
    TARGET_BUILD_CMD="cmake --build build/rpi5 --parallel ${JOBS}${TARGET_LIST}"
fi

# Initialize git submodules if needed
print_info "Checking git submodules..."
if [ -d "${PROJECT_ROOT}/.git" ]; then
    cd "${PROJECT_ROOT}"
    git submodule update --init --recursive
fi

# Run build in container
docker run --rm \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_ROOT}:/workspace" \
    -w /workspace \
    "${DOCKER_IMAGE}" \
    /bin/bash -c "
        set -e

        echo 'Initializing git submodules...'
        if [ -d .git ]; then
            git submodule update --init --recursive
        fi

        echo 'Configuring CMake...'
        cmake -B build/rpi5 \
            -G Ninja \
            -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
            -DCMAKE_C_COMPILER_LAUNCHER=ccache \
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
            ${CMAKE_ARGS}

        echo 'Building...'
        ${TARGET_BUILD_CMD}

        echo 'Build complete!'
    "

print_info "Build completed successfully!"
print_info "Binaries are available in: ${BUILD_DIR}"
print_info ""
print_info "To run on Raspberry Pi 5:"
print_info "  1. Copy the build/rpi5 directory to your Raspberry Pi 5"
print_info "  2. Install runtime dependencies:"
print_info "     sudo apt-get install libvulkan1 mesa-vulkan-drivers vulkan-tools"
print_info "  3. Run samples from build/rpi5/app/bin/"
