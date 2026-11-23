#!/usr/bin/env python3
"""Build the JPEG XL command tools from the pinned sources and macOS SDK."""
import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

import build

here = Path(__file__).resolve().parent
manifest = here / "jxl-sources.json"
packages = json.loads(manifest.read_text())
cmake = shutil.which("cmake") or "/opt/homebrew/bin/cmake"


def main():
    build.archives.mkdir(parents=True, exist_ok=True)
    fingerprint = hashlib.sha256(Path(__file__).read_bytes() + manifest.read_bytes() + (here / "build.py").read_bytes()).hexdigest()[:16]
    root = build.cache / ("jxl-" + fingerprint)
    root.mkdir(parents=True, exist_ok=True)
    with (root / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        output = root / "output"
        if not (output / "JPEG XL Sources.zip").is_file():
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
                archives = dict(executor.map(build.download, packages.items()))
            src = root / "source"
            for name, archive in archives.items():
                dst = src if name == "jxl" else src / "third_party" / name
                dst.mkdir(parents=True, exist_ok=True)
                subprocess.run(["/usr/bin/tar", "-xf", archive, "-C", dst, "--strip-components", "1"], check=True)
            env = {**os.environ, "MACOSX_DEPLOYMENT_TARGET": "27.0", "CMAKE_POLICY_VERSION_MINIMUM": "3.5", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
            prefix = root / "install"
            # libjxl's tools use libpng and libjpeg for image interchange. Link static archives.
            build.cmake(src / "third_party/libpng", prefix, env, ["-DPNG_FRAMEWORK=OFF", "-DPNG_SHARED=OFF", "-DPNG_STATIC=ON", "-DPNG_TESTS=OFF", "-DPNG_TOOLS=OFF"])
            build.cmake(src / "third_party/libjpeg-turbo", prefix, env, ["-DCMAKE_INSTALL_LIBDIR=" + str(prefix / "lib"), "-DENABLE_SHARED=OFF", "-DENABLE_STATIC=ON", "-DWITH_TURBOJPEG=OFF"])
            args = ["-DCMAKE_BUILD_TYPE=Release", "-DBUILD_SHARED_LIBS=OFF", "-DBUILD_TESTING=OFF",
                    "-DCMAKE_PREFIX_PATH=" + str(prefix), "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local",
                    "-DJPEGXL_BUNDLE_LIBPNG=OFF", "-DJPEGXL_ENABLE_SKCMS=ON", "-DJPEGXL_ENABLE_OPENEXR=OFF",
                    "-DJPEGXL_ENABLE_SJPEG=OFF", "-DJPEGXL_ENABLE_JNI=OFF", "-DJPEGXL_ENABLE_BENCHMARK=OFF",
                    "-DJPEGXL_ENABLE_DOXYGEN=OFF", "-DJPEGXL_ENABLE_MANPAGES=OFF", "-DJPEGXL_ENABLE_EXAMPLES=OFF"]
            build.run([cmake, "-S", src, "-B", root / "build", *args], root, env)
            build.run([cmake, "--build", root / "build", "--target", "cjxl", "djxl", "-j", build.jobs], root, env)
            output.mkdir(exist_ok=True)
            for name in ("cjxl", "djxl"):
                binary = root / "build/tools" / name
                deps = subprocess.check_output(["/usr/bin/otool", "-L", binary], text=True).splitlines()[1:]
                if any(not line.strip().startswith(("/usr/lib/", "/System/Library/")) for line in deps):
                    raise ValueError(name + " has a non-system runtime dependency")
                shutil.copy2(binary, output / name)
            temporary = output / "source.zip"
            with zipfile.ZipFile(temporary, "w") as bundle:
                for archive in archives.values():
                    bundle.write(archive, "archives/" + archive.name)
                for name in ("build.py", "build_jxl.py", "sources.json", "jxl-sources.json"):
                    bundle.write(here / name, name)
            temporary.replace(output / "JPEG XL Sources.zip")
        tools = build.cache / "tools"
        tools.mkdir(exist_ok=True)
        for name in ("cjxl", "djxl", "JPEG XL Sources.zip"):
            shutil.copy2(output / name, tools / name)


if __name__ == "__main__":
    main()
