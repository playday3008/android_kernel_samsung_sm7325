#!/usr/bin/env python3
"""Read and write Android boot images with a version 3 header.

The a52sxq boot partition carries no AVB footer, so packing is just the header
followed by page-aligned kernel and ramdisk blobs.
"""

import argparse
import struct
import sys

MAGIC = b"ANDROID!"
PAGE_SIZE = 4096
HEADER_SIZE_V3 = 1580
CMDLINE_SIZE = 1536


def pack_os_version(version, patch_level):
    major, minor, patch = (int(x) for x in version.split("."))
    year, month = (int(x) for x in patch_level.split("-"))
    a = (major << 14) | (minor << 7) | patch
    b = ((year - 2000) << 4) | month
    return (a << 11) | b


def unpack_os_version(value):
    a, b = value >> 11, value & 0x7FF
    return (
        "%d.%d.%d" % ((a >> 14) & 0x7F, (a >> 7) & 0x7F, a & 0x7F),
        "%04d-%02d" % (2000 + ((b >> 4) & 0x7F), b & 0xF),
    )


def pad(size):
    return -size % PAGE_SIZE


def read_header(path):
    with open(path, "rb") as f:
        head = f.read(PAGE_SIZE)
    if head[:8] != MAGIC:
        sys.exit("%s: not an Android boot image" % path)
    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<IIII", head, 8)
    header_version, = struct.unpack_from("<I", head, 40)
    if header_version != 3:
        sys.exit("%s: header version %d, only 3 is supported" % (path, header_version))
    cmdline = head[44:44 + CMDLINE_SIZE].split(b"\0")[0].decode()
    return {
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "os_version": os_version,
        "header_size": header_size,
        "cmdline": cmdline,
    }


def cmd_info(args):
    h = read_header(args.image)
    version, patch = unpack_os_version(h["os_version"])
    print("header_version   3")
    print("kernel_size      %d" % h["kernel_size"])
    print("ramdisk_size     %d" % h["ramdisk_size"])
    print("os_version       %s" % version)
    print("os_patch_level   %s" % patch)
    print("header_size      %d" % h["header_size"])
    print("cmdline          %r" % h["cmdline"])


def cmd_unpack(args):
    h = read_header(args.image)
    with open(args.image, "rb") as f:
        f.seek(PAGE_SIZE)
        kernel = f.read(h["kernel_size"])
        f.seek(pad(h["kernel_size"]), 1)
        ramdisk = f.read(h["ramdisk_size"])
    if len(kernel) != h["kernel_size"] or len(ramdisk) != h["ramdisk_size"]:
        sys.exit("%s: truncated" % args.image)
    if args.kernel:
        open(args.kernel, "wb").write(kernel)
    if args.ramdisk:
        open(args.ramdisk, "wb").write(ramdisk)


def cmd_pack(args):
    kernel = open(args.kernel, "rb").read()
    ramdisk = open(args.ramdisk, "rb").read()
    cmdline = args.cmdline.encode()
    if len(cmdline) >= CMDLINE_SIZE:
        sys.exit("cmdline too long")

    header = bytearray(PAGE_SIZE)
    header[0:8] = MAGIC
    struct.pack_into(
        "<IIII", header, 8,
        len(kernel), len(ramdisk),
        pack_os_version(args.os_version, args.os_patch_level),
        HEADER_SIZE_V3,
    )
    struct.pack_into("<I", header, 40, 3)
    header[44:44 + len(cmdline)] = cmdline

    with open(args.out, "wb") as f:
        f.write(header)
        f.write(kernel)
        f.write(b"\0" * pad(len(kernel)))
        f.write(ramdisk)
        f.write(b"\0" * pad(len(ramdisk)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("info")
    p.add_argument("image")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("unpack")
    p.add_argument("image")
    p.add_argument("--kernel")
    p.add_argument("--ramdisk")
    p.set_defaults(func=cmd_unpack)

    p = sub.add_parser("pack")
    p.add_argument("--kernel", required=True)
    p.add_argument("--ramdisk", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--os-version", required=True)
    p.add_argument("--os-patch-level", required=True)
    p.add_argument("--cmdline", default="")
    p.set_defaults(func=cmd_pack)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
