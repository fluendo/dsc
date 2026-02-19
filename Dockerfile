FROM ubuntu:25.10

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --fix-missing \
    build-essential \
    pkg-config \
    vim \
    unzip \
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
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libavfilter-dev \
    libswscale-dev \
    libgtk-4-dev \
    curl \
    ca-certificates \
    git \
    gdb \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Enable source repositories and install showtime build dependencies plus additional tools
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get install -y python3-pip flex bison cmake \
    && apt-get build-dep -y showtime \
    && rm -rf /var/lib/apt/lists/*

# Upgrade meson to >=1.4 (required for GStreamer build)
RUN rm -f /usr/lib/python*/EXTERNALLY-MANAGED && pip3 install --upgrade meson

# Install Rust toolchain
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory for all projects
WORKDIR /root

# Clone and build GStreamer
RUN git clone --depth=1 --branch h266seiinserter https://gitlab.freedesktop.org/diegonieto/gstreamer.git gstreamer \
    && cd gstreamer \
    && meson build --prefix=/usr/local \
        -Dgst-plugins-bad:videoparsers=enabled \
        -Dgstreamer:tools=enabled \
        -Dlibav=enabled \
        --wrap-mode=nofallback \
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
RUN git clone --depth=1 --branch dsc-upstream https://gitlab.freedesktop.org/diegonieto/gst-plugins-rs.git gst-plugins-rs \
    && cd gst-plugins-rs \
    && patch -p1 < /tmp/gst-rs-cargo.patch \
    && cargo build --release -p gst-plugin-dsc -p gst-plugin-gtk4 \
    && install -v target/release/libgst*so /usr/lib/x86_64-linux-gnu/gstreamer-1.0/

# Clone and build VTM (VVC reference software)
RUN git clone --depth=1 --branch VTM-23.13 https://vcgit.hhi.fraunhofer.de/jvet/VVCSoftware_VTM.git VVCSoftware_VTM \
    && cd VVCSoftware_VTM \
    && mkdir build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TRACING=true -DCMAKE_CXX_FLAGS="-Wno-error=unused-value" \
    && make -j"$(nproc)"

# Remove conflicting system GStreamer plugins that cause symbol errors
RUN rm -f /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstv4l2codecs.so \
    /usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstnvcodec.so

# Clone and build Showtime video player with DSC support
RUN git clone --depth=1 --branch dsc https://github.com/fluendo/showtime.git showtime \
    && cd showtime \
    && meson setup build --prefix=/usr/local \
    && ninja -C build \
    && ninja -C build install \
    && cd .. \
    && rm -rf showtime \
    && ldconfig

# Find and setup gst-plugin-scanner
RUN mkdir -p /usr/libexec/gstreamer-1.0 \
    && find /usr -name "gst-plugin-scanner" -type f 2>/dev/null | head -1 | xargs -I {} ln -sf {} /usr/libexec/gstreamer-1.0/gst-plugin-scanner || \
    find /usr/local -name "gst-plugin-scanner" -type f 2>/dev/null | head -1 | xargs -I {} ln -sf {} /usr/libexec/gstreamer-1.0/gst-plugin-scanner

ENV GST_PLUGIN_SCANNER="/usr/libexec/gstreamer-1.0/gst-plugin-scanner"
ENV PATH="/usr/libexec/gstreamer-1.0:${PATH}"

ENV GST_PLUGIN_PATH="/usr/local/lib/x86_64-linux-gnu/gstreamer-1.0:/usr/lib/x86_64-linux-gnu/gstreamer-1.0"
ENV LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
ENV PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"
ENV PATH="/usr/local/bin:${PATH}"

# Set Python path for showtime (check multiple possible locations)
RUN PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") \
    && echo "export PYTHONPATH=\"/usr/local/lib/python${PYTHON_VERSION}/site-packages:/usr/local/lib/python3/dist-packages:\${PYTHONPATH}\"" >> /root/.bashrc

RUN wget "https://drive.usercontent.google.com/download?id=1A8ZtCtwShd3C5ZADjsMRGZ0QV1L7FnUT&confirm=t" -O UFO-DSC-Example.zip \
    && unzip UFO-DSC-Example.zip -d /root/UFO-DSC-Example \
    && rm UFO-DSC-Example.zip

ENV DSC_KEY_STORE_PATH=/root/UFO-DSC-Example/UFO-DSC-Example/keystore/pub/

ENV PYTHONPATH="/usr/local/lib/python3.13/site-packages:/usr/local/lib/python3/dist-packages:${PYTHONPATH}"

# Fix X11 authorization
ENV QT_X11_NO_MITSHM=1
ENV XDG_RUNTIME_DIR=/tmp/runtime-root

