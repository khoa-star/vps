{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -euo pipefail

      # One-time cleanup (safer: keep dotfiles and the idx folder)
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-ubuntu22-gui' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      CONTAINER_NAME=ubuntu-novnc
      IMAGE=thuonghai2711/ubuntu-novnc-pulseaudio:22.04

      # Create the container if missing; otherwise start it
      if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        docker run --name "$CONTAINER_NAME" \
          --shm-size 1g \
          -d \
          --cap-add=SYS_ADMIN \
          -p 8080:10000 \
          -e VNC_PASSWD=12345678 \
          -e PORT=10000 \
          -e AUDIO_PORT=1699 \
          -e WEBSOCKIFY_PORT=6900 \
          -e VNC_PORT=5900 \
          -e SCREEN_WIDTH=1024 \
          -e SCREEN_HEIGHT=768 \
          -e SCREEN_DEPTH=24 \
          "$IMAGE"
      else
        docker start "$CONTAINER_NAME" || true
      fi

      # Wait for container to be running and accept execs
      for i in 1 2 3 4 5 6 7 8 9 10; do
        if docker exec "$CONTAINER_NAME" bash -lc "echo ok" >/dev/null 2>&1; then
          break
        fi
        echo "waiting for container to be ready... ($i)"
        sleep 2
      done

      # Install Chrome inside the container as root (no sudo)
      docker exec "$CONTAINER_NAME" bash -lc '
        set -euo pipefail
        apt-get update -y || true
        apt-get remove -y firefox || true
        apt-get install -y wget apt-transport-https ca-certificates gnupg lsb-release || true

        # Download and install Chrome .deb (retry if network flakey)
        TMPDEB=/tmp/chrome.deb
        if wget -O "$TMPDEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; then
          apt-get install -y "$TMPDEB" || apt-get -f install -y
          rm -f "$TMPDEB"
        else
          echo "WARNING: chrome download failed"
        fi
      '

      # Run cloudflared in background and capture logs (consider systemd for permanence)
      CLOUD_LOG=/tmp/cloudflared.log
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 > "$CLOUD_LOG" 2>&1 &

      # Give it a few seconds to start
      sleep 8

      # Attempt to extract the public tunnel URL (trycloudflare domains)
      if grep -q -E "trycloudflare\\.com|trycloudflare" "$CLOUD_LOG" 2>/dev/null; then
        URL=$(grep -o -E "https?://[a-z0-9.-]*trycloudflare\\.com(:[0-9]+)?" "$CLOUD_LOG" | head -n1 || true)
        if [ -n "$URL" ]; then
          echo "========================================="
          echo " 🌍 Your Cloudflared tunnel is ready:"
          echo "     $URL"
          echo "========================================="
        else
          echo "❌ Couldn't parse URL from $CLOUD_LOG"
        fi
      else
        echo "❌ Cloudflared tunnel failed to start or no trycloudflare URL found. See $CLOUD_LOG"
      fi

      # Keep container/runner alive for developer preview (intentional long-running loop)
      elapsed=0
      while true; do
        echo "Time elapsed: ${elapsed} min"
        elapsed=$((elapsed + 1))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      novnc = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:8080"
        ];
      };
    };
  };
}
