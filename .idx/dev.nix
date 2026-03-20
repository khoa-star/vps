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

      # 1. Dọn dẹp môi trường (Giữ lại thư mục vps chứa code của bạn)
      if [ ! -f /home/user/.cleanup_done ]; then
        echo "Cleaning up..."
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'vps' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      VM_DIR="$HOME/qemu"
      DISK="$VM_DIR/ubuntu.qcow2"
      SEED_ISO="$VM_DIR/seed.iso"
      NOVNC_DIR="$HOME/noVNC"

      mkdir -p "$VM_DIR"

      # 2. Tải Ubuntu và Set Disk 100GB
      if [ ! -f "$DISK" ]; then
        echo "Downloading Ubuntu 24.04 Cloud Image..."
        wget -O "$DISK" https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
        echo "Resizing disk to 100G..."
        qemu-img resize "$DISK" 100G
      fi

      # 3. Chạy Python tạo Seed ISO (GNOME + Auto gdm3)
      if [ ! -f "$SEED_ISO" ]; then
        echo "Creating Seed ISO..."
        python3 /home/user/vps/main.py
      fi

      # 4. Chuẩn bị noVNC
      if [ ! -d "$NOVNC_DIR" ]; then
        echo "Cloning noVNC..."
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # 5. Khởi động QEMU với 16GB RAM (16384MB)
      echo "Starting QEMU (16GB RAM / 100GB Disk)..."
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

      sleep 10

      # 6. Khởi động noVNC Proxy
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &

      # 7. Cloudflared và Lọc link chuẩn (Loại bỏ link 'api.')
      rm -f /tmp/cloudflared.log
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      echo "Waiting for Cloudflare Link (Checking log...)"
      
      URL=""
      for i in {1..30}; do
        # Lấy link trycloudflare nhưng KHÔNG có chữ 'api'
        URL=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" /tmp/cloudflared.log | grep -v "api" | head -n1)
        if [ -n "$URL" ]; then
          break
        fi
        sleep 2
      done

      if [ -n "$URL" ]; then
        echo "========================================="
        echo " CẤU HÌNH: 16GB RAM | 100GB DISK"
        echo " Link noVNC: $URL/vnc.html"
        echo " User: ubuntu | Pass: ubuntu"
        echo "========================================="
        mkdir -p /home/user/vps
        echo "$URL/vnc.html" > /home/user/vps/noVNC-URL.txt
      else
        echo "Cloudflared failed. Kiểm tra log tại /tmp/cloudflared.log"
      fi

      # Giữ script chạy ngầm
      elapsed=0
      while true; do
        echo "Uptime: $elapsed min | QEMU: $(pgrep qemu-system > /dev/null && echo running || echo STOPPED)"
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
        command = [ "bash" "-lc" "echo 'noVNC port 8888 ready'" ];
      };
    };
  };
}
