FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG USERNAME=app
ARG UID=1000
ARG GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
    dbus-x11 \
    gosu \
    tigervnc-standalone-server \
    tigervnc-common \
    tigervnc-tools \
    xfce4-session \
    xfce4-panel \
    xfce4-settings \
    xfdesktop4 \
    xfwm4 \
    xterm \
    virt-manager \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/.X11-unix /tmp/.ICE-unix \
    && chmod 1777 /tmp /tmp/.X11-unix /tmp/.ICE-unix

RUN groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

ENV CONTAINER_USER=${USERNAME}
ENV CONTAINER_HOME=/home/${USERNAME}

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

WORKDIR /home/${USERNAME}

EXPOSE 5901

ENTRYPOINT ["/usr/local/bin/start.sh"]