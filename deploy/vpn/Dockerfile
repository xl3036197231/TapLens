FROM docker.m.daocloud.io/library/ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i \
      -e 's|http://archive.ubuntu.com/ubuntu|http://mirrors.aliyun.com/ubuntu|g' \
      -e 's|http://security.ubuntu.com/ubuntu|http://mirrors.aliyun.com/ubuntu|g' \
      /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl dbus-x11 iproute2 iptables lsb-release net-tools procps psmisc \
      libasound2 libatk1.0-0 libcairo2 libcups2 libdbus-glib-1-2 libgdk-pixbuf2.0-0 \
      libgtk2.0-0 libnss3 libpango-1.0-0 libpangocairo-1.0-0 libx11-xcb1 libxcomposite1 \
      libxcursor1 libxdamage1 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 \
      novnc websockify x11vnc xvfb \
    && rm -rf /var/lib/apt/lists/*

ARG EASYCONNECT_URL=https://download.sangfor.com.cn/download/product/sslvpn/pkg/linux_767/EasyConnect_x64.deb
ARG EASYCONNECT_SHA256=6a9903b5c884651ab2264ab37b8f5a08edc0ab39a24a165d2134e5213450705c

RUN curl -fL --retry 3 "$EASYCONNECT_URL" -o /tmp/easyconnect.deb \
    && echo "$EASYCONNECT_SHA256  /tmp/easyconnect.deb" | sha256sum -c - \
    && dpkg-deb -x /tmp/easyconnect.deb / \
    && rm /tmp/easyconnect.deb \
    && chmod +x /usr/share/sangfor/EasyConnect/EasyConnect \
    && chmod +x /usr/share/sangfor/EasyConnect/resources/shell/* \
    && mkdir -p /usr/share/sangfor/EasyConnect/resources/logs \
    && chmod 0777 /usr/share/sangfor/EasyConnect/resources/logs \
    && chmod -R 0777 /usr/share/sangfor/EasyConnect/resources/conf \
    && chown root:root \
      /usr/share/sangfor/EasyConnect/resources/bin/ECAgent \
      /usr/share/sangfor/EasyConnect/resources/bin/svpnservice \
      /usr/share/sangfor/EasyConnect/resources/bin/CSClient \
    && chmod 4755 \
      /usr/share/sangfor/EasyConnect/resources/bin/ECAgent \
      /usr/share/sangfor/EasyConnect/resources/bin/CSClient \
    && chmod 6755 /usr/share/sangfor/EasyConnect/resources/bin/svpnservice \
    && useradd --create-home --shell /bin/bash easyconnect

COPY deploy/vpn/entrypoint.sh /usr/local/bin/taplens-vpn-entrypoint
RUN chmod 0755 /usr/local/bin/taplens-vpn-entrypoint

EXPOSE 6080
ENTRYPOINT ["/usr/local/bin/taplens-vpn-entrypoint"]
