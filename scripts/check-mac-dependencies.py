#!/usr/bin/env python3
"""Compare the Swift, bundled native codec and installer pins with stable upstream releases."""
import json
from pathlib import Path
import re
import subprocess
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / "apps/macos"


def fetch(url):
    request = Request(url, headers={"User-Agent": "Cloakyard-Mac-release-check"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def github(repo):
    return json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))["tag_name"].removeprefix("v")


def latest_version(versions):
    return max(versions, key=lambda v: tuple(map(int, v.split("."))))


def github_tags(repo):
    """Include peeled annotated tags so a pinned commit can be matched to its release."""
    lines = subprocess.check_output(["git", "ls-remote", "--tags", f"https://github.com/{repo}.git"],
                                    text=True, timeout=60).splitlines()
    tags = {}
    for line in lines:
        sha, ref = line.split()
        match = re.fullmatch(r"refs/tags/v?(\d+(?:[._]\d+)+)(?:\^\{\})?", ref)
        if match:
            tags.setdefault(match[1].replace("_", "."), set()).add(sha)
    return tags


def release_page(url, pattern):
    return latest_version(re.findall(pattern, fetch(url).decode(), re.IGNORECASE))


def codec_pins():
    folder = MAC / "scripts/codecs"
    sources = json.loads((folder / "sources.json").read_text())
    versions = {
        "pkgconf": github("pkgconf/pkgconf").removeprefix("pkgconf-"),
        "lame": release_page("https://lame.sourceforge.io/download.php", r"current release version of LAME is ([\d.]+)"),
        "opus": release_page("https://opus-codec.org/downloads/", r"libopus (\d+(?:\.\d+)+)"),
        "libvpx": latest_version(github_tags("webmproject/libvpx")),
        "svt-av1": latest_version(github_tags("AOMediaCodec/SVT-AV1")),
        "x265": github("Multicorewareinc/x265"),
        "ffmpeg": release_page("https://ffmpeg.org/releases/", r'href="ffmpeg-(\d+(?:\.\d+)+)\.tar\.xz"'),
    }
    for name, (url, _) in sources.items():
        match = re.search(r"([0-9]+(?:\.[0-9]+)+)\.tar\.(?:xz|bz2|gz)$", url)
        if not match:
            raise ValueError(f"Unrecognized {name} release archive: {url}")
        yield name, match[1], versions[name]

    for name, (url, _) in json.loads((folder / "jxl-sources.json").read_text()).items():
        match = re.fullmatch(r"https://github.com/([\w.-]+/[\w.-]+)/archive/([\w.-]+)\.tar\.gz", url)
        if not match:
            raise ValueError(f"Unrecognized {name} GitHub archive: {url}")
        repo, rev = match.groups()
        tags = github_tags(repo)
        current = next((tag for tag, shas in tags.items() if rev in shas), rev.removeprefix("v"))
        yield name, current, latest_version(tags)


def main():
    spec = (MAC / "project.yml").read_text()
    sparkle = re.search(r"\n  Sparkle:\n[^\n]+\n    exactVersion: ([\d.]+)", spec)[1]
    pins = [("Sparkle", sparkle, github("sparkle-project/Sparkle"))]
    for lock in sorted((MAC / "Packages").glob("*/Package.resolved")):
        for package in json.loads(lock.read_text())["pins"]:
            repo = package["location"].removeprefix("https://github.com/").removesuffix(".git")
            pins.append((package["identity"], package["state"]["version"], github(repo)))
    pins.extend(codec_pins())
    for line in (MAC / "scripts/dmg/requirements.txt").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        name, version = line.split()[0].split("==")
        upstream = json.loads(fetch(f"https://pypi.org/pypi/{name}/json"))["info"]["version"]
        pins.append((name, version, upstream))
    for name, current, latest in pins:
        print(f"{name}: {current} (stable upstream {latest})")
    return int(any(current != latest for _, current, latest in pins))


if __name__ == "__main__":
    raise SystemExit(main())
