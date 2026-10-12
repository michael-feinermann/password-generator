"""Compare a Windows distribution ZIP to its already signature-verified inventory."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import stat

def require(condition):
    if not condition:
        raise ValueError("Archive differs from the authenticated inventory or violates safety bounds")

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property")
        result[key] = value
    return result

def safe(name):
    if not name or len(name) > 240 or "\\" in name or ":" in name:
        raise ValueError("Unsafe archive path")
    if any(p in ("", ".", "..") or p.endswith((" ", ".")) for p in name.split("/")):
        raise ValueError("Unsafe archive path")
    return name

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("archive", type=Path)
a = p.parse_args()
with zipfile.ZipFile(a.archive) as archive:
    entries = archive.infolist()
    require(0 < len(entries) <= 8192)
    files, dirs, names = {}, set(), set()
    total = 0
    for entry in entries:
        name = safe(entry.filename[:-1] if entry.is_dir() else entry.filename)
        require(name.casefold() not in names and entry.filename == entry.orig_filename)
        names.add(name.casefold())
        require(not entry.flag_bits & 1)
        require(stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG, stat.S_IFDIR))
        parts = name.split("/")
        dirs.update("/".join(parts[:n]) for n in range(1, len(parts)))
        if entry.is_dir():
            require(entry.file_size == 0)
            dirs.add(name)
        else:
            require(0 <= entry.file_size <= 512 * 1024 * 1024)
            total += entry.file_size
            require(total <= 2 * 1024 * 1024 * 1024)
            data = archive.read(entry)
            require(len(data) == entry.file_size)
            files[name] = (len(data), hashlib.sha512(data).hexdigest())
    inventory = json.loads(archive.read("windows-release.json"), object_pairs_hook=unique_object)
    require((inventory["schema"], inventory["product"], inventory["version"], inventory["build"], inventory["architecture"]) == (
        1, "com.feinermann.passwordgenerator.windows", "2.3.6", 14, "win-x64"))
    for sidecar, size in (("windows-release.json", None), ("windows-release.rsa.sig", 512), ("windows-release.mldsa87.sig", 4627)):
        length, _ = files.pop(sidecar)
        require(size is None or size == length)
    expected = {safe(item["path"]): (item["size"], item["sha512"]) for item in inventory["files"]}
    require(not (set(files) & dirs))
    require(len(expected) == len(inventory["files"]) and files == expected)
    require(dirs == set(inventory["directories"]))
print(f"PASS ZIP exact inventory: {len(files)} files, {len(dirs)} directories; {total} uncompressed bytes")
