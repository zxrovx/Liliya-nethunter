#!/bin/bash

# Constants
SCRIPT_VERSION="1.1"
KERNEL_DEVICES="realme_trinket"
BANNER_TEXT="#### Liliya-Nethunter ####"
LOG_FILE="kernel_build.log"
CHANGELOGS_FILE="changelogs.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display colored text
color_echo() {
    local color="$1"
    shift
    echo -e "${color}$@${NC}"
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@" >> "$LOG_FILE"
}

# Function to handle failures with specific messages
handle_failure() {
    local message="$1"
    color_echo $RED "$message"
    exit 1
}

# Function to manage dependencies
manage_dependencies() {
    color_echo $CYAN "Installing required packages..."
    sudo apt-get update && sudo apt-get install -y nano bc bison ca-certificates curl flex gcc git libc6-dev libssl-dev openssl python2 python3 ssh wget zip zstd sudo make gcc-arm-linux-gnueabi software-properties-common mc pv bc neofetch brotli llvm jq || \
        handle_failure "Failed to install required packages."
}

# Function to get the branch name, replacing invalid characters
get_branch_name() {
    local BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)"
    # Replace invalid characters in branch name with underscores
    BRANCH_NAME="${BRANCH_NAME//[^a-zA-Z0-9_-]/_}"
    echo "$BRANCH_NAME"
}

# Function to initialize and update submodules
initialize_submodules() {
    color_echo $CYAN "Initializing and updating submodules..."
    git submodule update --init || \
        handle_failure "Failed to initialize and update submodules."
}

# Function to set up Clang
setup_clang() {
    local clang_source="$1"
    local clang_dir_name="$2"

    color_echo $CYAN "Setting up Clang from $clang_source..."

    if [ ! -d "$clang_dir_name" ]; then
        mkdir -p "$clang_dir_name" || handle_failure "Failed to create directory $clang_dir_name"
        color_echo $CYAN "Downloading Clang using git..."
        if ! git clone --depth=1 "$clang_source" "$clang_dir_name"; then
            color_echo $YELLOW "Failed to clone using git, trying wget..."
            local file_name=$(basename "$clang_source")
            local file_ext="${file_name##*.}"

            if ! wget -O "$clang_dir_name/$file_name" "$clang_source"; then
                handle_failure "Failed to download Clang using wget"
            fi

            # Extract based on file extension
            case "$file_name" in
                *.tar.gz)
                    color_echo $CYAN "Extracting .tar.gz file..."
                    tar -xzf "$clang_dir_name/$file_name" -C "$clang_dir_name" --strip-components=1 || \
                        handle_failure "Failed to extract .tar.gz file"
                    ;;
                *.tar.xz)
                    color_echo $CYAN "Extracting .tar.xz file..."
                    tar -xJf "$clang_dir_name/$file_name" -C "$clang_dir_name" --strip-components=1 || \
                        handle_failure "Failed to extract .tar.xz file"
                    ;;
                *.tar.zst)
                    color_echo $CYAN "Extracting .tar.zst file..."
                    tar --zstd -xf "$clang_dir_name/$file_name" -C "$clang_dir_name" --strip-components=1 || \
                        handle_failure "Failed to extract .tar.zst file"
                    ;;
                *.zip)
                    color_echo $CYAN "Extracting .zip file..."
                    unzip "$clang_dir_name/$file_name" -d "$clang_dir_name" || \
                        handle_failure "Failed to extract .zip file"
                    ;;
                *.xz)
                    color_echo $CYAN "Extracting .xz file..."
                    unxz "$clang_dir_name/$file_name" || handle_failure "Failed to extract .xz file"
                    ;;
                *)
                    handle_failure "Unsupported file extension: $file_ext"
                    ;;
            esac

            rm "$clang_dir_name/$file_name" || \
                handle_failure "Failed to remove downloaded archive"
        fi
    else
        color_echo $CYAN "Clang directory $clang_dir_name already exists. Skipping download..."
    fi

    export PATH="$(pwd)/$clang_dir_name/bin:$PATH"
}

# Function to clean up unnecessary files and directories
cleanup() {
    color_echo $CYAN "Cleaning up unnecessary files and directories..."
    rm -rf aosp* AnyKer* error* out xrage* kernel_bui* proton* weeb* neutron* xrage* eva* *.zip changelogs.txt zyc*
}

# Function to regenerate defconfig if specified
regenerate_defconfig() {
    local defconfig_option="$1"

    if [ ! -z "$defconfig_option" ]; then
        color_echo $CYAN "Regenerating defconfig..."
        if ! make O=out ARCH=arm64 $defconfig_option savedefconfig && \
           cp out/defconfig arch/arm64/configs/vendor/${defconfig_option#*/}; then
            handle_failure "Failed to regenerate defconfig."
        fi
    fi
}

# Function to build the kernel with selected options
build_kernel() {
    local defconfig="vendor/RMX1911_defconfig"  # Default defconfig location

    color_echo $CYAN "Building the kernel with defconfig: $defconfig..."
    make clean
    make mrproper
    local build_options=$1

    if [ "$build_options" == "lto" ]; then
        COMPRESSION_TYPE="LTO+PGO+LLVM"
        color_echo $CYAN "Building with Full LTO & PGO & POLLY..."
        if ! make -j$(nproc) O=out ARCH=arm64 "$defconfig" \
            CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            CLANG_LD_PATH="$CLANG_DIR/lib" LLVM=1 \
            LLVM_POLLY=1 \
            HOSTCFLAGS="-O3 -fprofile-generate -flto" \
            HOSTLDFLAGS="-O3 -fprofile-generate -flto" \
            LOCALVERSION="-realme_trinket" \
            Image.gz dtb.img dtbo.img 2>&1 | tee error.log; then
            handle_failure "Build failed. Skipping packaging."
        fi
    elif [ "$build_options" == "llvm-polly" ]; then
        COMPRESSION_TYPE="LLVM-POLLY"
        color_echo $CYAN "Building with LLVM Polly optimization..."
        if ! make -j$(nproc) O=out ARCH=arm64 "$defconfig" \
            CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            CLANG_LD_PATH="$CLANG_DIR/lib" LLVM=1 \
            LLVM_POLLY=1 \
            HOSTCFLAGS="-O3" \
            HOSTLDFLAGS="-O3" \
            LOCALVERSION="-realme_trinket" \
            Image.gz dtb.img dtbo.img 2>&1 | tee error.log; then
            handle_failure "Build failed. Skipping packaging."
        fi
    elif [ "$build_options" == "polly-clang" ]; then
        COMPRESSION_TYPE="POLLY_CLANG"
        color_echo $CYAN "Building with LLVM Polly Clang optimization..."
        if ! make -j$(nproc) O=out ARCH=arm64 "$defconfig" \
            CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            CLANG_LD_PATH="$CLANG_DIR/lib" LLVM=1 \
            POLLY_CLANG=1 \
            HOSTCFLAGS="-O3" \
            HOSTLDFLAGS="-O3" \
            LOCALVERSION="-realme_trinket" \
            Image.gz dtb.img dtbo.img 2>&1 | tee error.log; then
            handle_failure "Build failed. Skipping packaging."
        fi
    else
        COMPRESSION_TYPE="LLVM"
        color_echo $CYAN "Building with default LLVM compression options..."
        if ! make -j$(nproc) O=out ARCH=arm64 "$defconfig" \
            CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
            CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
            CLANG_LD_PATH="$CLANG_DIR/lib" LLVM=1 \
            HOSTCFLAGS="-O3" \
            HOSTLDFLAGS="-O3" \
            LOCALVERSION="-realme_trinket" \
            Image.gz dtb.img dtbo.img 2>&1 | tee error.log; then
            handle_failure "Build failed. Skipping packaging."
        fi
    fi

    color_echo $GREEN "Kernel build completed successfully."
}

# Function to retrieve git commit changelogs and append to changelogs.txt
retrieve_changelogs() {
    color_echo $CYAN "Retrieving git commit changelogs..."
    git log --pretty=format:"%h - %s (%an)" > temp_changelogs.txt || \
        handle_failure "Failed to retrieve git commit changelogs."

    # Append changelogs to changelogs.txt
    cat temp_changelogs.txt >> changelogs.txt || \
        handle_failure "Failed to append changelogs to changelogs.txt."

    rm temp_changelogs.txt || \
        handle_failure "Failed to remove temporary changelogs file."
}

# Function to package the kernel
package_kernel() {
    local TIMESTAMP="$(date +"%Y%m%d-%H%M")"
    local BRANCH="$(get_branch_name)"  # Get current branch name
    local ZIP_NAME="Liliya-Nethunter-realme_trinket-${BRANCH}-${TIMESTAMP}.zip"  # Update ZIP file name with branch name and timestamp
    color_echo $CYAN "Packaging the kernel..."
    if [ ! -d "AnyKernel3" ]; then
        git clone https://github.com/zxrovx/AnyKernel3.git -b main AnyKernel3 || \
            handle_failure "Failed to clone AnyKernel3 repository"
    fi

    cp "out/arch/arm64/boot/Image.gz" "AnyKernel3" || \
        handle_failure "Failed to copy kernel image"
    cp "out/arch/arm64/boot/dtbo.img" "AnyKernel3" || \
        handle_failure "Failed to copy dtbo image"
    cp "out/arch/arm64/boot/dtb.img" "AnyKernel3" || \
        handle_failure "Failed to copy dtb image"

    # Copy changelogs.txt to AnyKernel3 directory
    cp "changelogs.txt" "AnyKernel3" || \
        handle_failure "Failed to copy changelogs.txt"

    cd AnyKernel3 || handle_failure "Failed to change directory to AnyKernel3"

    # Substitute placeholders in anykernel.sh with actual values
    sed -i "s|@HOSTNAME@|$(hostname)|g; s|@LOCALNAME@|$(hostname)|g; s|@ZIP_NAME@|$ZIP_NAME|g; s|@BANNER_TEXT@|$BANNER_TEXT|g" anykernel.sh

    # Zip the contents of AnyKernel3 directory
    zip -r9 "$ZIP_NAME" * -x .git README.md || handle_failure "Failed to create zip file"

    color_echo $GREEN "Kernel packaged successfully."

    # Get the size of the zip file
    local ZIP_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
}


# Function to upload the kernel and get download link
upload_kernel() {
    color_echo $CYAN "Uploading the kernel..."
    curl --progress-bar --upload-file "$ZIP_NAME" "https://oshi.at/$ZIP_NAME"
    color_echo $GREEN "Kernel uploaded successfully."

    # Back To Default Directory
    cd ..
}

# Function to get build time
get_build_time() {
    color_echo $CYAN "Getting build time..."
    local BUILD_TIME=$(date -d "@$SECONDS" -u +%T)
    echo "Build Time: $BUILD_TIME" >> "$LOG_FILE"
}

# Function to display kernel information
display_kernel_info() {
    # Get kernel version from Makefile in the current directory
    local VERSION=$(awk -F'[ =]' '/^VERSION/{print $NF}' Makefile)
    local PATCHLEVEL=$(awk -F'[ =]' '/^PATCHLEVEL/{print $NF}' Makefile)
    local SUBLEVEL=$(awk -F'[ =]' '/^SUBLEVEL/{print $NF}' Makefile)
    local KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

    # Clear terminal screen
    # clear

    color_echo $GREEN "Kernel Information:"
    color_echo $GREEN "  - Kernel Name: $ZIP_NAME"
    color_echo $GREEN "  - Kernel Version: $KERNEL_VERSION"
    color_echo $GREEN "  - Kernel Size: $ZIP_SIZE"
    color_echo $GREEN "  - Date Built: $(date +'%d/%m/%Y')"
    color_echo $GREEN "  - Compression Type: $COMPRESSION_TYPE"
    color_echo $GREEN "  - Compiled with Clang: "$clang_option""
    color_echo $GREEN "  - Changelogs: Attached in the zip file"
    color_echo $GREEN "  - Build Time: $(date -d "@$SECONDS" -u +%T)"
}

# Function to display usage instructions
usage() {
    color_echo $RED "Usage: $0 <clang_option> [<build_option>] [<defconfig_location>]"
    color_echo $YELLOW "Available Clang Options: weebx, neutron, proton, xragetc, eva, aosp, zyc"
    color_echo $YELLOW "Available Build Options: lto, polly. If Not Provided, The Script Will Use The Default Options."
    color_echo $YELLOW "Defconfig Location Is Optional. If Not Provided, The Script Will Use The Default Defconfig."
    color_echo $YELLOW "Use --regen Option To Regenerate The Defconfig If Needed."
    exit 1
}

# Function to select and setup Clang
select_and_setup_clang() {
    local clang_option="$1"

    case "$clang_option" in
        weebx)
            setup_clang "https://github.com/XSans0/WeebX-Clang/releases/download/WeebX-Clang-19.1.0-rc4-release/WeebX-Clang-19.1.0-rc4.tar.gz" "weebx-clang"
            CLANG_DIR="$(pwd)/weebx-clang"
            ;;
        neutron)
            setup_clang "https://gitlab.com/z3zens/neutron-clang.git" "neutron-clang"
            CLANG_DIR="$(pwd)/neutron-clang"
            ;;
        proton)
            setup_clang "https://github.com/kdrag0n/proton-clang.git" "proton-clang"
            CLANG_DIR="$(pwd)/proton-clang"
            ;;
        xragetc)
            setup_clang "https://github.com/xyz-prjkt/xRageTC-clang.git" "xragetc-clang"
            CLANG_DIR="$(pwd)/xragetc-clang"
            ;;
        eva)
            setup_clang "https://github.com/mvaisakh/gcc-build/releases/download/30082024/eva-gcc-arm64-30082024.xz" "eva-gcc"
            CLANG_DIR="$(pwd)/eva-gcc"
            ;;
        aosp)
            setup_clang "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86.git" "aosp-clang"
            CLANG_DIR="$(pwd)/aosp-clang"
            ;;
        zyc)
            setup_clang "https://github.com/ZyCromerZ/Clang/releases/download/20.0.0git-20240913-release/Clang-20.0.0git-20240913.tar.gz" "zyc-clang"
            CLANG_DIR="$(pwd)/zyc-clang"
            ;;
        *)
            color_echo $RED "Invalid option for clang selection. Please choose 'weebx', 'neutron', 'proton', 'xragetc', 'eva' , 'aosp' , or 'zyc'."
            usage
            ;;
    esac
}

# Main function
main() {
    color_echo $CYAN "$BANNER_TEXT"
    color_echo $GREEN "Kernel Build Script Version: $SCRIPT_VERSION"
    color_echo $GREEN "Build For Device: $KERNEL_DEVICES"

    # Check if valid arguments are provided
    if [ $# -lt 1 ]; then
        usage
    fi

    # Create log file
    > "$LOG_FILE" || handle_failure "Failed to create log file $LOG_FILE"

    # Cleanup First
    cleanup

    # Install required packages
    manage_dependencies

    # Initialize and update submodules
    initialize_submodules

    # Set timezone
    export TZ="Asia/Jakarta"

    # Select and setup Clang
    select_and_setup_clang "$1" || exit 1

    # Check for --regen option
    if [ "$2" == "--regen" ]; then
        # Regenerate defconfig
        regenerate_defconfig "$3"
        shift 3  # Shift arguments to the left to ignore --regen and its argument
    fi

    # Build the kernel with optional defconfig location
    if [ ! -z "$2" ]; then
        build_kernel "$2" "$3" || exit 1
    else
        build_kernel "$2" || exit 1
    fi

    # Retrieve git commit changelogs and append to changelogs.txt
    retrieve_changelogs

    # Package the kernel
    package_kernel || exit 1

    # Upload the kernel
    upload_kernel || exit 1

    # Get build time
    get_build_time

    # Display kernel information
    display_kernel_info

    # Cleanup Work result
    cleanup
}

# Call main function with command line arguments
main "$@"

