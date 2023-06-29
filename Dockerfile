FROM debian:12 AS build-base
RUN sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources
# 构建 SoapySDR 需要这些
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
    wget

# 准备构建目录
RUN mkdir -p /build
WORKDIR /build

# 克隆 SoapySDR 和他的那些仓库
RUN git clone https://hub.fgit.ml/pothosware/SoapySDR
RUN git clone https://hub.fgit.ml/pothosware/SoapyRemote
RUN git clone https://hub.fgit.ml/pothosware/SoapySDRPlay3

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
ENV INSTALLLIBDIR=/opt/lib
ENV INSTALLINCDIR=/opt/include
ENV INSTALLBINDIR=/opt/bin
# RUN cp /build/rsp/x86_64/libsdrplay_api.so.3.07 /opt/lib/
# 装库
RUN set -x && rm -f ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} && \
    rm -f ${INSTALLLIBDIR}/libsdrplay_api.so && \
    rm -f ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} && \
    cp -f rsp/x86_64/libsdrplay_api.so.${VERS} ${INSTALLLIBDIR}/. && \
    chmod 644 ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} && \
    ln -s ${INSTALLLIBDIR}/libsdrplay_api.so.${VERS} ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} && \
    ln -s ${INSTALLLIBDIR}/libsdrplay_api.so.${MAJVERS} ${INSTALLLIBDIR}/libsdrplay_api.so
# 装 inc
RUN cp -f rsp/inc/sdrplay_api*.h ${INSTALLINCDIR}/. && \
    chmod 644 ${INSTALLINCDIR}/sdrplay_api*.h
# 装 bin
RUN cp -f rsp/x86_64/sdrplay_apiService ${INSTALLBINDIR}/sdrplay_apiService && \
    chmod 755 ${INSTALLBINDIR}/sdrplay_apiService



# 构建 SoapySDRPlay3
RUN cd SoapySDRPlay3 && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt .. && \
    make -j$(nproc) && \
    make install


# 最后的组装
FROM debian:12-slim
RUN sed -i 's#http://deb.debian.org#http://mirrors.ustc.edu.cn#g' /etc/apt/sources.list.d/debian.sources
# RUN apt update && apt install -y avahi-daemon libavahi-client3 supervisor procps usbutils
# 精简版
RUN apt update && apt install -y avahi-daemon libavahi-client3 supervisor

# SDRPlay 的设备规则
COPY --from=build-base /build/rsp/66-mirics.rules /etc/udev/rules.d/66-mirics.rules
# SDRPlay 更新 USB ID
COPY --from=build-base /build/rsp/scripts/sdrplay_ids.txt /opt/bin/sdrplay_ids.txt
# RUN cp -f /var/lib/usbutils/usb.ids /var/lib/usbutils/usb.ids.bak && \
#     echo "cat /opt/bin/sdrplay_ids.txt /var/lib/usbutils/usb.ids.bak > /var/lib/usbutils/usb.ids"

# 从 build-base 阶段拷贝构建结果
COPY --from=build-base /opt /opt
COPY supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ENV LD_LIBRARY_PATH=/opt/lib
ENV PATH=/opt/bin:$PATH

# 给一些运行时必须的变量
ENV SOPAY_REMOTE_BIND=0.0.0.0:55132
CMD ["/usr/bin/supervisord"]