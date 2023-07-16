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
    avahi-daemon \
    libavahi-client-dev \
    git \
    ca-certificates \
    xz-utils \
    wget

# 准备构建目录
RUN mkdir -p /build
WORKDIR /build

# 克隆 SoapySDR 和他的那些仓库
RUN git clone https://github.com/pothosware/SoapySDR
RUN git clone https://github.com/pothosware/SoapyRemote
RUN git clone https://github.com/pothosware/SoapySDRPlay3

# 下载 SDRPlay 依赖,解压到 rsp 目录
RUN wget -O rsp-api.run https://www.sdrplay.com/software/SDRplay_RSP_API-Linux-3.07.1.run
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
ENV VERS="3.07"
ENV MAJVERS="3"
# RUN cp /build/rsp/x86_64/libsdrplay_api.so.3.07 /opt/lib/
# 装库
RUN set -x && rm -f /opt/lib/libsdrplay_api.so.${VERS} && \
    rm -f /opt/lib/libsdrplay_api.so && \
    rm -f /opt/lib/libsdrplay_api.so.${MAJVERS} && \
    cp -f rsp/x86_64/libsdrplay_api.so.${VERS} /opt/lib/. && \
    chmod 644 /opt/lib/libsdrplay_api.so.${VERS} && \
    ln -s /opt/lib/libsdrplay_api.so.${VERS} /opt/lib/libsdrplay_api.so.${MAJVERS} && \
    ln -s /opt/lib/libsdrplay_api.so.${MAJVERS} /opt/lib/libsdrplay_api.so
# 装 inc
RUN cp -f rsp/inc/sdrplay_api*.h /opt/include/. && \
    chmod 644 /opt/include/sdrplay_api*.h
# 装 bin
RUN cp -f rsp/x86_64/sdrplay_apiService /opt/bin/sdrplay_apiService && \
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
ENV DEBIAN_FRONTEND=noninteractive
# RUN sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources
RUN apt update && apt install -y --no-install-recommends \
    avahi-daemon \
    libavahi-client3 \
    udev \
    procps \
    usbutils


# SDRPlay 的设备规则
COPY --from=build-base /build/rsp/66-mirics.rules /etc/udev/rules.d/66-mirics.rules
# SDRPlay 更新 USB ID
COPY --from=build-base /build/rsp/scripts/sdrplay_ids.txt /opt/bin/sdrplay_ids.txt

# 从 build-base 阶段拷贝构建结果
COPY --from=build-base /opt /opt
# 拷贝 S6-init
COPY --from=build-base /tmp/s6-temp/ /
# 拷贝 S6 服务
COPY  s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# ENV LD_LIBRARY_PATH=/opt/lib
ENV PATH=/opt/bin:$PATH

# 给一些运行时必须的变量
ENV SOPAY_REMOTE_BIND=0.0.0.0:55132
ENTRYPOINT ["/init"]
