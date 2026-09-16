FROM debian:12 AS build-base
# RUN sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources
# 构建 SoapySDR 需要这些
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y \
    cmake \
    g++ \
    libpython3-dev \
    python3-numpy \
    swig \
    python3-distutils \
    git \
    ca-certificates \
    xz-utils \
    wget

# 拿掉了这个
# avahi-daemon \
# libavahi-client-dev \

# 准备构建目录
RUN mkdir -p /build
WORKDIR /build

# 克隆 SoapySDR 和他的那些仓库
RUN git clone https://github.com/pothosware/SoapySDR
RUN git clone https://github.com/pothosware/SoapyRemote
RUN git clone https://github.com/pothosware/SoapySDRPlay3

# 下载 SDRPlay 依赖,解压到 rsp 目录
# 官方把直链下载改成了 WPDM(WordPress Download Manager)网盘中转,
# 这个 URL 是 hardware-api-linux 下载页里 wpdm-download-link 的 data-downloadurl,
# 会 302 跳到 SharePoint 的实际文件,wpdmdl=1906 目前是稳定的
RUN wget -O rsp-api.run "https://sdrplay.com/download/hardware-api-linux/?wpdmdl=1906"
RUN chmod +x ./rsp-api.run && ./rsp-api.run --quiet --noexec --target rsp


# 构建第一个 SoapySDR
RUN cd SoapySDR && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt .. && \
    make -j$(nproc) && \
    make install

# 构建 SoapyRemote
RUN cd SoapyRemote && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt .. && \
    make -j$(nproc) && \
    make install

# 部署 SDRPlay 二进制依赖
ENV VERS="3.15"
ENV MAJVERS="3"
# 装库
# 新版安装包把架构目录从 x86_64 改成了 amd64(跟 dpkg --print-architecture 对齐)
RUN set -x && rm -f /opt/lib/libsdrplay_api.so.${VERS} && \
    rm -f /opt/lib/libsdrplay_api.so && \
    rm -f /opt/lib/libsdrplay_api.so.${MAJVERS} && \
    cp -f rsp/amd64/libsdrplay_api.so.${VERS} /opt/lib/. && \
    chmod 644 /opt/lib/libsdrplay_api.so.${VERS} && \
    ln -s /opt/lib/libsdrplay_api.so.${VERS} /opt/lib/libsdrplay_api.so.${MAJVERS} && \
    ln -s /opt/lib/libsdrplay_api.so.${MAJVERS} /opt/lib/libsdrplay_api.so
# 装 inc
RUN cp -f rsp/inc/sdrplay_api*.h /opt/include/. && \
    chmod 644 /opt/include/sdrplay_api*.h
# 装 bin
RUN cp -f rsp/amd64/sdrplay_apiService /opt/bin/sdrplay_apiService && \
    chmod 755 /opt/bin/sdrplay_apiService

# 构建 SoapySDRPlay3
RUN cd SoapySDRPlay3 && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt .. && \
    make -j$(nproc) && \
    make install

# 清理,删掉不必要的
RUN rm -rf /opt/lib/python* \
    /opt/lib/pkgconfig \
    /opt/lib/systemd \
    /opt/lib/sysctl.d

# 布置 S6-init
ARG S6_OVERLAY_VERSION=3.1.5.0
RUN mkdir -p /tmp/s6-temp
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /tmp/s6-temp -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C /tmp/s6-temp -Jxpf /tmp/s6-overlay-x86_64.tar.xz


# 最后的组装
FROM debian:12-slim
# FROM frolvlad/alpine-glibc
ENV DEBIAN_FRONTEND=noninteractive
# RUN apt update && apt install -y --no-install-recommends \
#     procps \
#     usbutils
# RUN apk add --no-cache libstdc++6
# 容器内以 root 运行 sdrplay_apiService,不需要 udev 规则来放宽设备权限,
# USB 热插拔权限改由宿主机 docker 的 device_cgroup_rules 处理(见 docker-compose.yml)
# 注:新版安装包(3.15)已经不再附带 scripts/sdrplay_ids.txt,这个文件被官方去掉了

# 从 build-base 阶段拷贝构建结果
COPY --from=build-base /opt /opt
# 拷贝 S6-init
COPY --from=build-base /tmp/s6-temp/ /
# 拷贝 S6 服务
COPY  s6-rc.d/ /etc/s6-overlay/s6-rc.d/

ENV LD_LIBRARY_PATH=/opt/lib
ENV PATH=/opt/bin:$PATH

# 给一些运行时必须的变量
ENV SOPAY_REMOTE_BIND=0.0.0.0:55132
ENTRYPOINT ["/init"]
