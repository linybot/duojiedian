#!/usr/bin/env python3
"""统一修改仓库内所有版本号占位，避免手工漏改导致 CI --locked 失败。

用法:
    python3 scripts/bump_version.py 1.5.8 [--build 76]

会更新:
    - Cargo.toml / libs/portable/Cargo.toml 的 package version
    - Cargo.lock 中 rustdesk 与 rustdesk-portable-packer 两个 workspace 包版本
    - flutter/pubspec.yaml 的 version（含 build number）
    - .github/workflows/*.yml 中的 VERSION 环境变量
    - appimage/AppImageBuilder-*.yml 的 version 字段
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CRATES = ["rustdesk", "rustdesk-portable-packer"]


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def write(p: Path, s: str) -> None:
    p.write_text(s, encoding="utf-8")
    print("updated", p.relative_to(ROOT))


def bump_cargo_toml(version: str) -> None:
    for rel in ["Cargo.toml", "libs/portable/Cargo.toml"]:
        p = ROOT / rel
        s = read(p)
        s2 = re.sub(r'(?m)^version\s*=\s*"[^"]+"', f'version = "{version}"', s, count=1)
        if s2 == s:
            print("skip (no change)", rel)
        else:
            write(p, s2)


def bump_cargo_lock(version: str) -> None:
    p = ROOT / "Cargo.lock"
    s = read(p)
    for crate in CRATES:
        pattern = re.compile(
            r'(\[\[package\]\]\nname = "%s"\nversion = ")[^"]+(")' % re.escape(crate)
        )
        s, n = pattern.subn(lambda m: m.group(1) + version + m.group(2), s)
        if n == 0:
            print(f"WARN: {crate} not found in Cargo.lock")
        else:
            print(f"Cargo.lock: {crate} -> {version}")
    write(p, s)


def bump_pubspec(version: str, build: int) -> None:
    p = ROOT / "flutter/pubspec.yaml"
    s = read(p)
    s2 = re.sub(r'(?m)^version:\s*\S+', f"version: {version}+{build}", s, count=1)
    write(p, s2)


def bump_workflows(version: str) -> None:
    for p in sorted((ROOT / ".github/workflows").glob("*.yml")):
        s = read(p)
        s2 = re.sub(r'(?m)^(\s*VERSION:\s*)"[^"]+"', lambda m: m.group(1) + f'"{version}"', s)
        if s2 != s:
            write(p, s2)


def bump_appimage(version: str) -> None:
    for p in sorted((ROOT / "appimage").glob("AppImageBuilder-*.yml")):
        s = read(p)
        s2 = re.sub(r'(?m)^(\s*version:\s*)\S+', f"\\g<1>{version}", s)
        if s2 != s:
            write(p, s2)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    version = sys.argv[1]
    build = 0
    if "--build" in sys.argv:
        build = int(sys.argv[sys.argv.index("--build") + 1])
    else:
        p = ROOT / "flutter/pubspec.yaml"
        m = re.search(r"(?m)^version:\s*\S+\+(\d+)", read(p))
        build = (int(m.group(1)) + 1) if m else 0
    bump_cargo_toml(version)
    bump_cargo_lock(version)
    bump_pubspec(version, build)
    bump_workflows(version)
    bump_appimage(version)
    print(f"done: {version}+{build}")


if __name__ == "__main__":
    main()
