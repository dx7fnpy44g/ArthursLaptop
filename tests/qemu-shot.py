#!/usr/bin/env python3
"""qemu-shot.py <monitor.sock> shot <out.png> | colors <out.png> | pixel <out.png> | react <before.png> <after.png> | key <name>

Talks to a QEMU monitor socket: take a screenshot as PNG (no dependencies), or send a key.
Used by qemu-install-test.sh to see what an installer that is stuck is showing.
"""
import socket
import struct
import sys
import tempfile
import time
import zlib


def monitor(sock_path, cmd, wait=1.5):
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock_path)
    s.settimeout(3)
    time.sleep(0.3)
    try:
        s.recv(65536)
    except OSError:
        pass
    s.send((cmd + "\n").encode())
    time.sleep(wait)
    s.close()


def ppm_to_png(ppm_path, png_path):
    with open(ppm_path, "rb") as f:
        data = f.read()
    # P6\n<w> <h>\n255\n<pixels>
    parts = data.split(b"\n", 3)
    assert parts[0] == b"P6", "not a P6 ppm"
    w, h = map(int, parts[1].split())
    pix = parts[3]
    raw = b"".join(b"\x00" + pix[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    with open(png_path, "wb") as f:
        f.write(png)


def describe(ppm_path):
    """Return 'colors=<distinct> top=<% of the most common colour> md5=<hash>'."""
    import collections
    import hashlib
    with open(ppm_path, "rb") as f:
        data = f.read()
    pix = data.split(b"\n", 3)[3]
    c = collections.Counter(zip(pix[0::3], pix[1::3], pix[2::3]))
    top = c.most_common(1)[0][1] * 100 // (len(pix) // 3)
    return "colors=%d top=%d md5=%s" % (len(c), top, hashlib.md5(pix).hexdigest()[:12])


def snap(sock, png):
    tmp = tempfile.mktemp(suffix=".ppm")
    monitor(sock, "screendump " + tmp, wait=1.0)
    ppm_to_png(tmp, png)
    with open(tmp, "rb") as f:
        return f.read().split(b"\n", 3)[3]


def react(sock, before_png, after_png):
    """Screenshot, press a key at once, screenshot again; report how much of the screen changed.
    The background gradient drifts by a few units per second; a shape from a key press changes
    >60 levels over thousands of pixels, so a 60-level threshold ignores the drift."""
    a = snap(sock, before_png)
    monitor(sock, "sendkey a", wait=0.4)
    b = snap(sock, after_png)
    n = len(a) // 3
    changed = sum(1 for i in range(0, 3 * n, 3)
                  if max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2])) > 60)
    return "changed=%.2f%%" % (changed * 100.0 / n)


if __name__ == "__main__":
    sock, action, arg = sys.argv[1:4]
    if action == "shot":
        tmp = tempfile.mktemp(suffix=".ppm")
        monitor(sock, "screendump " + tmp)
        ppm_to_png(tmp, arg)
    elif action == "colors":
        tmp = tempfile.mktemp(suffix=".ppm")
        monitor(sock, "screendump " + tmp)
        ppm_to_png(tmp, arg)
        print(describe(tmp))
    elif action == "pixel":
        # background colour at the top-left corner: the installer paints errors on RED
        tmp = tempfile.mktemp(suffix=".ppm")
        monitor(sock, "screendump " + tmp)
        ppm_to_png(tmp, arg)
        with open(tmp, "rb") as f:
            parts = f.read().split(b"\n", 3)
        w = int(parts[1].split()[0])
        off = (2 * w + 2) * 3
        print("rgb=%d,%d,%d" % tuple(parts[3][off:off + 3]))
    elif action == "react":
        print(react(sock, arg, sys.argv[4]))
    elif action == "key":
        monitor(sock, "sendkey " + arg)
    else:
        sys.exit("unknown action")
