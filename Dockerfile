FROM emscripten/emsdk:latest

# APT
RUN apt update &&\
    apt install -y pkgconf python3 cargo automake-1.15

# deb-src
RUN sed -i "s|^# deb-src|deb-src|g" /etc/apt/sources.list &&\
    sed -i "s|^deb-src http://archive.canonical.com/ubuntu|# deb-src http://archive.canonical.com/ubuntu|g" /etc/apt/sources.list &&\
    apt update

# opencv
RUN mkdir -p /i &&\
    cd /i &&\
    wget https://github.com/opencv/opencv/archive/refs/tags/4.5.5.tar.gz -O opencv-4.5.5.tar.gz &&\
    tar xvf opencv-4.5.5.tar.gz &&\
    cd opencv-4.5.5 &&\
    emmake python3 ./platforms/js/build_js.py --build_wasm $(emcmake echo | awk -v RS=' ' -v ORS=' ' '{print "--cmake_option=\""$1"\""}') --cmake_option="-DCMAKE_INSTALL_PREFIX=/emsdk/upstream/emscripten/cache/sysroot" build &&\
    cmake --build build -j8 &&\
    cmake --install build

# zlib
RUN mkdir -p /i &&\
    cd /i &&\
    apt source zlib &&\
    cd zlib-* &&\
    mkdir win32 && touch win32/zlib1.rc &&\
    emcmake cmake -B build &&\
    cmake --build build -j8 &&\
    cmake --install build

# libpng
# 需要 zlib
RUN mkdir -p /i &&\
    cd /i &&\
    apt source libpng1.6 &&\
    cd libpng1.6-* &&\
    emcmake cmake -B build -DPNG_SHARED=no -DPNG_STATIC=yes -DPNG_FRAMEWORK=no -DM_LIBRARY="" &&\
    cmake --build build -j8 &&\
    cmake --install build

# freetype
# 需要 libpng zlib
RUN mkdir -p /i &&\
    cd /i &&\
    apt source freetype &&\
    cd freetype-* &&\
    emcmake cmake -B build &&\
    cmake --build build -j8 &&\
    cmake --install build

# pixman
RUN mkdir -p /i &&\
    cd /i &&\
    apt source pixman &&\
    cd pixman-* &&\
    emconfigure ./configure &&\
    emmake make -j8 &&\
    emmake make install prefix=/emsdk/upstream/emscripten/cache/sysroot

# cairo
# 需要 libpng pixman freetype
RUN mkdir -p /i &&\
    cd /i &&\
    apt source cairo &&\
    cd cairo-* &&\
    emconfigure ./configure --enable-static -without-x \
        --disable-xlib --disable-xlib-xrender --disable-directfb --disable-win32 --disable-pdf --disable-ps --disable-svg \
        --enable-script=no --enable-png \
        --disable-interpreter --disable-xlib-xcb --disable-xcb --disable-xcb-shm \
        --enable-ft --enable-fc=no \
        ax_cv_c_float_words_bigendian=no \
        FREETYPE_CFLAGS="$(emmake pkg-config --cflags freetype2)" FREETYPE_LIBS="$(emmake pkg-config --libs freetype2)" \
        png_CFLAGS="$(emmake pkg-config --cflags libpng)" png_LIBS="$(emmake pkg-config --libs libpng)" \
        pixman_CFLAGS="$(emmake pkg-config --cflags pixman-1)" pixman_LIBS="$(emmake pkg-config --libs pixman-1)" \
        LDFLAGS="$(emmake pkg-config --libs zlib)" &&\
    emmake make -j8 &&\
    emmake make install prefix=/emsdk/upstream/emscripten/cache/sysroot