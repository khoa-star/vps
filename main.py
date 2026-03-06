import struct, os, time

def pad(data, size):
    return data + b'\x00' * (size - len(data))

def make_iso(output_path, files):
    SECTOR = 2048
    file_start_sector = 19
    file_sectors = []
    offset = file_start_sector
    for name, content in files:
        file_sectors.append(offset)
        sectors_needed = (len(content) + SECTOR - 1) // SECTOR
        offset += sectors_needed
    total_sectors = offset

    def lsb_msb_16(n):
        return struct.pack('<H', n) + struct.pack('>H', n)
    def lsb_msb_32(n):
        return struct.pack('<I', n) + struct.pack('>I', n)
    def date_field(t=None):
        if t is None:
            t = time.gmtime()
        return bytes([t.tm_year-1900, t.tm_mon, t.tm_mday,
                      t.tm_hour, t.tm_min, t.tm_sec, 0])
    def dir_record(name_bytes, sector, size, is_dir=False):
        flags = 0x02 if is_dir else 0x00
        name_len = len(name_bytes)
        record_len = 33 + name_len
        if record_len % 2 != 0:
            record_len += 1
        rec = bytes([record_len, 0])
        rec += lsb_msb_32(sector)
        rec += lsb_msb_32(size)
        rec += date_field()
        rec += bytes([flags, 0, 0])
        rec += lsb_msb_16(1)
        rec += bytes([name_len]) + name_bytes
        if len(rec) % 2 != 0:
            rec += b'\x00'
        return rec

    root_dir = b''
    root_dir += dir_record(b'\x00', 18, SECTOR, is_dir=True)
    root_dir += dir_record(b'\x01', 18, SECTOR, is_dir=True)
    for i, (name, content) in enumerate(files):
        root_dir += dir_record(name.upper().encode(), file_sectors[i], len(content))
    root_dir_padded = pad(root_dir, SECTOR)

    pvd = b'\x01'
    pvd += b'CD001\x01\x00'
    pvd += b' ' * 32
    pvd += pad(b'CIDATA', 32)
    pvd += b'\x00' * 8
    pvd += lsb_msb_32(total_sectors)
    pvd += b'\x00' * 32
    pvd += lsb_msb_16(1)
    pvd += lsb_msb_16(1)
    pvd += lsb_msb_16(SECTOR)
    pvd += lsb_msb_32(total_sectors * SECTOR)
    pvd += struct.pack('<I', 0)
    pvd += struct.pack('<I', 0)
    pvd += struct.pack('>I', 0)
    pvd += struct.pack('>I', 0)
    pvd += dir_record(b'\x00', 18, SECTOR, is_dir=True)
    pvd += b' ' * 128
    pvd += b' ' * 128
    pvd += b' ' * 128
    pvd += b' ' * 128
    pvd += b' ' * 37
    pvd += b' ' * 37
    pvd += b' ' * 37
    pvd += b'0001010000000000\x00'
    pvd += b'0000000000000000\x00'
    pvd += b'0000000000000000\x00'
    pvd += b'0000000000000000\x00'
    pvd += b'\x01\x00'
    pvd = pad(pvd, SECTOR)

    term = pad(b'\xff' + b'CD001\x01', SECTOR)

    with open(output_path, 'wb') as f:
        f.write(b'\x00' * (16 * SECTOR))
        f.write(pvd)
        f.write(term)
        f.write(root_dir_padded)
        for name, content in files:
            sectors_needed = (len(content) + SECTOR - 1) // SECTOR
            f.write(pad(content, sectors_needed * SECTOR))
    print(f"ISO created: {output_path} ({os.path.getsize(output_path)} bytes)")

meta_data = "instance-id: ubuntu-qemu-01\nlocal-hostname: ubuntu-vm\n".encode('utf-8')

user_data = """#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
chpasswd:
  expire: false
  list:
    - ubuntu:ubuntu
ssh_pwauth: false
package_update: true
package_upgrade: false
packages:
  - xfce4
  - xfce4-goodies
  - x11vnc
  - xvfb
  - dbus-x11
  - wget
  - curl
  - htop
  - nano
  - net-tools
  - firefox
  - libxdo3
  - gstreamer1.0-pipewire
write_files:
  - path: /etc/systemd/system/xvnc.service
    content: |
      [Unit]
      Description=Xvfb + XFCE + x11vnc
      After=network.target
      [Service]
      User=ubuntu
      Environment=DISPLAY=:0
      ExecStartPre=/bin/bash -c "pkill Xvfb || true"
      ExecStartPre=/bin/bash -c "pkill x11vnc || true"
      ExecStartPre=/bin/bash -c "Xvfb :0 -screen 0 1280x800x24 &"
      ExecStartPre=/bin/sleep 3
      ExecStart=/bin/bash -c "DISPLAY=:0 dbus-launch --exit-with-session startxfce4 & sleep 5 && x11vnc -display :0 -rfbport 5900 -passwd ubuntu -forever -shared -o /var/log/x11vnc.log"
      Restart=on-failure
      RestartSec=5
      [Install]
      WantedBy=multi-user.target
  - path: /etc/lightdm/lightdm.conf
    content: |
      [Seat:*]
      autologin-user=ubuntu
      autologin-user-timeout=0
      user-session=xfce
  - path: /home/ubuntu/.config/autostart/rustdesk.desktop
    content: |
      [Desktop Entry]
      Type=Application
      Name=RustDesk
      Exec=rustdesk
      Hidden=false
      NoDisplay=false
      X-GNOME-Autostart-enabled=true
runcmd:
  - passwd -d ubuntu
  - chown -R ubuntu:ubuntu /home/ubuntu
  - mkdir -p /home/ubuntu/.config/autostart
  - chown -R ubuntu:ubuntu /home/ubuntu/.config
  - wget -O /tmp/rustdesk.deb https://github.com/rustdesk/rustdesk/releases/download/1.4.5/rustdesk-1.4.5-x86_64.deb
  - dpkg -i /tmp/rustdesk.deb || true
  - apt install -f -y
  - systemctl enable xvnc.service
  - reboot
""".encode('utf-8')

make_iso(os.environ['HOME'] + '/qemu/seed.iso', [
    ('meta-data', meta_data),
    ('user-data', user_data),
])
