#!/usr/bin/env python3
"""Collect upstream license/notice texts, preserving their source-relative names."""

import os
import re
import sys
import tarfile
from pathlib import Path, PurePosixPath


NOTICE_NAME = re.compile(
    r"^(licen[cs]e|copying|copyright|notice|ofl|ftl|mit|bsd|apache|attribution)([._-]|$)",
    re.IGNORECASE,
)


def is_notice(path):
    return bool(NOTICE_NAME.match(path.name)) or path.as_posix() == "src/font/res/README.md"


def archive_notices(path, label):
    # Zig 0.16 stores fetched packages as archives rather than directories.
    # Read notices in place: do not extract untrusted paths or symlinks.
    # Not "r|gz": Python 3.15's stream reader spins forever on these archives,
    # which end without tar's end-of-archive blocks.
    sections = []
    with tarfile.open(path, mode="r:gz") as archive:
        for member in archive:
            relative = PurePosixPath(member.name)
            if not member.isfile() or relative.is_absolute() or ".." in relative.parts:
                continue
            if not is_notice(relative):
                continue
            text = archive.extractfile(member).read().decode("utf-8-sig")
            sections.append((relative.as_posix(), text))
    return [
        f"{label}/{path.name}/{name}\n{'=' * 72}\n{text.rstrip()}\n"
        for name, text in sorted(sections)
    ]


def collect(roots):
    sections = []
    for label, root in roots:
        root = Path(root)
        if not root.is_dir():
            raise ValueError(f"Missing notice source: {root}")
        notices = []
        for directory, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in {".git", ".zig-cache", "zig-out"})
            for name in sorted(files):
                path = Path(directory) / name
                relative = path.relative_to(root)
                if Path(directory) == root and name.endswith(".tar.gz"):
                    notices.extend(archive_notices(path, label))
                    continue
                # This README maps the bundled fonts to their license texts.
                if not is_notice(relative):
                    continue
                if path.is_symlink():
                    continue
                text = path.read_text(encoding="utf-8-sig")
                notices.append(f"{label}/{relative.as_posix()}\n{'=' * 72}\n{text.rstrip()}\n")
        if not notices:
            raise ValueError(f"No license notices found in {root}")
        sections.extend(notices)
    return "Third-party license notices\n\n" + "\n".join(sections)


def main():
    if len(sys.argv) < 4 or len(sys.argv[2:]) % 2:
        raise ValueError("Usage: collect-notices.py OUTPUT LABEL ROOT [LABEL ROOT ...]")
    output = Path(sys.argv[1])
    roots = list(zip(sys.argv[2::2], sys.argv[3::2]))
    text = collect(roots)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError, tarfile.TarError) as error:
        sys.exit(str(error))
