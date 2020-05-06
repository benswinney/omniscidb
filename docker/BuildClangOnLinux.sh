#!/bin/bash

set -e

# common variables
SCRIPT_DIR=$(cd "$(dirname "$BASH_SOURCE")" ; pwd)
TOP_DIR=$(cd "$SCRIPT_DIR/../../../.." ; pwd)

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
reset=$(tput sgr0)

# script variables
HOST_ARCH=$(uname -m)

if   [[ "$HOST_ARCH" == "x86_64" ]]; then
    export TARGET_TRIPLE=x86_64-unknown-linux-gnu
elif [[ "$HOST_ARCH" == "ppc64le" ]]; then
    export TARGET_TRIPLE=powerpc64le-unknown-linux-gnu
elif [[ "$HOST_ARCH" == "aarch64" ]]; then
    export TARGET_TRIPLE=aarch64-unknown-linux-gnu
else
    echo "${red}Error: Unsupported host platform architecture: $HOST_ARCH${reset}"
    exit 1
fi

##### script functions #####

###################################################
# Check if a package is installed.
# Globals:
#   None.
# Arguments:
#   package
# Returns:
#   0 if installed, 1 if it needs to be installed.
###################################################
function PackageIsInstalled() {
    PackageName=$1

    dpkg-query -W -f='${Status}\n' $PackageName | head -n 1 | awk '{print $3;}' | grep -q '^installed$'
}

###################################################
# Install a list of packages.
# Globals:
#   None.
# Arguments:
#   array list of package names
# Returns:
#   None.
###################################################
function InstallPackages() {

  if [ -e /etc/os-release ]; then
    source /etc/os-release
    # Ubuntu/Debian/Mint
    if [[ "$ID" == "ubuntu" ]] || [[ "$ID_LIKE" == "ubuntu" ]] || [[ "$ID" == "debian" ]] || [[ "$ID_LIKE" == "debian" ]] || [[ "$ID" == "tanglu" ]] || [[ "$ID_LIKE" == "tanglu" ]]; then

      DEPS=$1

      for DEP in $DEPS; do
        if ! PackageIsInstalled $DEP; then
          echo "Attempting installation of missing package: $DEP"
          set -x
          apt-get update && apt-get install -y $DEP
          set +x
        fi
      done
    fi
  fi
}

###################################################
# Build LLVM toolchain from sources
# Globals:
#   None.
# Arguments:
#   LLVM_VERSION
#   LLVM_PROJECTS
#   LLVM_TARGET_TRIPLE
#   INSTALL_PREFIX
#   BUILD_TYPE
# Returns:
#   None.
###################################################
function BuildLLVMToolchain() {

  # args
  LLVM_VERSION=$1
  LLVM_PROJECTS=$2
  LLVM_TARGET_TRIPLE=$3
  CMAKE_INSTALL_PREFIX=${4:-"/usr/local"}
  CMAKE_BUILD_TYPE=${5:-"Release"}

  # variables
  GIT_PROJECT="llvm-project"
  GIT_REPO="https://github.com/llvm/$GIT_PROJECT.git"
  GIT_BRANCH=release/`echo $LLVM_VERSION | cut -d. -f1`.x
  GIT_TAG="llvmorg-$LLVM_VERSION"
  REPO_DIR="/tmp/llvm"
  LOCAL_REPO="$REPO_DIR/$GIT_PROJECT"

  # create repo dir
  if [ ! -d $REPO_DIR ]; then
    mkdir -p $REPO_DIR; cd $REPO_DIR
  fi

  # clone sources
  if [ ! -d $LOCAL_REPO ]; then
    echo "${yellow}Cloning llvm-$LLVM_VERSION toolchain sources to $LOCAL_REPO${reset}"
    git clone --single-branch --depth=1 --branch=$GIT_BRANCH $GIT_REPO $LOCAL_REPO
  fi

  # create build dir
  if [ ! -d $LOCAL_REPO/build ]; then
    mkdir -p $LOCAL_REPO/build;
  fi

  # patch sources
  if [[ "$LLVM_VERSION" == "8.0.1" ]] && [[ "$HOST_ARCH" == "ppc64le" ]]; then
    cd $LOCAL_REPO
    git reset --hard
    git apply $SCRIPT_DIR/patches/llvm/$LLVM_VERSION/001-libcxx-bug-39696-llvm-8.0.1-ppc64le.patch
  fi

  # configure
  cd $LOCAL_REPO/build
  cmake \
  -DCMAKE_INSTALL_PREFIX=$CMAKE_INSTALL_PREFIX \
  -DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
  -DBUILD_SHARED_LIBS=ON \
  -DLLVM_BUILD_BENCHMARKS=OFF \
  -DLLVM_BUILD_DOCS=OFF \
  -DLLVM_BUILD_EXAMPLES=OFF \
  -DLLVM_BUILD_TESTS=OFF \
  -DLLVM_ENABLE_PROJECTS=$LLVM_PROJECTS \
  -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TARGET_TRIPLE \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=OFF \
  ../llvm

  # build
  make -j`nproc`  # use all available threads

  # install
  echo "${yellow}instaling llvm-$LLVM_VERSION toolchain to $CMAKE_INSTALL_PREFIX${reset}"
  make -j`nproc` install
}

##### main script entrypoint #####

# main entrypoint function
function main {

  # variables
  LLVM_VERSION='8.0.1'
  LLVM_PROJECTS="clang;clang-tools-extra;libcxx;libcxxabi;lld;lldb;libunwind;polly"
  LLVM_TARGET_TRIPLE="$TARGET_TRIPLE"
  TOOLCHAIN_VERSION="v14_clang-$LLVM_VERSION-centos7"

  BUILD_TYPE="Release"

  if   [[ "$HOST_ARCH" == "x86_64" ]]; then
    INSTALL_PREFIX="$TOP_DIR/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64/$TOOLCHAIN_VERSION/$LLVM_TARGET_TRIPLE"
  elif [[ "$HOST_ARCH" == "ppc64le" ]] || [[ "$HOST_ARCH" == "aarch64" ]]; then
    INSTALL_PREFIX="$TOP_DIR/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_$HOST_ARCH/$TOOLCHAIN_VERSION/$LLVM_TARGET_TRIPLE"
  fi

  if [ -d $INSTALL_PREFIX ]; then
    echo "Toolchain already installed skipping."
    exit 0
  fi

  # install required packages
  DEPS="
    build-essential
    cmake
    libedit-dev
    libncurses-dev
    libxml2-dev
    python-dev
    python3-dev
    swig
    "
  InstallPackages "${DEPS[@]}"

  # build toolchain
  BuildLLVMToolchain \
    $LLVM_VERSION \
    $LLVM_PROJECTS \
    $LLVM_TARGET_TRIPLE \
    $INSTALL_PREFIX \
    $BUILD_TYPE \

  exit 0
}

# run main entrypoint
main
