#!/usr/bin/env python3
"""Expand the workflow's refs x devices inputs into a build matrix."""

import json
import os
import re
import sys

CI_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def split(value):
    seen = []
    for item in re.split(r"[,\s]+", value.strip()):
        if item and item not in seen:
            seen.append(item)
    return seen


def main():
    refs = split(sys.argv[1])
    devices = split(sys.argv[2])
    if not refs:
        sys.exit("no refs given")
    if not devices:
        sys.exit("no devices given")

    include = []
    for ref in refs:
        for device in devices:
            if not os.path.isfile(os.path.join(CI_ROOT, "devices", device, "meta.env")):
                sys.exit("unknown device %r" % device)
            include.append({
                "ref": ref,
                "device": device,
                "name": "%s / %s" % (device, ref),
                # artifact and tag names reject slashes
                "slug": "%s-%s" % (device, re.sub(r"[^A-Za-z0-9._-]", "-", ref)),
            })
    print(json.dumps({"include": include}))


if __name__ == "__main__":
    main()
