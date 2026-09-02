# CI branch

This branch holds nothing but build automation. **The kernel source is on the `lineage-*`
branches**, one per LineageOS release; the fork's own work lands on
[`lineage-23.2-ReSukiSU`](../../tree/lineage-23.2-ReSukiSU).

```sh
git clone -b lineage-23.2 https://github.com/playday3008/android_kernel_samsung_sm7325
```

## Why this is the default branch

GitHub only offers a `workflow_dispatch` trigger for workflows that exist on the default
branch. Keeping the workflow here, and making `ci` the default, means no kernel branch
carries a `.github` directory that would have to survive every rebase onto LineageOS.

The kernel branch to build is therefore a workflow *input*, not the run ref. Runs always
execute from `ci`.

## Running a build

Actions tab -> "build boot.img" -> Run workflow, or:

```sh
gh workflow run 'build boot.img' --ref ci \
  -f refs=lineage-23.2-ReSukiSU,sukisu-builtin \
  -f devices=a52sxq \
  -f release=false
```

| Input | Meaning |
| --- | --- |
| `refs` | kernel branches, tags or shas, comma or newline separated |
| `devices` | `a52sxq`, `a73xq`, `m52xq` |
| `release` | also publish each leg as a prerelease |

Every ref is built against every device, each combination as its own matrix leg with
`fail-fast: false`.

## What a leg produces

- `boot.img` - flashable directly; a52sxq needs neither `vendor_boot` nor `dtbo` reflashed
  for kernel-only changes
- `AnyKernel3-<device>-<release>.zip`
- `vendor-modules.tar.gz` - unpacks to `lib/modules/`, for `/vendor/lib/modules`; optional,
  since `CONFIG_MODVERSIONS` lets stock modules load against a self-built kernel
- `Image` and `config`

## Layout

```text
.github/workflows/build-boot.yml   dispatch inputs, matrix, artifact upload
scripts/plan.py                    refs x devices -> matrix JSON
scripts/build.sh                   defconfig + make for one device
scripts/pack_boot.py               read/write boot images with a v3 header
scripts/pack_modules.sh            vendor-modules.tar.gz
scripts/pack_anykernel.sh          AnyKernel3 zip
devices/<device>/meta.env          defconfig, boot header fields, module renames
devices/<device>/ramdisk.img       stock ramdisk, reused verbatim
devices/<device>/modules.load      ROM load order
```

## Packing

The a52sxq boot partition uses a version 3 header with no AVB footer, and the ramdisk is
reused unchanged, so packing is just a header plus two page-aligned blobs. That is why
`pack_boot.py` exists instead of a `magiskboot` and `avbtool` dependency, and why the only
binary asset needed is a 1.7 MB ramdisk rather than a 46 MB base image.

Feeding a locally built `Image` through it reproduces the corresponding hand-packed image
byte for byte.

## Adding a device

Drop a `devices/<codename>/` directory containing at least `meta.env` with `DEFCONFIG` and
`ANYKERNEL_DEVICES`. Without a `ramdisk.img` the leg still builds and still produces an
AnyKernel3 zip, but the `boot.img` step is skipped with a notice; without a `modules.load`
the load order is derived from `depmod` instead of the ROM's. The workflow needs no change.

`a73xq` and `m52xq` are in that partial state today.

## Toolchain

Builds use AOSP `clang-r530567`, mirrored as a release asset
([`toolchain-clang-r530567`](../../releases/tag/toolchain-clang-r530567)) and cached
between runs. The upstream gitiles `+archive` tarball is not used directly because it has
no resume support and regularly stalls just short of the end.
