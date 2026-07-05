# Render.com Free Tier friendly Dockerfile
# Android Studio 2026.1.1.10 (Quail 1 Patch 2)
# Single file - no COPY needed
# For Render: Connect repo + select Language: Docker + Free instance

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PASS=vncpassword \
    DISPLAY=:1 \
    RESOLUTION=1280x720 \
    USER=developer

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg supervisor \
    xfce4 xfce4-goodies x11vnc xvfb xterm dbus-x11 \
    openjdk-17-jdk \
    libgtk-3-0 libxext6 libxrender1 libxtst6 libxi6 \
    libgl1-mesa-glx libx11-xcb1 libxcb1 \
    unzip zip git \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash $USER && \
    echo "$USER:$VNC_PASS" | chpasswd && \
    usermod -aG sudo $USER

# noVNC
RUN mkdir -p /opt/noVNC && \
    curl -fsSL https://github.com/novnc/noVNC/archive/v1.4.0.tar.gz | tar -xz -C /opt/noVNC --strip-components=1 && \
    ln -s /opt/noVNC/vnc.html /opt/noVNC/index.html && \
    curl -fsSL https://github.com/novnc/websockify/archive/v0.11.0.tar.gz | tar -xz -C /opt/noVNC/utils --strip-components=1

# Robust Android Studio download
RUN mkdir -p /opt && cd /opt && \
    for i in 1 2 3 4 5; do \
        echo "Download attempt $i..." && \
        curl -L --retry 5 --retry-delay 12 --max-time 350 \
            -o android-studio.tar.gz \
            "https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2026.1.1.10/android-studio-quail1-patch2-linux.tar.gz" && \
        SIZE=$(stat -c%s android-studio.tar.gz 2>/dev/null || echo 0) && \
        if [ "$SIZE" -gt 1000000000 ]; then echo "✅ Download OK"; break; fi; \
        echo "Retry..."; sleep 35; \
    done && \
    tar -xzf android-studio.tar.gz && \
    mv android-studio /opt/android-studio && \
    rm -f android-studio.tar.gz && \
    chmod -R 755 /opt/android-studio

RUN mkdir -p /home/$USER/Android/Sdk /home/$USER/Projects /home/$USER/.vnc && \
    chown -R $USER:$USER /home/$USER /opt/android-studio

# Startup script
RUN printf '#!/bin/bash\n\
set -e\n\
echo "Starting VNC + Android Studio..."\n\
mkdir -p /home/$USER/.vnc\n\
echo "$VNC_PASS" | vncpasswd -f > /home/$USER/.vnc/passwd\n\
chmod 600 /home/$USER/.vnc/passwd\n\
\n\
vncserver $DISPLAY -geometry $RESOLUTION -depth 24 -localhost no -SecurityTypes VncAuth -rfbauth /home/$USER/.vnc/passwd &\n\
sleep 5\n\
\n\
/opt/noVNC/utils/websockify --web /opt/noVNC 7860 localhost:5901 &\n\
\n\
startxfce4 &\n\
sleep 8\n\
\n\
cd /home/$USER\n\
/opt/android-studio/bin/studio.sh &\n\
\n\
tail -f /dev/null\n\
' > /startup.sh && chmod +x /startup.sh

RUN mkdir -p /etc/supervisor/conf.d && \
    printf '[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:desktop]\n\
command=/startup.sh\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/var/log/supervisor/desktop.log\n\
stderr_logfile=/var/log/supervisor/desktop.err\n\
' > /etc/supervisor/conf.d/supervisord.conf

EXPOSE 7860 5901

USER $USER
WORKDIR /home/$USER

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:7860 || exit 1

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
