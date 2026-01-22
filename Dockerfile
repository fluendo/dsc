FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --fix-missing \
    build-essential \
    pkg-config \
    vim \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-good1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    libgstreamer-plugins-base1.0-0 \
    libgstreamer-plugins-good1.0-0 \
    libgstreamer-plugins-bad1.0-0 \
    libglib2.0-dev \
    libssl-dev \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-x \
    curl \
    ca-certificates \
    git \
    gdb \
    && rm -rf /var/lib/apt/lists/*

# Install additional dependencies for building libvmaf and GStreamer
RUN apt-get update && apt-get install -y --fix-missing \
    meson \
    ninja-build \
    python3-pip \
    yasm \
    nasm \
    cmake \
    libtool \
    autoconf \
    automake \
    pkg-config \
    libxml2-dev \
    libfftw3-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    zlib1g-dev \
    liborc-0.4-dev \
    libglib2.0-dev \
    libgdk-pixbuf2.0-dev \
    libgtk-3-dev \
    libgudev-1.0-dev \
    libdrm-dev \
    libx11-dev \
    libxext-dev \
    libxfixes-dev \
    libxrandr-dev \
    libxi-dev \
    libxv-dev \
    libxtst-dev \
    libxinerama-dev \
    libxcomposite-dev \
    libxdamage-dev \
    libxrender-dev \
    libpango1.0-dev \
    libjson-glib-dev \
    libgstreamer-plugins-base1.0-dev \
    cython3 \
    python3-setuptools \
    python3-numpy \
    flex \
    bison \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libva-dev \
    libva-drm2 \
    libva-x11-2 \
    libva2 \
    vainfo \
    intel-media-va-driver \
    mesa-va-drivers \
    && rm -rf /var/lib/apt/lists/*

# Upgrade meson to >=1.4 (required for GStreamer build)
RUN rm -f /usr/lib/python*/EXTERNALLY-MANAGED && pip3 install --upgrade meson

# Install Rust toolchain
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

RUN apt-get update && apt-get install -y --fix-missing \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory for all projects
WORKDIR /root

# Clone and build GStreamer
RUN git clone --depth=1 --branch h266seiinserter https://gitlab.freedesktop.org/diegonieto/gstreamer.git gstreamer \
    && cd gstreamer \
    && meson build --prefix=/usr/local \
        -Dgst-plugins-bad:va=enabled \
        -Dgst-plugins-bad:videoparsers=enabled \
        -Dgstreamer:tools=enabled \
        --auto-features=disabled \
    && ninja -C build \
    && ninja -C build install \
    && ldconfig

# Clone GStreamer Rust bindings
RUN git clone --branch dsc https://gitlab.freedesktop.org/diegonieto/gstreamer-rs.git gstreamer-rs \
    && cd gstreamer-rs \
    && git submodule update --init \
    && cargo build -p gstreamer-video -F v1_30

# Clone GStreamer plugins in Rust
COPY gst-rs-cargo.patch /tmp/gst-rs-cargo.patch
RUN git clone --depth=1 --branch dsc https://github.com/fluendo/gst-plugins-rs.git gst-plugins-rs \
    && cd gst-plugins-rs \
    && patch -p1 < /tmp/gst-rs-cargo.patch \
    && cargo build -p gst-plugin-dsc

# Clone and build VTM (VVC reference software)
RUN git clone --depth=1 --branch VTM-23.13 https://vcgit.hhi.fraunhofer.de/jvet/VVCSoftware_VTM.git VVCSoftware_VTM \
    && cd VVCSoftware_VTM \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TRACING=true \
    && make -j$(nproc)

# Remove conflicting system GStreamer plugins that cause symbol errors
RUN rm -f /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstv4l2codecs.so \
    /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstnvcodec.so

# Find and setup gst-plugin-scanner
RUN mkdir -p /usr/libexec/gstreamer-1.0 \
    && find /usr -name "gst-plugin-scanner" -type f 2>/dev/null | head -1 | xargs -I {} ln -sf {} /usr/libexec/gstreamer-1.0/gst-plugin-scanner || \
    find /usr/local -name "gst-plugin-scanner" -type f 2>/dev/null | head -1 | xargs -I {} ln -sf {} /usr/libexec/gstreamer-1.0/gst-plugin-scanner

ENV GST_PLUGIN_SCANNER="/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
ENV PATH="/usr/libexec/gstreamer-1.0:${PATH}"

# Set GST_PLUGIN_PATH to include vmaf plugin
ENV GST_PLUGIN_PATH="/root/gst-plugins-rs/target/debug:/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0"
ENV LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/local/lib:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"
ENV PATH="/usr/local/bin:${PATH}"