# SIMUX — Build Log & Handbook

> **Goal:** A tiny C‑friendly GNU/Linux you build yourself, bootable in QEMU. Minimal, fast, and perfect for learning.

---

## Table of Contents

* [Vision](#vision)
* [Repo Setup](#repo-setup)
* [Host Prerequisites](#host-prerequisites)
* [Conventions](#conventions)
* [Milestone 0 — Prep the Build VM](#milestone-0--prep-the-build-vm)
* [Milestone 1 — Kernel + BusyBox initramfs](#milestone-1--kernel--busybox-initramfs)
* [Milestone 2 — BusyBox on musl + real init](#milestone-2--busybox-on-musl--real-init)
* [Milestone 3 — Real RootFS on Disk Image](#milestone-3--real-rootfs-on-disk-image)
* [Milestone 4 — Turn SIMUX into a C Dev Box](#milestone-4--turn-simux-into-a-c-dev-box)
* [Milestone 5 — Developer Polish](#milestone-5--developer-polish)
* [Stretch Goals](#stretch-goals)
* [Troubleshooting](#troubleshooting)
* [Cheat‑Sheet: Remember that…](#cheat-sheet-remember-that)
* [Learning bullets](#learning-bullets)
* [Changelog](#changelog)

---

## Vision

**SIMUX** is a lightweight, study‑first GNU/Linux. The focus is:

* Understand the boot flow (firmware → kernel → initramfs → init → userspace).
* Practice **C** with real OS primitives (syscalls, signals, procfs, ptrace…).
* Keep the system **small, reproducible, and scriptable**.

---

## Repo Setup

```bash
# Create repo skeleton
mkdir -p simux/{build,docs,rootfs-overlay,scripts}
cd simux

# Initialize Git
git init
cat > .gitignore << 'EOF'
# build outputs
build/*
*.img
*.cpio.gz
*.tar.*
*.xz
*.bz2
*.gz
*.zip
# editor
*.swp
.DS_Store
EOF

git add .
git commit -m "chore: bootstrap SIMUX repo skeleton"
```

**Suggested structure**

```
simux/
  build/              # sources and artifacts (kernel, busybox, toolchains)
  docs/               # notes, references, logs (this file lives here)
  rootfs-overlay/     # files to overlay onto rootfs (etc/, banners, scripts)
  scripts/            # repeatable build steps (bash)
```

> **Remember:** Automate every step you repeat twice.

---

## Host Prerequisites

> Build inside a Linux VM (Ubuntu/Debian or Arch). These packages give you toolchain + QEMU.

**Debian/Ubuntu**

```bash
sudo apt update
sudo apt install -y build-essential git wget curl bc bison flex \
  libelf-dev libssl-dev libncurses-dev \
  qemu-system-x86 cpio xz-utils
```

**Arch**

```bash
sudo pacman -S --needed base-devel git wget curl bc bison flex \
  libelf openssl ncurses qemu cpio xz
```

---

## Conventions

* Workdir: `~/simux` unless noted.
* Kernel: Linux **6.10.x** (adjust as needed).
* Console: serial (`console=ttyS0`) for clean QEMU logs.

---

## Milestone 0 — Prep the Build VM

**Outcome:** Clean environment ready to build.

**Steps**

1. Install prerequisites (above).
2. Create folders: `build/`, `scripts/`, `rootfs-overlay/`.
3. Commit the baseline to Git.

**Verification**

* `qemu-system-x86_64 --version` works.
* `gcc --version` works.

---

## Milestone 1 — Kernel + BusyBox initramfs

**Outcome:** Boot your own kernel into a BusyBox shell from RAM.

### 1. Download sources

```bash
cd ~/simux/build
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.10.9.tar.xz
wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2

tar xf linux-6.10.9.tar.xz
tar xf busybox-1.36.1.tar.bz2
```

### 2. Build the kernel

```bash
cd linux-6.10.9
make defconfig
make -j"$(nproc)"       # outputs arch/x86/boot/bzImage
cd ..
```

### 3. Build BusyBox (static)

```bash
cd busybox-1.36.1
make defconfig
# enable static linking
sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
make -j"$(nproc)"
make CONFIG_PREFIX=../rootfs install
cd ..
```

### 4. Create initramfs with a minimal /init

```bash
mkdir -p rootfs/{proc,sys,dev,etc}
cat > rootfs/init << 'SH'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
echo "Welcome to SIMUX (initramfs)"
exec /bin/sh
SH
chmod +x rootfs/init

( cd rootfs && find . | cpio -H newc -o | gzip -9 ) > initramfs.cpio.gz
```

### 5. Boot in QEMU

```bash
qemu-system-x86_64 \
  -kernel linux-6.10.9/arch/x86/boot/bzImage \
  -initrd initramfs.cpio.gz \
  -nographic -append "console=ttyS0"
```

**Verification**

* You get a shell prompt.
* `ls /proc /sys` shows mounted pseudo filesystems.

**Log / Commit**

* Commit `scripts/` if you turned these into helpers.

---

## Milestone 2 — BusyBox on musl + real init

**Outcome:** Switch libc to **musl** (smaller, simpler) and hand control to BusyBox **init**.

### 1. Install musl tool

```bash
# Debian/Ubuntu
sudo apt install -y musl musl-tools
```

### 2. Rebuild BusyBox against musl

```bash
cd ~/simux/build/busybox-1.36.1
make distclean && make defconfig
sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
make CC=musl-gcc -j"$(nproc)"
make CONFIG_PREFIX=../rootfs-musl install
```

### 3. Set up BusyBox init

```bash
mkdir -p ../rootfs-musl/{etc,dev,proc,sys}
cat > ../rootfs-musl/etc/inittab << 'EOF'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
ttyS0::respawn:/bin/ash
::ctrlaltdel:/bin/umount -a -r
EOF

cat > ../rootfs-musl/init << 'SH'
#!/bin/sh
exec /sbin/init
SH
chmod +x ../rootfs-musl/init

( cd ../rootfs-musl && find . | cpio -H newc -o | gzip -9 ) > ../initramfs-musl.cpio.gz
```

### 4. Boot

```bash
cd ..
qemu-system-x86_64 \
  -kernel linux-6.10.9/arch/x86/boot/bzImage \
  -initrd initramfs-musl.cpio.gz \
  -nographic -append "console=ttyS0"
```

**Verification**

* You see `ash` respawn on `ttyS0`.

---

## Milestone 3 — Real RootFS on Disk Image

**Outcome:** Persistent root filesystem (ext4) on a virtual disk.

### 1. Create and partition disk

```bash
cd ~/simux/build
dd if=/dev/zero of=simux.img bs=1M count=1024
parted -s simux.img mklabel msdos
parted -s simux.img mkpart primary ext4 1MiB 100%
```

### 2. Format, mount, populate

```bash
LOOP=$(sudo losetup -f --show -P simux.img)
sudo mkfs.ext4 ${LOOP}p1
mkdir -p mnt
sudo mount ${LOOP}p1 mnt

# seed with musl BusyBox root
sudo cp -a rootfs-musl/* mnt/

# minimal /etc/passwd (no password for root yet)
echo "root::0:0:root:/root:/bin/ash" | sudo tee mnt/etc/passwd >/dev/null

sudo umount mnt
sudo losetup -d "$LOOP"
```

### 3. Boot from disk rootfs

```bash
qemu-system-x86_64 \
  -kernel linux-6.10.9/arch/x86/boot/bzImage \
  -drive file=simux.img,format=raw,if=virtio \
  -append "root=/dev/vda1 console=ttyS0 init=/sbin/init" \
  -nographic
```

**Verification**

* You can create a file in `/root`, reboot, and it persists.

---

## Milestone 4 — Turn SIMUX into a C Dev Box

**Outcome:** A tiny but usable dev environment.

### Options for toolchain

* **Quick**: build **tcc** (tiny C compiler) statically.
* **Standard**: build **gcc**/**clang** (larger; full feature set).
* **Buildroot assist**: generate a musl toolchain + rootfs, then copy needed parts.

### Suggested order

1. Add `make`, `pkg-config`, `git` (static where possible).
2. Build `tcc` first (fast feedback), then graduate to `gcc`.
3. Add `gdb`, `strace`, `perf` (debugging & perf).
   *Note:* `valgrind` is simpler on glibc; consider dual‑libc later.

### C practice tasks

* Write a **tiny PID 1** in C that:

  * mounts `/proc` and `/sys`
  * spawns `/bin/ash` on `ttyS0`
  * reaps zombies (`waitpid` loop)
* Write a **toy init** supporting `/etc/inittab`‑like entries.
* Write a **mini ps** using `/proc`.
* Write a **signal playground** (SIGCHLD, SIGTERM handling).

---

## Milestone 5 — Developer Polish

**Outcome:** Comfortable daily driver for coding inside QEMU.

* Add **dropbear** (tiny SSH) → dev via `ssh -p <port>`.
* Add **vim/neovim**, **tmux**; drop dotfiles in `rootfs-overlay/`.
* Brand it: `/etc/issue`, MOTD, hostname = `simux`.
* Optional graphics: `kmscon` → sway/i3 later (keep base small first).

---

## Stretch Goals

* Replace BusyBox init with **runit** or **s6**.
* Implement a **simple package format** (tar + manifest + post‑install hook).
* Namespaces & seccomp demos (write a tiny `chroot`/`pivot_root`/`clone` tool in C).
* Create an **installer script** that lays SIMUX onto a disk.

---

## Troubleshooting

* **Kernel panic: unable to mount root** → check `root=/dev/vda1` and that the virtio block driver is built‑in (not module) in your kernel config.
* **No console output** → ensure `-nographic` and `console=ttyS0` kernel arg.
* **PID 1 exited** → never `exit(0)` from init; exec a shell or loop.
* **Filesystem perms weird when copying** → use `sudo cp -a` to preserve modes.

---

## Cheat‑Sheet: Remember that…

* **PID 1 never dies** — if it exits, kernel panics.
* **Static BusyBox** is your parachute when libs are broken.
* `console=ttyS0` + `-nographic` = fast, clean serial logs in QEMU.
* **musl** keeps things tiny; **glibc** maximizes compatibility.
* Keep a **known‑good boot** (old `bzImage` + initramfs) to roll back quickly.

---

## Learning bullets

* **C & Syscalls**: `fork/execve/waitpid`, `open/read/write/ioctl`, `ptrace`, `inotify`.
* **Boot & FS**: initramfs vs rootfs, `pivot_root`, `/proc` & `/sys` internals.
* **Toolchain**: musl vs glibc, static vs dynamic linking, ELF introspection (`readelf`, `ldd`).
* **Debug/Perf**: `strace`, `ltrace`, `perf`, `ftrace`.
* **Packaging**: reproducible builds, checksums, signing basics.

---

## Changelog

* **Day 0:** Repo skeleton, prerequisites, Milestone 1 plan.

---

### Next Actions

* [ ] Run Milestone 0–1 exactly once and paste boot logs into `docs/boot-logs.md`.
* [ ] Turn the Milestone 1 commands into `scripts/build_kernel.sh`, `scripts/build_initramfs.sh`.
* [ ] Commit artifacts list (don’t check in large blobs).
* [ ] Plan tiny C `init` (Milestone 4) and add to `src/`.
