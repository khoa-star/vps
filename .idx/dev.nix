{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # 1. Dọn dẹp môi trường
      if [ ! -f /home/user/.cleanup_done ]; then
        echo "Cleaning up..."
        rm -rf /home/user/.gradle/* || true
        rm -rf /home/user/.emu/* || true
        rm -rf /home/user/.android/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'vps' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
        echo "Cleanup done."
      else
        echo "Cleanup already done, skipping."
      fi

      VM_DIR="$HOME/qemu"
      DISK="$VM_DIR/ubuntu.qcow2"
      SEED_ISO="$VM_DIR/seed.iso"
      NOVNC_DIR="$HOME/noVNC"

      mkdir -p "$VM_DIR"

      # 2. Chuẩn bị Disk Ubuntu
      if [ ! -f "$DISK" ]; then
        echo "Downloading Ubuntu 24.04 cloud image..."
        wget -O "$DISK" \
          https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
        echo "Resizing disk to 64G..."
        qemu-img resize "$DISK" 64G
      else
        echo "Ubuntu disk exists, skipping."
      fi

      # 3. Tạo Seed ISO
      if [ ! -f "$SEED_ISO" ] || [ ! -s "$SEED_ISO" ]; then
        echo "Creating seed ISO..."
        python3 /home/user/vps/main.py
        if [ -s "$SEED_ISO" ]; then
          echo "Seed ISO OK"
        else
          echo "Seed ISO failed!"
          exit 1
        fi
      else
        echo "Seed ISO exists, skipping."
      fi

      # 4. Tải noVNC
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      else
        echo "noVNC exists, skipping."
      fi

      # 5. Khởi động QEMU
      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp 8,cores=8 \
        -m 16384 \
        -M q35 \
        -device qemu-xhci \
        -device usb-tablet \
        -vga virtio \
        -netdev user,id=n0,hostfwd=tcp::2222-:22 \
        -net nic,netdev=n0,model=virtio-net-pci \
        -drive file="$DISK",format=qcow2,if=virtio \
        -drive file="$SEED_ISO",format=raw,if=virtio,readonly=on \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      echo "QEMU started. Waiting for VM to boot..."
      sleep 10

      # 6. Khởi động noVNC Proxy
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # 7. Khởi động Cloudflared (FIX CHÍNH XÁC LINK)
      echo "Starting Cloudflared..."
      rm -f /tmp/cloudflared.log
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      echo "Waiting for Cloudflare Tunnel..."
      
      # Vòng lặp chờ link public xuất hiện (tối đa 40s)
      for i in {1..40}; do
        if grep -q "trycloudflare.com" /tmp/cloudflared.log && grep "trycloudflare.com" /tmp/cloudflared.log | grep -qv "api"; then
          break
        fi
        sleep 1
      done

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        # Lấy link: PHẢI CÓ trycloudflare VÀ KHÔNG ĐƯỢC CÓ api
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" /tmp/cloudflared.log | grep -v "api" | head -n1)
        
        echo "========================================="
        echo " Ubuntu Server + XFCE ready:"
        echo " Link noVNC: $URL/vnc.html"
        echo " VNC Password: ubuntu"
        echo " SSH: ssh -p 2222 ubuntu@localhost"
        echo "========================================="
        
        mkdir -p /home/user/vps
        echo "$URL/vnc.html" > /home/user/vps/noVNC-URL.txt
      else
        echo "Cloudflared failed. Check /tmp/cloudflared.log"
      fi

      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min | QEMU: $(pgrep qemu-system > /dev/null && echo running || echo STOPPED)"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [ "bash" "-lc" "echo 'noVNC running on port 8888'" ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
