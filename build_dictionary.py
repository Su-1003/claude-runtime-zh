"""Read translation data and original English labels; write only this project."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile


def asar_json(archive, parts):
    with archive.open("rb") as stream:
        prefix = stream.read(16)
        if len(prefix) != 16:
            raise ValueError("Invalid ASAR prefix")
        _, header_size, _, json_size = struct.unpack("<4I", prefix)
        if not 0 < json_size <= 32 * 1024 * 1024 or header_size < json_size + 4:
            raise ValueError("Invalid ASAR header size")
        entry = json.loads(stream.read(json_size))
        for part in parts:
            entry = entry["files"][part]
        if entry.get("unpacked"):
            raise ValueError("Unexpected unpacked translation resource")
        size = entry["size"]
        if not 0 < size < 32 * 1024 * 1024:
            raise ValueError("Unexpected translation size")
        stream.seek(8 + header_size + int(entry["offset"]))
        return json.loads(stream.read(size))


def literal(value):
    if not isinstance(value, str):
        return None
    if value.startswith('"') and value.endswith('"'):
        try:
            decoded = json.loads(value)
            if isinstance(decoded, str):
                value = decoded
        except ValueError:
            return None
    return value.strip()


def canonical(value):
    return re.sub(r"\s+", " ", value.translate(str.maketrans({"’": "'", "‘": "'", "“": '"', "”": '"'}))).strip()


def eligible(english, chinese):
    if not english or not chinese or english == chinese:
        return False
    if not 2 <= len(english) <= 1200 or re.search(r"[\x00-\x1f\u3400-\u9fff]", english) or not re.search(r"[A-Za-z]", english):
        return False
    if not re.search(r"[\u3400-\u9fff]", chinese) or len(chinese) > 1500:
        return False
    # Neither code-like literals nor units/placeholders become DOM translation rules.
    if re.search(r"[{}\[\]<>`\\;=]|://|\*\*|\w+\(|\w+\.\w+|@", english):
        return False
    if re.search(r"[{}\n\r]", chinese):
        return False
    if english.lower() in {"hours", "hour", "minutes", "minute", "seconds", "second",
                            "days", "day", "weeks", "week", "months", "month", "years", "year",
                            "true", "false", "null", "undefined", "nan", "infinity"}:
        return False
    return True


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--resources", required=True, type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    source = args.source.resolve()
    resources = args.resources.resolve()
    candidates = defaultdict(set)
    read_files = []

    def read_source(relative):
        if source.is_file() and source.suffix.lower() == ".zip":
            with zipfile.ZipFile(source) as archive:
                names = [name for name in archive.namelist() if name == relative or name.endswith('/' + relative)]
                if len(names) != 1:
                    raise ValueError(f"Source archive entry not unique: {relative}")
                return archive.read(names[0]).decode("utf-8-sig")
        return (source / relative).read_text(encoding="utf-8-sig")

    def collect(english, chinese):
        english, chinese = literal(english), literal(chinese)
        if english:
            english = canonical(english)
        if eligible(english, chinese):
            candidates[english].add(chinese)

    pairs = [("app.asar", ["resources", "i18n", "en-US.json"], "desktop-zh-CN.json"),
             ("ion-dist.asar", ["i18n", "en-US.json"], "frontend-zh-CN.json")]
    for archive_name, parts, translation_name in pairs:
        archive = resources / archive_name
        originals = asar_json(archive, parts)
        translations = json.loads(read_source("resources/" + translation_name))
        for key, original in originals.items():
            collect(original, translations.get(key))
        read_files.append(archive)
        if source.is_dir():
            read_files.append(source / "resources" / translation_name)
    for pair in json.loads(read_source("resources/frontend-hardcoded-zh-CN.json")):
        if isinstance(pair, list) and len(pair) == 2:
            collect(*pair)
    read_files.append(source if source.is_file() else source / "resources" / "frontend-hardcoded-zh-CN.json")
    dictionary = {key: next(iter(values)) for key, values in sorted(candidates.items()) if len(values) == 1}
    if not dictionary or any(key.lower() in {"hours", "hour"} for key in dictionary):
        raise ValueError("Invalid generated dictionary")
    script = project / "claude-zh.js"
    original = script.read_text(encoding="utf-8")
    pattern = r"/\* BEGIN_IMPORTED_WORDS \*/.*?/\* END_IMPORTED_WORDS \*/"
    replacement = "/* BEGIN_IMPORTED_WORDS */" + json.dumps(dictionary, ensure_ascii=False, separators=(",", ":")) + "/* END_IMPORTED_WORDS */"
    output, count = re.subn(pattern, lambda _: replacement, original, flags=re.S)
    if count != 1:
        raise ValueError("Expected exactly one dictionary block")
    script.write_text(output, encoding="utf-8", newline="\n")
    (project / "dictionary.json").write_text(json.dumps(dictionary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (project / "UPSTREAM-LICENSE.txt").write_text(read_source("LICENSE"), encoding="utf-8")
    record = {"entries": len(dictionary), "ambiguous_labels_skipped": sum(len(v) > 1 for v in candidates.values()),
              "source": str(source), "inputs_read_only": [{"path": str(p), "sha256": digest(p)} for p in read_files],
              "upstream": "https://github.com/javaht/claude-desktop-zh-cn",
              "license": "MIT; see UPSTREAM-LICENSE.txt",
              "application_files_written": []}
    (project / "dictionary-provenance.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"entries": len(dictionary), "ambiguous_labels_skipped": record["ambiguous_labels_skipped"],
                      "application_files_written": []}, ensure_ascii=False))


if __name__ == "__main__":
    main()
