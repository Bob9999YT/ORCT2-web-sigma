#!/bin/bash
set -ex

PWD=$(pwd)
PATCHES_ROOT="$PWD/patches"
VENDOR_ROOT="$PWD/vendored"
RESOURCE_ROOT="$PWD/resources"
TOOLS_ROOT="$PWD/tools"
EMSDK_ROOT="$VENDOR_ROOT/emsdk"
OPENRCT_SRCROOT="$PWD/vendored/OpenRCT2"
OPENRCT_BUILDROOT="$PWD/build"
OPENRCT_ASSET_BUILDROOT="$PWD/assets"
OPENRCT_INSTALL_DEST_DIR="$PWD/www"
OPENSSL_ROOT="$VENDOR_ROOT/openssl"
DUKTAPE_ROOT="$VENDOR_ROOT/duktape"
ICU_ROOT="$VENDOR_ROOT/icu/icu4c/source"
SPEEXDSP_ROOT="$VENDOR_ROOT/speexdsp"
JSON_ROOT="$VENDOR_ROOT/json"
ZLIB_ROOT="$VENDOR_ROOT/zlib"
ZIP_ROOT="$VENDOR_ROOT/zip"
ZIP_BUILDROOT="$ZIP_ROOT/build"

export MAKEFLAGS="-j$(nproc)"

DUKTAPE_DIST="https://duktape.org/duktape-2.6.0.tar.xz"

prepare() {
  # Make sure submodules are up to date
  git -C $PWD submodule update -i --recursive

  # Link nlohmann_json
  rm -rf "$OPENRCT_SRCROOT/src/thirdparty/nlohmann"
  ln -s "$JSON_ROOT/include/nlohmann" "$OPENRCT_SRCROOT/src/thirdparty/nlohmann"

  # Link FindSpeexDSP.cmake
  rm -f "$OPENRCT_SRCROOT/cmake/FindSpeexDSP.cmake"
  ln -s "$PATCHES_ROOT/FindSpeexDSP.cmake" "$OPENRCT_SRCROOT/cmake/FindSpeexDSP.cmake"

  # Install/update emsdk
  pushd $EMSDK_ROOT
  ./emsdk install latest
  ./emsdk activate latest
  source ./emsdk_env.sh
  popd

  # Unfortunately we can't just cherry-pick this one...
  pushd "$EMSDK_ROOT/upstream/emscripten"
  if ! patch --dry-run -p0 -Rfsi "$PATCHES_ROOT/emscripten.patch">/dev/null; then
    patch -p0 -i "$PATCHES_ROOT/emscripten.patch"
  fi
  popd

  # Create the build root for OpenRCT2
  if [ ! -d $OPENRCT_BUILDROOT ]; then
    mkdir -p $OPENRCT_BUILDROOT
  fi

  if [ ! -d $OPENRCT_ASSET_BUILDROOT ]; then
    mkdir -p $OPENRCT_ASSET_BUILDROOT
  fi
}

build_openssl() {
  pushd $OPENSSL_ROOT
  emmake ./Configure \
    -no-asm \
    -no-ssl2 \
    -no-ssl3 \
    -no-comp \
    -no-hw \
    -no-engine \
    -no-deprecated \
    -no-dso \
    -no-tests \
    -shared \
    --openssldir=built \
    linux-generic32

  # Patch Makefile
  sed -i='' -e 's/^CC=.*/CC=\$\(CROSS_COMPILE\)cc/' Makefile
  sed -i='' -e 's/^CXX=.*/CXX=\$\(CROSS_COMPILE\)\+\+/' Makefile
  sed -i='' -e 's/^AR=.*/AR=\$\(CROSS_COMPILE\)ar/' Makefile
  sed -i='' -e 's/^RANLIB=.*/RANLIB=\$\(CROSS_COMPILE\)ranlib/' Makefile

  # Disable enscriptem optimizations for OpenSSL
  sed -i='' -e 's/^CFLAGS=-O3 \(.*\)/CFLAGS=\1/' Makefile

  # Build
  emmake make build_libs
  popd
}

build_zlib() {
  pushd $ZLIB_ROOT
  emcmake cmake $ZLIB_ROOT
  emmake make zlib || emmake make zlib
  emmake make install || emmake make install
  popd
}

build_zip() {
  pushd $ZIP_ROOT

  if [ ! -d $ZIP_BUILDROOT ]; then
    mkdir -p $ZIP_BUILDROOT
  fi

  cd $ZIP_BUILDROOT
  emcmake cmake $ZIP_ROOT \
    -DZLIB_INCLUDE_DIR="$ZLIB_ROOT" \
    -DZLIB_LIBRARY="$ZLIB_ROOT/libz.a"
  emmake make zip
  emmake make install

  popd
}

build_duktape() {
  pushd $VENDOR_ROOT

  # Download and unpack Duktape distributable
  rm -rf $DUKTAPE_ROOT
  curl -O $DUKTAPE_DIST
  tar -xvf duktape*tar*
  rm -f duktape*tar*
  mv duktape-* duktape

  popd
  pushd $DUKTAPE_ROOT

  # Patch Makefile
  sed -i='' -e "s/Darwin/Foobar/" Makefile.sharedlibrary
  sed -i='' -e "s|^CC =.*|CC=$EMSDK_ROOT/upstream/emscripten/emcc|" Makefile.sharedlibrary

  # Build
  emmake make -f Makefile.sharedlibrary
  ln -s libduktape.so* libduktape.so
  ln -s libduktaped.so* libduktaped.so
  popd
}

build_icu() {
  pushd $ICU_ROOT
  ac_cv_namespace_ok=yes icu_cv_host_frag=mh-linux emmake ./configure \
    --enable-release \
    --enable-shared \
    --disable-icu-config \
    --disable-extras \
    --disable-icuio \
    --disable-layoutex \
    --disable-tools \
    --disable-tests \
    --disable-samples

  emmake make
  popd
}

build_speexdsp() {
  pushd $SPEEXDSP_ROOT
  emmake ./autogen.sh
  emmake ./configure --enable-shared --disable-neon
  emmake make
  popd
}

build_openrct2_assets() {
  pushd $OPENRCT_ASSET_BUILDROOT
  cmake $OPENRCT_SRCROOT -DMACOS_BUNDLE=off -DDISABLE_NETWORK=on -DDISABLE_GUI=off
  make openrct2-cli VERBOSE=1
  make g2
  DESTDIR=. make install
  cp -v g2.dat "$OPENRCT_BUILDROOT"
  cp -v openrct2-cli "$OPENRCT_BUILDROOT"
  cp -vr usr/local/share/openrct2/object usr/local/share/openrct2/sequence .
  popd
}

build_openrct2() {
  pushd $OPENRCT_BUILDROOT
  emcmake env \
      PKG_CONFIG_LIBDIR="$EMSDK_ROOT/upstream/emscripten/cache/sysroot/local/lib/pkgconfig:$EMSDK_ROOT/upstream/emscripten/cache/sysroot/lib/pkgconfig:$EMSDK_ROOT/upstream/emscripten/cache/sysroot/share/pkgconfig" \
    cmake $OPENRCT_SRCROOT \
    -DOPENSSL_INCLUDE_DIR="$OPENSSL_ROOT/include" \
    -DOPENSSL_SSL_LIBRARY="$OPENSSL_ROOT/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_ROOT/libcrypto.a" \
    -Dduktape_DIR="$OPENRCT_SRCROOT/cmake" \
    -DDUKTAPE_INCLUDE_DIR="$DUKTAPE_ROOT/src" \
    -DDUKTAPE_LIBRARY="$DUKTAPE_ROOT/libducktape.so" \
    -DICU_INCLUDE_DIR="$ICU_ROOT/common" \
    -DICU_LIBRARY="$ICU_ROOT/lib/libicuuc.so" \
    -DLIBZIP_LIBRARIES="$ZIP_BUILDROOT/lib/libzip.a" \
    -DICU_DT_LIBRARY_RELEASE="$ICU_ROOT/stubdata/libicudata.so" \
    -DICU_UC_LIBRARY_RELEASE="$ICU_ROOT/lib/libicuuc.so" \
    -DSPEEXDSP_INCLUDE_DIR="$SPEEXDSP_ROOT/include" \
    -DSPEEXDSP_LIBRARY="$SPEEXDSP_ROOT/libspeexdsp/.libs/libspeexdsp.a" \
    -DDISABLE_HTTP:BOOL=FALSE \
    -DDISABLE_TTF:BOOL=TRUE \
    -DENABLE_SCRIPTING:BOOL=FALSE \
    -DCMAKE_SYSTEM_NAME=Emscripten

  DESTDIR=. emmake make install VERBOSE=1
  popd
}

master_resources() {
  if [ ! -d $OPENRCT_INSTALL_DEST_DIR ]; then
    mkdir -p $OPENRCT_INSTALL_DEST_DIR
    mkdir -p "$OPENRCT_INSTALL_DEST_DIR/user-data-path"
    mkdir -p "$OPENRCT_INSTALL_DEST_DIR/rct2-data-path"
  fi

  pushd $OPENRCT_INSTALL_DEST_DIR

  # Patch clownshoes code
  # https://github.com/emscripten-core/emscripten/issues/13219
  sed -i='' -e 's/throw "getpwuid: TODO"/return 0/' "$OPENRCT_BUILDROOT/openrct2.js"

  cp -v "$RESOURCE_ROOT/index.html" .
  cp -v "$OPENRCT_BUILDROOT/openrct2.js" .
  cp -v "$OPENRCT_BUILDROOT/openrct2.worker.js" .
  cp -v "$OPENRCT_BUILDROOT/openrct2.wasm" .
  cp -v "$OPENRCT_BUILDROOT/openrct2.wasm.map" . || true
  cp -v "$OPENRCT_BUILDROOT/g2.dat" .

  cp -v "$RESOURCE_ROOT/config.ini" "./user-data-path"

  cp -vR "$OPENRCT_ASSET_BUILDROOT/g2.dat" "./rct2-data-path"
  cp -vR "$OPENRCT_ASSET_BUILDROOT/object" "./rct2-data-path"
  cp -vR "$OPENRCT_ASSET_BUILDROOT/sequence" "./rct2-data-path"
  cp -vR "$OPENRCT_SRCROOT/data/language" "./rct2-data-path"

  # Scan ourseslves to discover assets
  $TOOLS_ROOT/gestalt.py -i ./rct2-data-path -o .

  popd
}

prepare
build_openssl
build_zlib
build_zip
build_duktape
build_icu
build_speexdsp
build_openrct2_assets
build_openrct2
master_resources
