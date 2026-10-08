# Build & Release Guide

This library targets **Raspberry Pi hardware only**. The C++ core directly
memory-maps GPIO, PWM, and clock registers via `/dev/mem`, so builds intended
for production must be compiled on (or cross-compiled for) a Raspberry Pi ARM
target. Builds on x86/x64 hosts will compile successfully but **cannot run**.

---

## Production Runtime Environment

This is the verified configuration of the live `rgb-panel` device.

| Item | Value |
|---|---|
| Hardware | Raspberry Pi 4 Model B Rev 1.2 (revision `c03112`) |
| OS | Debian GNU/Linux 13 (Trixie), 64-bit |
| Kernel | `6.12.47+rpt-rpi-v8` — standard PREEMPT (not RT) |
| Python | 3.13.5 |
| Pillow | 11.3.0 |
| numpy | 2.3.3 |
| requests | 2.32.5 |
| Cython | 3.0.11 |
| rgbmatrix | 0.0.1+20260125 |
| CPU frequency | 1900 MHz (overclocked, `arm_freq=1900`) |
| Audio | Disabled (`dtparam=audio=off`) — required for hardware PWM |
| Bluetooth | Disabled (`dtoverlay=disable-bt`) |
| Wi-Fi | Disabled (`dtoverlay=disable-wifi`) — wired Ethernet only |
| GPU memory | 16 MB (`gpu_mem_256/512/1024=16`) |
| Service | `rgb-panel.service` — systemd, `User=root`, `Restart=always`, `RuntimeMaxSec=24h` |

---

## Raspberry Pi OS Settings

### `/boot/firmware/cmdline.txt`

The live device uses the following kernel command line (single line, no wrapping):

```
root=PARTUUID=bc0a5264-02 rootfstype=ext4 rootwait net.ifnames=0 logo.nologo console=tty1 cfg80211.ieee80211_regdom=US isolcpus=3 ipv6.disable=1
```

The key addition for display quality is `isolcpus=3`, which pins CPU core 3 for
exclusive use by the matrix refresh thread. Add it to your own device:

```bash
sudo nano /boot/firmware/cmdline.txt
# append to the end of the existing single line:
#   isolcpus=3
sudo reboot
```

For even lower latency (especially on Pi 3 / Zero 2W) use the extended form:

```
isolcpus=domain,managed_irq,2,3 nohz_full=2,3 rcu_nocbs=2,3 irqaffinity=0,1 idle=poll
```

### `/boot/firmware/config.txt`

Active (non-comment) settings on the live device:

```ini
hdmi_blanking=1
disable_overscan=1
gpu_mem_256=16
gpu_mem_512=16
gpu_mem_1024=16
disable_splash=1
dtparam=audio=off        # required for hardware PWM pulse mode
dtparam=sd_poll_once
temp_limit=78
initial_turbo=20
over_voltage=4
arm_freq=1900            # Pi 4 overclock to 1.9 GHz
core_freq=600
arm_64bit=1
dtoverlay=disable-bt
dtoverlay=disable-wifi
```

The two mandatory entries for any new device are:

```ini
dtparam=audio=off        # disables snd_bcm2835 which conflicts with PWM
```

Without `audio=off`, the library will detect `snd_bcm2835` at startup,
print an error, and exit.

---

## Building the C++ Library

### On the Raspberry Pi (native build — recommended)

```bash
# Clone
git clone https://github.com/hzeller/rpi-rgb-led-matrix.git
cd rpi-rgb-led-matrix

# Build the static + shared library and all example binaries
make -j$(nproc)

# Artifacts:
#   lib/librgbmatrix.a        — static library
#   lib/librgbmatrix.so.1     — shared library
#   examples-api-use/*        — example binaries
```

Link your own binaries against the library with:

```bash
g++ myapp.cc -I./include -L./lib -lrgbmatrix -lrt -lm -lpthread -o myapp
```

### Cross-compiling from a Linux x86/x64 host

The `config.mk` in the repository handles cross-compile detection automatically —
`-march=native` and `-mtune=native` are dropped when `aarch64-linux-gnu-g++` is
the compiler.

```bash
# Install the ARM64 cross-toolchain (Ubuntu/Debian)
sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

# Build for Pi 4 / 3 / Zero 2W (64-bit aarch64)
make -j$(nproc) CXX=aarch64-linux-gnu-g++ CC=aarch64-linux-gnu-gcc
```

> Cross-compiled binaries must be transferred to the Pi to run. The library
> will fail to map `/dev/mem` on an x86 host.

---

## Build Options (Compile-time Flags)

These `DEFINES` live in `lib/Makefile` and can be overridden on the command
line with `USER_DEFINES` or set permanently. All have equivalent **runtime
flags** shown in parentheses, so you rarely need to bake them in at build time.

| Define | Runtime flag | Description |
|---|---|---|
| `HARDWARE_DESC=<name>` | `--led-gpio-mapping` | GPIO pinout: `regular` (default), `adafruit-hat`, `adafruit-hat-pwm`, `regular-pi1` |
| `RGB_SLOWDOWN_GPIO=<n>` | `--led-slowdown-gpio` | Slow GPIO writes. Default: 2 on Pi4, 1 elsewhere. Range: -1 (memory barrier) to 10 |
| `LSB_PWM_NANOSECONDS=<n>` | `--led-pwm-lsb-nanoseconds` | PWM LSB timing in ns (50–3000). Default: 130 |
| `DISABLE_HARDWARE_PULSES` | `--led-no-hardware-pulse` | Disable PWM hardware — required if audio is enabled |
| `FIXED_FRAME_MICROSECONDS=<n>` | `--led-limit-refresh` | Lock refresh period to reduce flicker |
| `DISABLE_BUSY_WAITING` | `--led-no-busy-waiting` | Free CPU during refresh rate limiting |
| `ENABLE_WIDE_GPIO_COMPUTE_MODULE` | — | 64-bit GPIO for Compute Module with >3 parallel chains |
| `SHOW_REFRESH_RATE` | `--led-show-refresh` | Print refresh rate to stdout |

Example — build with refresh logging:

```bash
make -j$(nproc) USER_DEFINES="-DSHOW_REFRESH_RATE"
```

---

## Building the Python Binding

The live device runs `rgbmatrix 0.0.1+20260125` built with Cython 3.0.11 and
Python 3.13.5. To reproduce that build:

```bash
# System build dependencies
sudo apt-get install -y \
    python3-dev \
    python3-pip \
    build-essential \
    cmake \
    git \
    libfreetype6-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    libtiff5-dev \
    libwebp-dev \
    zlib1g-dev

# Cython 3 (not Cython 0.x)
sudo apt-get install -y cython3
# or: pip3 install "cython>=3"

# Build the C++ library first, then the Python binding
make -j$(nproc)
sudo make install-python
```

To build without system-wide install (for local/dev use):

```bash
make build-python
# Extension lands at bindings/python/rgbmatrix/*.so
```

### Application Python dependencies (`new-panel`)

```bash
cd new-panel
pip3 install -r requirements.txt
# Pillow>=9.0.0, requests>=2.25.0, numpy>=1.24.0
```

---

## Running

All binaries that access hardware must run as **root** (or `sudo`). After
hardware init the process automatically drops privileges to `daemon:daemon`
(pass `--led-no-drop-privs` to keep root).

```bash
sudo ./examples-api-use/demo -D0 --led-rows=64 --led-cols=64
```

For production (matching the live device flags):

```bash
sudo python3 /home/ntableman/new-panel/main.py
```

Common first-run flags:

| Flag | When to use |
|---|---|
| `--led-gpio-mapping=adafruit-hat` | Adafruit RGB Matrix HAT |
| `--led-rows=64 --led-cols=64` | 64×64 panels |
| `--led-chain=2` | Two panels daisy-chained |
| `--led-slowdown-gpio=2` | Pi 4 default; increase to 3–4 for garbled output |
| `--led-no-hardware-pulse` | Only if `snd_bcm2835` audio module is loaded |
| `--led-limit-refresh=60` | Cap refresh for stable frame timing |
| `--led-no-busy-waiting` | Free CPU when refresh rate is limited |

For best latency, pin the parent process to core 2 as well:

```bash
sudo taskset -c 2 chrt -f 99 python3 main.py
```

---

## Systemd Service

The live device runs `rgb-panel.service`. Install it on a new device:

```bash
sudo cp rgb-panel.service.new /etc/systemd/system/rgb-panel.service
sudo systemctl daemon-reload
sudo systemctl enable rgb-panel
sudo systemctl start rgb-panel
```

The service definition (`rgb-panel.service.new` in the home directory):

```ini
[Unit]
Description=RGB LED Panel Display
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/ntableman/new-panel/main.py
WorkingDirectory=/home/ntableman/new-panel
User=root
Restart=always
RestartSec=5
RuntimeMaxSec=24h        # process is restarted once per day
StandardOutput=journal
StandardError=inherit

[Install]
WantedBy=multi-user.target
```

Check status and logs:

```bash
systemctl status rgb-panel
journalctl -u rgb-panel -f          # follow live logs
journalctl -u rgb-panel --since today
```

---

## Real-Time Kernel (Optional)

The live device runs the standard `PREEMPT` kernel. For the lowest possible
refresh jitter — particularly on SPWM displays or when not using the hardware
PWM pin — a full `PREEMPT_RT` kernel is recommended.

Prebuilt RT kernel tarballs for Pi 4 / 3 / Zero 2W are included in
`RT-kernel/` (kernel version **6.12.47-rt**, Trixie 64-bit):

```bash
# Copy tarballs to the Pi first, then on the Pi:
tar -xzf /tmp/raspberry_kernel_rt_trixie*boot.tar.gz -C /boot/firmware
tar -xzf /tmp/raspberry_kernel_rt_trixie*root.tar.gz -C /

# Verify after reboot
uname -a
# Expected: Linux ... 6.12.47-rt-v8+ #1 SMP PREEMPT_RT ...
```

See `RT-kernel/README.md` for cross-compilation instructions if you need to
build your own kernel for a different version.

---

## Development Workflow

Changes flow through three locations. Always follow this order:

```
1. Edit on Mac (local dev repo)
        ↓  git commit + git push origin master
2. GitHub fork (disruptivepatternmaterial/rpi-rgb-led-matrix)
        ↓  git pull + make + systemctl restart
3. Pi device (~/rpi-rgb-led-matrix)
```

### Step 1 — Commit and push from your Mac

```bash
cd /path/to/rpi-rgb-led-matrix   # local dev repo

# One-time: use SSH for GitHub pushes (no HTTPS username prompt).
git remote set-url origin git@github.com:disruptivepatternmaterial/rpi-rgb-led-matrix.git

git add <changed files>
git commit -m "your message"
git push origin master            # pushes to your GitHub fork
```

If `git push` asks for a GitHub username/password, the remote is still HTTPS.
Re-run the `git remote set-url ...` command above and push again.

### If push is rejected (`non-fast-forward`)

This means `origin/master` moved ahead and your local branch needs a rebase.

```bash
git pull --rebase origin master
```

If there are conflicts:

```bash
git status                         # see conflicted files
# edit files and resolve conflict markers
git add <resolved files>
GIT_EDITOR=true git rebase --continue
```

Repeat until the rebase completes, then:

```bash
git push origin master
```

If you need to bail out and return to pre-rebase state:

```bash
git rebase --abort
```

### Step 2 — Deploy to the Pi

Either run the deploy script from your Mac:

```bash
./deploy.sh                       # default: ntableman@192.168.50.183
# or: ./deploy.sh user@host
```

Or SSH in and run it manually:

```bash
ssh ntableman@192.168.50.183

# On the Pi:
cd ~/rpi-rgb-led-matrix
git pull origin master
make -j$(nproc)
sudo make install-python
sudo systemctl restart rgb-panel
systemctl status rgb-panel
```

Quick post-deploy health check from your Mac:

```bash
ssh ntableman@192.168.50.183 "systemctl status rgb-panel --no-pager | head -20"
```

### Step 3 — Keeping in sync with upstream (hzeller)

The upstream repo (`hzeller/rpi-rgb-led-matrix`) receives regular updates.
Pull them into your fork periodically:

```bash
# On your Mac
git fetch upstream
git merge upstream/master         # or: git rebase upstream/master
git push origin master            # update your fork on GitHub
# Then deploy to the Pi as above
```

### Fast return checklist (copy/paste later)

```bash
cd /path/to/rpi-rgb-led-matrix
git status -sb
git pull --rebase origin master

# ... make changes ...
git add <files>
git commit -m "message"
git push origin master
./deploy.sh
ssh ntableman@192.168.50.183 "systemctl status rgb-panel --no-pager | head -20"
```

---

## CI / GitHub Actions

The workflow (`.github/workflows/c-cpp.yml`) runs on `ubuntu-24.04` and only
verifies compilation — it does **not** execute binaries (no Pi hardware in CI).
It tests against both `cython3` and `cython3-legacy` packages.

To replicate locally:

```bash
# Regenerate Cython C++ sources
make -B -C bindings/python/rgbmatrix

# Full build
make -j$(nproc)
```

---

## New Device Setup

Full procedure from a fresh Debian Trixie 64-bit lite image:

```bash
# 1. System dependencies
sudo apt-get update && sudo apt-get install -y \
    python3-dev python3-pip build-essential cmake git \
    libfreetype6-dev libjpeg-dev libopenjp2-7-dev \
    libtiff5-dev libwebp-dev zlib1g-dev cython3

# 2. Clone and build the matrix library
git clone https://github.com/hzeller/rpi-rgb-led-matrix.git
cd rpi-rgb-led-matrix
make -j$(nproc)
sudo make install-python
cd ..

# 3. Clone and configure the application
git clone <new-panel-repo-url> new-panel
cd new-panel
pip3 install -r requirements.txt
cp config.template.json config.json
# Edit config.json — fill in weather API key, location, etc.
nano config.json

# 4. /boot/firmware/config.txt — add if not present
sudo bash -c 'echo "dtparam=audio=off" >> /boot/firmware/config.txt'

# 5. /boot/firmware/cmdline.txt — append isolcpus=3 to the single line
sudo sed -i 's/$/ isolcpus=3/' /boot/firmware/cmdline.txt

# 6. Install systemd service
sudo cp rgb-panel.service.new /etc/systemd/system/rgb-panel.service
sudo systemctl daemon-reload
sudo systemctl enable rgb-panel

# 7. Reboot and verify
sudo reboot
# After reboot:
systemctl status rgb-panel
```

---

## Release Checklist

1. **Test on Pi 4 hardware.** Run `demo`, `led-image-viewer`, and `new-panel/main.py`.
2. **Confirm `isolcpus=3` and `audio=off`** are set on target device.
3. **Verify Python binding version.** `pip3 show rgbmatrix` should match expected date tag.
4. **Clean build.** `make clean && make -j$(nproc)` to catch stale artifact issues.
5. **Tag the release.**
   ```bash
   git tag v<MAJOR>.<MINOR>.<PATCH>
   git push origin v<MAJOR>.<MINOR>.<PATCH>
   ```
6. **Create GitHub Release.** Attach `lib/librgbmatrix.a`, `lib/librgbmatrix.so.1`, and a changelog entry.
7. **Deploy to device.**
   ```bash
   # On the Pi
   cd ~/rpi-rgb-led-matrix
   git pull
   make -j$(nproc)
   sudo make install-python
   sudo systemctl restart rgb-panel
   systemctl status rgb-panel
   ```

---

## Troubleshooting

**Display shows garbage / random pixels**
Add or increase `--led-slowdown-gpio`. The Pi 4 default is 2; try 3 or 4 for
long cables or slow panels.

**`snd_bcm2835` conflict / program exits at startup**
Confirm `dtparam=audio=off` is in `/boot/firmware/config.txt` and reboot.
Alternatively use `--led-no-hardware-pulse` (increases colour flicker).

**`Must run as root` error**
Prepend `sudo`. `/dev/mem` access requires root for GPIO and PWM registers.

**Flickering / unstable refresh**
- Confirm `isolcpus=3` is in `cmdline.txt` (`cat /sys/devices/system/cpu/isolated` should show `3`).
- Run with `--led-show-refresh` to measure worst-case frame time, then lock it with `--led-limit-refresh=<Hz>`.
- Consider the RT kernel in `RT-kernel/` for the lowest jitter.

**`ImportError` for `rgbmatrix` in Python**
Run `sudo make install-python` from the repo root, or add `bindings/python` to
`PYTHONPATH`.

**Service not starting after reboot**
Check `journalctl -u rgb-panel -b` for the boot log. Common causes: missing
`config.json`, wrong working directory, or `rgbmatrix` binding not installed
system-wide.
