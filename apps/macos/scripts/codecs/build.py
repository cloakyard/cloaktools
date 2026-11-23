#!/usr/bin/env python3
"""Build local-file-only, arm64 codec helpers. All source archives are checked before extraction."""
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

here = Path(__file__).resolve().parent
manifest = here / "sources.json"
packages = json.loads(manifest.read_text())
cache = here.parents[1] / "build" / "MediaCodecs"
archives = (here / "archives") if (here / "archives").is_dir() else cache / "archives"
jobs = str(min(8, os.cpu_count() or 2))


def run(args, cwd, env):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


def download(entry):
    name, (url, checksum) = entry
    archive = archives / url.split("/")[-1]
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
        partial = archive.with_suffix(".download")
        subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
                        "--proto", "=https", "--proto-redir", "=https", "--output", partial, url], check=True)
        if hashlib.sha256(partial.read_bytes()).hexdigest() != checksum:
            raise ValueError("Source checksum mismatch for " + name)
        partial.replace(archive)
    return name, archive


def make(source, prefix, env, arguments=()):
    run([source / "configure", "--prefix=" + str(prefix), *arguments], source, env)
    run(["make", "-j" + jobs], source, env)
    run(["make", "install"], source, env)


def cmake(source, prefix, env, arguments):
    binary = shutil.which("cmake") or "/opt/homebrew/bin/cmake"
    build = source / "build-cloaktools"
    run([binary, "-S", source, "-B", build, "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=" + str(prefix),
         "-DCMAKE_INSTALL_LIBDIR=lib", "-DBUILD_SHARED_LIBS=OFF", *arguments], source, env)
    run([binary, "--build", build, "-j", jobs], source, env)
    run([binary, "--install", build], source, env)


def compile_package(name, source, prefix, env):
    static = ["--disable-shared", "--enable-static"]
    if name == "pkgconf":
        make(source, prefix, env, static)
        (prefix / "bin/pkg-config").symlink_to("pkgconf", target_is_directory=False)
    elif name == "lame":
        make(source, prefix, env, [*static, "--disable-frontend", "--disable-decoder"])
    elif name == "opus":
        cmake(source, prefix, env, ["-DOPUS_BUILD_PROGRAMS=OFF", "-DOPUS_BUILD_TESTING=OFF"])
    elif name == "libvpx":
        make(source, prefix, env, ["--target=arm64-darwin25-gcc", "--disable-examples", "--disable-tools",
                                   "--disable-unit-tests", "--disable-docs", "--enable-pic"])
    elif name == "svt-av1":
        cmake(source, prefix, env, ["-DBUILD_APPS=OFF", "-DBUILD_TESTING=OFF"])
    elif name == "x265":
        cmake(source / "source", prefix, env, ["-DENABLE_CLI=OFF", "-DENABLE_SHARED=OFF", "-DENABLE_ASSEMBLY=OFF",
                                               "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"])
    elif name == "ffmpeg":
        make(source, prefix, env, [
            "--disable-autodetect", "--disable-network", "--disable-doc", "--disable-debug", "--disable-ffplay",
            "--disable-avdevice", "--disable-everything", "--enable-ffmpeg", "--enable-ffprobe", "--enable-gpl",
            "--enable-libvpx", "--enable-libsvtav1", "--enable-libx265", "--enable-libmp3lame", "--enable-libopus",
            "--enable-videotoolbox", "--enable-audiotoolbox", "--enable-protocol=file",
            "--enable-demuxer=mov,matroska,avi,mpegvideo,mpegps,mp3,ogg,flac,wav,aiff,caf,gif",
            "--enable-muxer=mp4,matroska,webm,ogg,mp3,flac,wav,aiff,null,gif",
            "--enable-parser=h264,hevc,vp8,vp9,av1,mpegvideo,mpegaudio,opus,vorbis,flac,aac",
            "--enable-decoder=h264,hevc,av1,vp8,vp9,mpeg1video,mpeg2video,mpeg4,mjpeg,aac,mp3,opus,vorbis,flac,alac,gif,pcm*",
            "--enable-encoder=h264_videotoolbox,hevc_videotoolbox,libx265,libsvtav1,libvpx_vp9,libopus,libmp3lame,aac,flac,gif,pcm*",
            "--enable-filter=scale,crop,format,fps,transpose,hflip,vflip,setpts,atempo,aresample,asetnsamples,aformat,volume,volumedetect,loudnorm,buffer,buffersink,abuffer,abuffersink,null,anull,trim,atrim",
            "--enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb,extract_extradata",
            "--pkg-config=" + str(prefix / "bin/pkgconf"), "--pkg-config-flags=--static",
            "--extra-cflags=-I" + str(prefix / "include"), "--extra-ldflags=-L" + str(prefix / "lib"), "--extra-libs=-lc++"
        ])


def main():
    if os.uname().machine != "arm64":
        raise SystemExit("Build the native codec helpers on Apple silicon.")
    cache.mkdir(parents=True, exist_ok=True)
    archives.mkdir(parents=True, exist_ok=True)
    with (cache / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            sources = dict(executor.map(download, packages.items()))
        fingerprint = hashlib.sha256(Path(__file__).read_bytes() + manifest.read_bytes()).hexdigest()[:16]
        root = cache / fingerprint
        prefix = root / "install"
        prefix.mkdir(parents=True, exist_ok=True)
        env = {**os.environ, "MACOSX_DEPLOYMENT_TARGET": "27.0", "CC": "/usr/bin/clang", "CXX": "/usr/bin/clang++",
               "PATH": str(prefix / "bin") + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
               "PKG_CONFIG_LIBDIR": str(prefix / "lib/pkgconfig"), "PKG_CONFIG_PATH": ""}
        for name, archive in sources.items():
            stage = root / name
            done = stage / ".complete"
            if done.exists():
                continue
            stage.mkdir(exist_ok=True)
            subprocess.run(["/usr/bin/tar", "-xf", archive, "-C", stage], check=True)
            source = next(path for path in stage.iterdir() if path.is_dir())
            print("Building " + name, flush=True)
            compile_package(name, source, prefix, env)
            done.touch()
        output = cache / "tools"
        output.mkdir(exist_ok=True)
        for name in ("ffmpeg", "ffprobe"):
            binary = prefix / "bin" / name
            deps = subprocess.check_output(["/usr/bin/otool", "-L", binary], text=True).splitlines()[1:]
            if any(not line.strip().startswith(("/usr/lib/", "/System/Library/")) for line in deps):
                raise ValueError(name + " has a non-system runtime dependency")
            shutil.copy2(binary, output / name)
        encoders = subprocess.check_output([output / "ffmpeg", "-hide_banner", "-encoders"], text=True)
        for codec in ("libvpx-vp9", "libsvtav1", "libx265", "libmp3lame", "libopus", "hevc_videotoolbox"):
            if codec not in {line.split()[1] for line in encoders.splitlines() if len(line.split()) >= 2}:
                raise ValueError("Missing encoder: " + codec)
        # Keep corresponding sources and the build instructions with redistributed helpers.
        with zipfile.ZipFile(output / "Codec Sources.zip", "w") as bundle:
            for archive in sources.values():
                bundle.write(archive, "archives/" + archive.name)
            bundle.write(__file__, "build.py")
            bundle.write(manifest, "sources.json")


if __name__ == "__main__":
    main()
