FROM docker.io/debian:12 AS build

RUN apt-get update && apt-get install -y git build-essential git-lfs cmake autoconf automake libtool libzip-dev python3 curl libcurl4-openssl-dev pkg-config libssl-dev libfontconfig-dev duktape-dev libicu-dev libsdl2-dev libspeex-dev libspeexdsp-dev ccache

RUN rm /bin/sh && ln -s /bin/bash /bin/sh

WORKDIR /app

RUN mkdir -p /app/vendored

COPY vendored/emsdk /app/vendored/emsdk
COPY patches /app/patches

ENV PRE="source /app/vendored/emsdk/emsdk_env.sh"

# Install/update emsdk
RUN cd /app/vendored/emsdk && \
  ./emsdk install latest && \
  ./emsdk activate latest && \
  echo 'export MAKEFLAGS="-j$(nproc)"' >> /app/vendored/emsdk/emsdk_env.sh

RUN mkdir -p /app/build && \
  mkdir -p /app/assets

COPY vendored/openssl /app/vendored/openssl

RUN cd /app/vendored/openssl && \
  $PRE && \
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
    linux-generic32 && \
  sed -i='' -e 's/^CC=.*/CC=\$\(CROSS_COMPILE\)cc/' Makefile && \
  sed -i='' -e 's/^CXX=.*/CXX=\$\(CROSS_COMPILE\)\+\+/' Makefile && \
  sed -i='' -e 's/^AR=.*/AR=\$\(CROSS_COMPILE\)ar/' Makefile && \
  sed -i='' -e 's/^RANLIB=.*/RANLIB=\$\(CROSS_COMPILE\)ranlib/' Makefile && \
  sed -i='' -e 's/^CFLAGS=-O3 \(.*\)/CFLAGS=\1/' Makefile && \
  emmake make build_libs

COPY vendored/zlib /app/vendored/zlib

RUN cd /app/vendored/zlib && \
  $PRE && \
  emcmake cmake /app/vendored/zlib && \
  sh -c 'emmake make zlib || emmake make zlib' && \
  sh -c 'emmake make install || emmake make install'

COPY vendored/zip /app/vendored/zip

RUN mkdir -p /app/vendored/zip/build && \
  $PRE && \
  cd /app/vendored/zip/build && \
  emcmake cmake /app/vendored/zip \
    -DZLIB_INCLUDE_DIR="/app/vendored/zlib" \
    -DZLIB_LIBRARY="/app/vendored/zlib/libz.a" && \
  emmake make zip && \
  emmake make install

RUN cd /app/vendored && \
  $PRE && \
  rm -rf /app/vendored/duktape && \
  curl -O https://duktape.org/duktape-2.6.0.tar.xz && \
  tar -xvf duktape*tar* && \
  rm -f duktape*tar* && \
  mv duktape-* duktape && \
  cd /app/vendored/duktape && \
  sed -i='' -e "s/Darwin/Foobar/" Makefile.sharedlibrary && \
  sed -i='' -e "s|^CC =.*|CC=/app/vendored/emsdk/upstream/emscripten/emcc|" Makefile.sharedlibrary && \
  emmake make -f Makefile.sharedlibrary && \
  ln -s libduktape.so* libduktape.so && \
  ln -s libduktaped.so* libduktaped.so

COPY vendored/icu /app/vendored/icu

RUN cd /app/vendored/icu/icu4c/source && \
  $PRE && \
  ac_cv_namespace_ok=yes icu_cv_host_frag=mh-linux emmake ./configure \
    --enable-release \
    --enable-shared \
    --disable-icu-config \
    --disable-extras \
    --disable-icuio \
    --disable-layoutex \
    --disable-tools \
    --disable-tests \
    --disable-samples && \
  emmake make

COPY vendored/speexdsp /app/vendored/speexdsp

RUN cd /app/vendored/speexdsp && \
  $PRE && \
  emmake ./autogen.sh && \
  emmake ./configure --enable-shared --disable-neon && \
  emmake make

COPY vendored/OpenRCT2 /app/vendored/OpenRCT2

RUN $PRE && \
  cd /app/assets && \
  cmake /app/vendored/OpenRCT2 -DMACOS_BUNDLE=off -DDISABLE_NETWORK=on -DDISABLE_GUI=off && \
  make openrct2-cli VERBOSE=1 && \
  make g2 && \
  DESTDIR=. make install && \
  cp -v g2.dat openrct2-cli /app/build && \
  cp -vr usr/local/share/openrct2/object usr/local/share/openrct2/sequence .

ENV EMSCRIPTEN_ROOT /app/vendored/emsdk/upstream/emscripten
RUN cd /app/build && \
  $PRE && \
  emcmake env \
      PKG_CONFIG_PATH="$EMSCRIPTEN_ROOT/cache/sysroot/local/lib/pkgconfig:$EMSCRIPTEN_ROOT/cache/sysroot/lib/pkgconfig:$EMSCRIPTEN_ROOT/cache/sysroot/share/pkgconfig" \
    cmake /app/vendored/OpenRCT2 \
    -DOPENSSL_INCLUDE_DIR="/app/vendored/openssl/include" \
    -DOPENSSL_SSL_LIBRARY="/app/vendored/openssl/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="/app/vendored/openssl/libcrypto.a" \
    -Dduktape_DIR="/app/vendored/OpenRCT2/cmake" \
    -DDUKTAPE_INCLUDE_DIR="/app/vendored/duktape/src" \
    -DDUKTAPE_LIBRARY="/app/vendored/duktape/libducktape.so" \
    -DICU_INCLUDE_DIR="/app/vendored/icu/icu4c/source/common" \
    -DICU_LIBRARY="/app/vendored/icu/icu4c/source/lib/libicuuc.so" \
    -DLIBZIP_LIBRARIES="/app/vendored/zip/build/lib/libzip.a" \
    -DICU_DT_LIBRARY_RELEASE="/app/vendored/icu/icu4c/source/stubdata/libicudata.so" \
    -DICU_UC_LIBRARY_RELEASE="/app/vendored/icu/icu4c/source/lib/libicuuc.so" \
    -DSPEEXDSP_INCLUDE_DIR="/app/vendored/speexdsp/include" \
    -DSPEEXDSP_LIBRARY="/app/vendored/speexdsp/libspeexdsp/.libs/libspeexdsp.a" \
    -DDISABLE_HTTP:BOOL=FALSE \
    -DDISABLE_TTF:BOOL=TRUE \
    -DENABLE_SCRIPTING:BOOL=FALSE \
    -DENABLE_SCRIPTING:BOOL=FALSE \
    -DDISABLE_VORBIS:BOOL=TRUE \
    -DDISABLE_FLAC:BOOL=TRUE \
    -DCMAKE_SYSTEM_NAME=Emscripten && \
  DESTDIR=. emmake make install VERBOSE=1 || DESTDIR=. MAKEFLAGS= emmake make install VERBOSE=1

WORKDIR /app/www

COPY tools /app/tools

RUN mkdir -p /app/www/{user,rct2}-data-path && \
  $PRE && \
  cp /app/build/openrct2.* /app/www/ && \
  sed -i='' -e 's/throw "getpwuid: TODO"/return 0/' "/app/www/openrct2.js" && \
  cp -vR /app/assets/{g2.dat,object,sequence} \
    /app/vendored/OpenRCT2/data/language \
    /app/www/rct2-data-path && \
  /app/tools/gestalt.py -i /app/tools/gestalt.py -i ./rct2-data-path -o .

FROM docker.io/nginxinc/nginx-unprivileged

COPY --from=build /app/www/ /usr/share/nginx/html/
RUN sed -i 's/ index /add_header Cross-Origin-Opener-Policy same-origin; index /' \
    /etc/nginx/conf.d/default.conf && \
  sed -i 's/ index /add_header Cross-Origin-Embedder-Policy require-corp; index /' \
  /etc/nginx/conf.d/default.conf

COPY resources/config.ini /usr/share/nginx/html/user-data-path/
COPY resources/index.html /usr/share/nginx/html/
