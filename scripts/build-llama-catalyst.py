#!/usr/bin/env python3
"""Add a real arm64 Mac Catalyst slice to the CI llama XCFramework.

Run only on GitHub's Xcode runner. The existing release contains iOS slices,
but neither it nor upstream b10472 provides a Catalyst slice.
"""
import os
import pathlib
import plistlib
import shutil
import subprocess

assert os.environ.get("GITHUB_ACTIONS") == "true", "Build this dependency on GitHub, not the local Mac"
root = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(os.environ["RUNNER_TEMP"]) / "llama-catalyst-source"
subprocess.run(["git", "clone", "--depth", "1", "--branch", "b10472",
                "https://github.com/ggml-org/llama.cpp.git", str(source)], check=True)
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
flags = f"-target arm64-apple-ios17.0-macabi -isystem {sdk}/System/iOSSupport/usr/include -iframework {sdk}/System/iOSSupport/System/Library/Frameworks"
build = source / "build-catalyst"
subprocess.run([
    "cmake", "-S", str(source), "-B", str(build), "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_SYSTEM_NAME=Darwin",
    f"-DCMAKE_OSX_SYSROOT={sdk}", "-DCMAKE_OSX_ARCHITECTURES=arm64",
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=", f"-DCMAKE_C_FLAGS={flags}", f"-DCMAKE_CXX_FLAGS={flags}",
    f"-DCMAKE_OBJC_FLAGS={flags}", f"-DCMAKE_OBJCXX_FLAGS={flags}",
    "-DBUILD_SHARED_LIBS=OFF", "-DLLAMA_BUILD_TESTS=OFF", "-DLLAMA_BUILD_EXAMPLES=OFF",
    "-DLLAMA_BUILD_TOOLS=OFF", "-DLLAMA_BUILD_SERVER=OFF", "-DLLAMA_BUILD_COMMON=OFF", "-DLLAMA_BUILD_APP=OFF",
    "-DGGML_NATIVE=OFF", "-DGGML_OPENMP=OFF", "-DGGML_METAL=ON",
    "-DGGML_METAL_EMBED_LIBRARY=ON", "-DGGML_BLAS=ON",
], check=True)
subprocess.run(["cmake", "--build", str(build), "--config", "Release", "-j", "3"], check=True)
xcframework = root / "Frameworks/llama.xcframework"
identifier = "ios-arm64-maccatalyst"
framework = xcframework / identifier / "llama.framework"
(framework / "Headers").mkdir(parents=True)
(framework / "Modules").mkdir()
# Match upstream's public C umbrella; ggml-cpp.h is C++ and cannot be imported
# by Swift's C module scanner.
for relative in ("include/llama.h", "ggml/include/ggml.h", "ggml/include/ggml-opt.h",
                 "ggml/include/ggml-alloc.h", "ggml/include/ggml-backend.h",
                 "ggml/include/ggml-metal.h", "ggml/include/ggml-cpu.h",
                 "ggml/include/ggml-blas.h", "ggml/include/gguf.h"):
    header = source / relative
    shutil.copy2(header, framework / "Headers" / header.name)
(framework / "Modules/module.modulemap").write_text('''framework module llama {
    umbrella "Headers"
    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"
    export *
}
''')
libraries = sorted(build.rglob("*.a"))
assert any(p.name == "libllama.a" for p in libraries), "llama static library missing"
subprocess.run(["xcrun", "libtool", "-static", "-o", str(framework / "llama"),
                *map(str, libraries)], check=True)
with (framework / "Info.plist").open("wb") as file:
    plistlib.dump({"CFBundleExecutable": "llama", "CFBundleIdentifier": "org.ggml.llama",
                  "CFBundleName": "llama", "CFBundlePackageType": "FMWK",
                  "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
                  "MinimumOSVersion": "17.0", "CFBundleSupportedPlatforms": ["MacOSX"]}, file)
plist = xcframework / "Info.plist"
info = plistlib.loads(plist.read_bytes())
assert not any(p.get("SupportedPlatformVariant") == "maccatalyst" for p in info["AvailableLibraries"])
info["AvailableLibraries"].append({"LibraryIdentifier": identifier,
    "LibraryPath": "llama.framework", "SupportedArchitectures": ["arm64"],
    "SupportedPlatform": "ios", "SupportedPlatformVariant": "maccatalyst"})
plist.write_bytes(plistlib.dumps(info))
print("Added real arm64 Mac Catalyst llama slice (b10472)")
