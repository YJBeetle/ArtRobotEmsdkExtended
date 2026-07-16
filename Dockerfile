FROM emscripten/emsdk:6.0.2

SHELL ["/bin/bash", "-c"]

# Install build dependencies
RUN apt update &&\
    apt install -y pkg-config libtool &&\
    rm -rf /var/lib/apt/lists/*

# ENV
ENV BUILD_DIR=/i
ENV PREFIX_DIR=/emsdk/upstream/emscripten/cache/sysroot
# Cloudflare Workers do not expose shared WebAssembly memory or pthread workers.
ENV EMCC_CFLAGS="-sSHARED_MEMORY=0 -mno-atomics"

# opencv
ENV OPENCV_VERSION=5.0.0
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz -O opencv-${OPENCV_VERSION}.tar.gz &&\
    tar xvf opencv-${OPENCV_VERSION}.tar.gz &&\
    cd opencv-${OPENCV_VERSION} &&\
    emcmake python3 ./platforms/js/build_js.py --build_wasm --cmake_option="-DCMAKE_INSTALL_PREFIX=${PREFIX_DIR}" build &&\
    cmake --build build -j2 &&\
    cmake --install build &&\
    cd .. && rm -rf opencv-${OPENCV_VERSION}.tar.gz opencv-${OPENCV_VERSION}

# libjpeg
ENV JPEG_VERSION=3.2.0
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${JPEG_VERSION}/libjpeg-turbo-${JPEG_VERSION}.tar.gz &&\
    tar xvf libjpeg-turbo-${JPEG_VERSION}.tar.gz &&\
    cd libjpeg-turbo-${JPEG_VERSION} &&\
    emcmake cmake -B build -DCMAKE_INSTALL_PREFIX=${PREFIX_DIR} \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
        -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_SIMD=OFF &&\
    cmake --build build -j2 &&\
    cmake --install build &&\
    cd .. && rm -rf libjpeg-turbo-${JPEG_VERSION}.tar.gz libjpeg-turbo-${JPEG_VERSION}

# zlib
ENV ZLIB_VERSION=1.3.2
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.xz &&\
    tar xvf zlib-${ZLIB_VERSION}.tar.xz &&\
    cd zlib-${ZLIB_VERSION} &&\
    sed -i "s|add_library(zlib SHARED |add_library(zlib STATIC |g" CMakeLists.txt &&\
    sed -i "s|share/pkgconfig|lib/pkgconfig|g" CMakeLists.txt &&\
    emcmake cmake -B build -DCMAKE_INSTALL_PREFIX=${PREFIX_DIR} &&\
    cmake --build build &&\
    cmake --install build &&\
    cd .. && rm -rf zlib-${ZLIB_VERSION}.tar.xz zlib-${ZLIB_VERSION}

# libpng
# 需要 zlib
ENV PNG_VERSION=1.6.58
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://download.sourceforge.net/libpng/libpng-${PNG_VERSION}.tar.xz &&\
    tar xvf libpng-${PNG_VERSION}.tar.xz &&\
    cd libpng-${PNG_VERSION} &&\
    LDFLAGS="-L${PREFIX_DIR}/lib" emconfigure ./configure --host=wasm32-unknown-linux --prefix=${PREFIX_DIR} --enable-static --disable-shared --disable-dependency-tracking \
        --disable-tests --disable-tools &&\
    emmake make -j2 &&\
    emmake make install &&\
    cd .. && rm -rf libpng-${PNG_VERSION}.tar.xz libpng-${PNG_VERSION}

# WebP
ENV WEBP_VERSION=1.6.0
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz &&\
    tar xvf libwebp-${WEBP_VERSION}.tar.gz &&\
    cd libwebp-${WEBP_VERSION} &&\
    emconfigure ./configure --host=wasm32-unknown-linux --prefix=${PREFIX_DIR} --enable-static --disable-shared --disable-dependency-tracking \
        --disable-png --disable-libwebpdecoder --disable-libwebpdemux --disable-libwebpmux --disable-sdl &&\
    emmake make -j2 &&\
    emmake make install &&\
    cd .. && rm -rf libwebp-${WEBP_VERSION}.tar.gz libwebp-${WEBP_VERSION}

# freetype
# 需要 libpng zlib
ENV FREETYPE_VERSION=2.14.3
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://download.sourceforge.net/freetype/freetype-${FREETYPE_VERSION}.tar.xz &&\
    tar xvf freetype-${FREETYPE_VERSION}.tar.xz &&\
    cd freetype-${FREETYPE_VERSION} &&\
    emconfigure ./configure --host=wasm32-unknown-linux --prefix=${PREFIX_DIR} --enable-static --disable-shared --disable-dependency-tracking &&\
    gcc ./src/tools/apinames.c -o ./objs/apinames &&\
    emmake make -j2 &&\
    emmake make install &&\
    cd .. && rm -rf freetype-${FREETYPE_VERSION}.tar.xz freetype-${FREETYPE_VERSION}

# expat
ENV EXPAT_VERSION=2.8.2
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/libexpat/libexpat/releases/download/R_$(printf '%s' "${EXPAT_VERSION}" | tr . _)/expat-${EXPAT_VERSION}.tar.xz &&\
    tar xvf expat-${EXPAT_VERSION}.tar.xz &&\
    cd expat-${EXPAT_VERSION} &&\
    emmake ./buildconf.sh --force &&\
    emconfigure ./configure --host=wasm32-unknown-linux --prefix=${PREFIX_DIR} --enable-static --disable-shared --disable-dependency-tracking \
        --without-xmlwf --without-docbook --without-examples --without-tests \
        --without-arc4random --without-arc4random-buf --without-getrandom --without-sys-getrandom &&\
    emmake make -j2 &&\
    emmake make install &&\
    cd .. && rm -rf expat-${EXPAT_VERSION}.tar.xz expat-${EXPAT_VERSION}

# meson
RUN apt update &&\
    apt install -y python3 ninja-build &&\
    rm -rf /var/lib/apt/lists/* &&\
    python3 -m pip install --break-system-packages meson
ADD emscripten.txt ${BUILD_DIR}/emscripten.txt

# gperf
RUN apt update &&\
    apt install -y gperf &&\
    rm -rf /var/lib/apt/lists/*

# fontconfig
# 需要 freetype expat gperf
ENV FONTCONFIG_VERSION=2.18.2
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/${FONTCONFIG_VERSION}/fontconfig-${FONTCONFIG_VERSION}.tar.gz &&\
    tar xvf fontconfig-${FONTCONFIG_VERSION}.tar.gz &&\
    cd fontconfig-${FONTCONFIG_VERSION} &&\
    sed -i "s|error('FIXME: implement cc.preprocess')|cpp += \['-E', '-P'\]|g" src/meson.build &&\
    # Fontconfig 2.18.2 未在 Meson 的线程探测中排除 Emscripten；单线程构建不应注入 -pthread。
    sed -i "s/host_machine.system() != 'windows'/host_machine.system() != 'windows' and host_machine.system() != 'emscripten'/" meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dtests=disabled -Ddoc=disabled -Dtools=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf fontconfig-${FONTCONFIG_VERSION}.tar.gz fontconfig-${FONTCONFIG_VERSION}

# pixman
# 需要 zlib
ENV PIXMAN_VERSION=0.46.4
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://www.cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz &&\
    tar xvf pixman-${PIXMAN_VERSION}.tar.gz &&\
    cd pixman-${PIXMAN_VERSION} &&\
    # Pixman 0.46.4 会为可用的 pthread 自动设置 HAVE_PTHREADS 并传播 -pthread；此镜像仅构建单线程 WASM。
    sed -i "s/dep_threads = dependency('threads')/dep_threads = null_dep/" meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dtests=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf pixman-${PIXMAN_VERSION}.tar.gz pixman-${PIXMAN_VERSION}

# libffi
ENV IFFI_VERSION=3.7.1
# Emscripten wasm32 support is included in current libffi releases.
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/libffi/libffi/releases/download/v${IFFI_VERSION}/libffi-${IFFI_VERSION}.tar.gz &&\
    tar xvf libffi-${IFFI_VERSION}.tar.gz &&\
    cd libffi-${IFFI_VERSION} &&\
    sed -i 's/ -fexceptions//g' configure &&\
    emconfigure ./configure --host=wasm32-unknown-linux --prefix=${PREFIX_DIR} --enable-static --disable-shared --disable-dependency-tracking \
        --disable-builddir --disable-multi-os-directory --disable-raw-api --disable-structs --disable-docs &&\
    emmake make -j2 &&\
    emmake make install &&\
    cd .. && rm -rf libffi-${IFFI_VERSION}.tar.gz libffi-${IFFI_VERSION}

# gettext
RUN apt update &&\
    apt install -y gettext &&\
    rm -rf /var/lib/apt/lists/*

# pcre2
ENV PCRE2_VERSION=10.47
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.bz2 &&\
    tar xvf pcre2-${PCRE2_VERSION}.tar.bz2 &&\
    cd pcre2-${PCRE2_VERSION} &&\
    emcmake cmake -B build -DCMAKE_INSTALL_PREFIX=${PREFIX_DIR} -DBUILD_SHARED_LIBS=OFF \
        -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF \
        -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_JIT=OFF &&\
    cmake --build build -j2 &&\
    cmake --install build &&\
    cd .. && rm -rf pcre2-${PCRE2_VERSION}.tar.bz2 pcre2-${PCRE2_VERSION}

# glib
# 需要 libffi pcre2
ENV GLIB_VERSION=2.89.1
# See https://github.com/kleisauke/wasm-vips/blob/master/build.sh
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://download.gnome.org/sources/glib/${GLIB_VERSION%.*}/glib-${GLIB_VERSION}.tar.xz &&\
    tar xvf glib-${GLIB_VERSION}.tar.xz &&\
    cd glib-${GLIB_VERSION} &&\
    curl -Ls https://github.com/GNOME/glib/compare/${GLIB_VERSION}...kleisauke:wasm-vips-${GLIB_VERSION}.patch | patch -p1 &&\
    # GLib 没有关闭线程的 Meson 选项；保留 POSIX API，但单线程 WASM 不传播 -pthread。
    sed -i "s/thread_dep = dependency('threads')/thread_dep = []/" meson.build &&\
    # wasm-vips 补丁移除了 GRegex；librsvg 仍通过 GLib 公开 API 使用它，因此恢复 PCRE2 后端。
    sed -i "/#include <glib\/grefstring.h>/a #include <glib/gregex.h>" glib/glib.h &&\
    sed -i "/'grefstring.h',/a\  'gregex.h'," glib/meson.build &&\
    sed -i "/'grefstring.c',/a\  'gregex.c'," glib/meson.build &&\
    sed -i "/# Import the gvdb sources/i pcre2 = dependency('libpcre2-8', version: '>=10.32')" meson.build &&\
    sed -i "/libsysprof_capture_dep,/a\    pcre2," glib/meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        --force-fallback-for=gvdb -Dintrospection=disabled -Dselinux=disabled -Dxattr=false -Dlibmount=disabled \
        -Dsysprof=disabled -Dnls=disabled -Dglib_debug=disabled -Dtests=false -Dglib_assert=false -Dglib_checks=false &&\
    meson install -C build --tag devel &&\
    ln -s ${PREFIX_DIR}/lib/pkgconfig/gio-2.0.pc ${PREFIX_DIR}/lib/pkgconfig/gio-unix-2.0.pc &&\
    cd .. && rm -rf glib-${GLIB_VERSION}.tar.xz glib-${GLIB_VERSION}

# cairo
# 需要 libpng pixman freetype zlib glib
# Keep Cairo single-threaded and skip native csi utilities that are not installed in the sysroot.
ENV CAIRO_VERSION=1.18.4
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://www.cairographics.org/releases/cairo-${CAIRO_VERSION}.tar.xz &&\
    tar xvf cairo-${CAIRO_VERSION}.tar.xz &&\
    cd cairo-${CAIRO_VERSION} &&\
    sed -i "/\['-D_REENTRANT'\], \['-lpthread'\]/d; /\['-pthread'\], \[\]/d" meson.build &&\
    sed -i "s/^if conf.get('CAIRO_HAS_INTERPRETER'.*/if false/; s/^if conf.get('CAIRO_HAS_TRACE'.*/if false/" util/meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dfontconfig=enabled -Dfreetype=enabled -Dpng=enabled -Dzlib=enabled -Dglib=enabled \
        -Ddwrite=disabled -Dquartz=disabled -Dxcb=disabled -Dxlib=disabled -Dxlib-xcb=disabled \
        -Dtests=disabled -Dlzo=disabled -Dspectre=disabled -Dsymbol-lookup=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf cairo-${CAIRO_VERSION}.tar.xz cairo-${CAIRO_VERSION}

# harfbuzz
ENV HARFBUZZ_VERSION=14.2.1
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz &&\
    tar xvf harfbuzz-${HARFBUZZ_VERSION}.tar.xz &&\
    cd harfbuzz-${HARFBUZZ_VERSION} &&\
    # HarfBuzz 会自动探测 pthread；Emscripten 单线程构建保留其默认空线程依赖。
    sed -i "s/host_machine.system() != 'windows'/host_machine.system() != 'windows' and host_machine.system() != 'emscripten'/" meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dglib=disabled -Dgobject=disabled -Dcairo=enabled -Dfreetype=enabled \
        -Draster=disabled -Dvector=disabled -Dgpu=disabled -Dutilities=disabled \
        -Ddocs=disabled -Dtests=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf harfbuzz-${HARFBUZZ_VERSION}.tar.xz harfbuzz-${HARFBUZZ_VERSION}

# fribidi
ENV FRIBIDI_VERSION=1.0.16
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://github.com/fribidi/fribidi/releases/download/v${FRIBIDI_VERSION}/fribidi-${FRIBIDI_VERSION}.tar.xz &&\
    tar xvf fribidi-${FRIBIDI_VERSION}.tar.xz &&\
    cd fribidi-${FRIBIDI_VERSION} &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dtests=false -Ddocs=false &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf fribidi-${FRIBIDI_VERSION}.tar.xz fribidi-${FRIBIDI_VERSION}

# libglib2.0-dev-bin
RUN apt update &&\
    apt install -y libglib2.0-dev-bin &&\
    rm -rf /var/lib/apt/lists/*

# Pango
# 需要 harfbuzz fribidi fontconfig freetype glib cairo libglib2.0-dev-bin
ENV PANGO_VERSION=1.58.0
# Remove pthread flags leaked by dependency metadata; all sysroot libraries are single-threaded.
# Pango has no Meson switches for disabling its native utility binaries.
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    sed -i 's/ -pthread//g' ${PREFIX_DIR}/lib/pkgconfig/*.pc &&\
    wget https://download.gnome.org/sources/pango/${PANGO_VERSION%.*}/pango-${PANGO_VERSION}.tar.xz &&\
    tar xvf pango-${PANGO_VERSION}.tar.xz &&\
    cd pango-${PANGO_VERSION} &&\
    sed -i "s|subdir('utils')||g" meson.build &&\
    sed -i "s|subdir('tools')||g" meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dintrospection=disabled -Dbuild-testsuite=false -Dbuild-examples=false &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf pango-${PANGO_VERSION}.tar.xz pango-${PANGO_VERSION}

# libxml2-utils
RUN apt update &&\
    apt install -y libxml2-utils &&\
    rm -rf /var/lib/apt/lists/*

# libxml2
ENV XML_VERSION=2.15.3
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://download.gnome.org/sources/libxml2/${XML_VERSION%.*}/libxml2-${XML_VERSION}.tar.xz &&\
    tar xvf libxml2-${XML_VERSION}.tar.xz &&\
    cd libxml2-${XML_VERSION} &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dthreads=disabled -Dtls=disabled -Dthread-alloc=disabled -Dmodules=disabled \
        -Dpython=disabled -Ddocs=disabled -Ddebugging=disabled -Dhistory=disabled -Dreadline=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf libxml2-${XML_VERSION}.tar.xz libxml2-${XML_VERSION}

# shared-mime-info
# 需要 gettext libxml2-utils
ENV SHARED_MIME_INFO_VERSION=2.5.1
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/${SHARED_MIME_INFO_VERSION}/shared-mime-info-${SHARED_MIME_INFO_VERSION}.tar.bz2 &&\
    tar xvf shared-mime-info-${SHARED_MIME_INFO_VERSION}.tar.bz2 &&\
    cd shared-mime-info-${SHARED_MIME_INFO_VERSION} &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dbuild-tools=false -Dbuild-tests=false -Dbuild-spec=false -Dbuild-translations=false &&\
    meson compile -C build &&\
    meson install -C build &&\
    ln -s ${PREFIX_DIR}/share/pkgconfig/shared-mime-info.pc ${PREFIX_DIR}/lib/pkgconfig/shared-mime-info.pc &&\
    cd .. && rm -rf shared-mime-info-${SHARED_MIME_INFO_VERSION}.tar.bz2 shared-mime-info-${SHARED_MIME_INFO_VERSION}

# gdk-pixbuf
# 需要 shared-mime-info
ENV GDK_PIXBUF_VERSION=2.44.7
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    wget https://download.gnome.org/sources/gdk-pixbuf/${GDK_PIXBUF_VERSION%.*}/gdk-pixbuf-${GDK_PIXBUF_VERSION}.tar.xz &&\
    tar xvf gdk-pixbuf-${GDK_PIXBUF_VERSION}.tar.xz &&\
    cd gdk-pixbuf-${GDK_PIXBUF_VERSION} &&\
    sed -i "s|\[ 'gdk-pixbuf-csource' \],||g" gdk-pixbuf/meson.build &&\
    sed -i "s|\[ 'gdk-pixbuf-pixdata' \],||g" gdk-pixbuf/meson.build &&\
    sed -i "s|\[ 'gdk-pixbuf-query-loaders', \[ 'queryloaders.c' \] \],||g" gdk-pixbuf/meson.build &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dman=false -Dtests=false -Dinstalled_tests=false -Dintrospection=disabled \
        -Dbuiltin_loaders=all -Dglycin=disabled -Dandroid=disabled -Dtiff=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    cd .. && rm -rf gdk-pixbuf-${GDK_PIXBUF_VERSION}.tar.xz gdk-pixbuf-${GDK_PIXBUF_VERSION}

# rsvg
# 需要 libxml2 gdk-pixbuf
ENV RSVG_VERSION=2.62.3
RUN mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR} &&\
    apt update && apt install -y libssl-dev && rm -rf /var/lib/apt/lists/* &&\
    wget https://download.gnome.org/sources/librsvg/${RSVG_VERSION%.*}/librsvg-${RSVG_VERSION}.tar.xz &&\
    tar xvf librsvg-${RSVG_VERSION}.tar.xz &&\
    cd librsvg-${RSVG_VERSION} &&\
    curl https://sh.rustup.rs -sSf | sh -s -- -y --target wasm32-unknown-emscripten &&\
    . "$HOME/.cargo/env" &&\
    cargo install cargo-c --version 0.10.10 --locked &&\
    export PKG_CONFIG_ALLOW_CROSS=1 &&\
    export PKG_CONFIG_PATH=${PREFIX_DIR}/lib/pkgconfig:${PREFIX_DIR}/share/pkgconfig &&\
    export CARGO_TARGET_WASM32_UNKNOWN_EMSCRIPTEN_LINKER=emcc &&\
    export CARGO_PROFILE_RELEASE_PANIC=abort &&\
    meson setup build --prefix=${PREFIX_DIR} --cross-file=../emscripten.txt --default-library=static --buildtype=release \
        -Dtriplet=wasm32-unknown-emscripten -Drsvg-convert=disabled -Dpixbuf-loader=disabled \
        -Ddocs=disabled -Dintrospection=disabled -Dvala=disabled -Dtests=false -Davif=disabled &&\
    meson compile -C build &&\
    meson install -C build &&\
    rustup self uninstall -y &&\
    cd .. && rm -rf librsvg-${RSVG_VERSION}.tar.xz librsvg-${RSVG_VERSION}

# clean meson
RUN rm ${BUILD_DIR}/emscripten.txt
