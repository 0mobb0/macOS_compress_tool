#!/usr/bin/env python3
"""Independent round trip: Python zipfile, raw headers and macOS ditto."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unicodedata
import zipfile
import zlib


def verify(archive, expected):
    raw = archive.read_bytes()
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == set(expected)
        for info in z.infolist():
            assert info.flag_bits & 0x800, info.filename
            assert info.filename == unicodedata.normalize('NFC', info.filename)
            assert z.read(info) == expected[info.filename]
            offset = info.header_offset
            header = struct.unpack_from('<IHHHHHIIIHH', raw, offset)
            assert header[0] == 0x04034B50 and header[2] & 0x800
            name_len, extra_len = header[-2:]
            name = raw[offset + 30:offset + 30 + name_len]
            assert name.decode('utf-8') == info.filename
            extra = raw[offset + 30 + name_len:offset + 30 + name_len + extra_len]
            for fields in (extra, info.extra):
                kind, size = struct.unpack_from('<HH', fields)
                assert kind == 0x7075 and size == len(name) + 5
                assert fields[4] == 1
                assert struct.unpack_from('<I', fields, 5)[0] == zlib.crc32(name)
                assert fields[9:] == name
        return {i.filename: hashlib.sha256(z.read(i)).hexdigest() for i in z.infolist() if not i.is_dir()}


def main():
    executable = str(Path(sys.argv[1]).resolve())
    export = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        folder = root / '跨平台资料'
        folder.mkdir()
        contents = {
            '中文报告.txt': '你好，Windows！'.encode(),
            '日本語.txt': 'こんにちは'.encode(),
            '한국어.txt': '안녕하세요'.encode(),
            'emoji-🌏📦.txt': b'emoji',
            'cafe\u0301.txt': b'normalized',
            '空文件.txt': b'',
            '空 格 & [1].txt': b'spaces',
            '大文件.bin': os.urandom(2_000_000),
            '.env.example': b'PUBLIC_EXAMPLE=true',
        }
        expected = {'跨平台资料/': b'', '跨平台资料/空目录/': b''}
        (folder / '空目录').mkdir()
        for name, data in contents.items():
            (folder / name).write_bytes(data)
            expected['跨平台资料/' + unicodedata.normalize('NFC', name)] = data
        for name in ['.DS_Store', '._中文报告.txt']:
            (folder / name).write_bytes(b'filtered')
        (folder / '__MACOSX').mkdir()
        (folder / '__MACOSX' / 'junk').write_bytes(b'filtered')
        archive = root / 'compatibility.zip'
        # Reproduce virtualenv relative links; broken, external-directory and circular links.
        outside = root / 'outside'
        outside.mkdir()
        (outside / 'must-not-be-included.txt').write_bytes(b'outside fixture')
        bin_dir = folder / '.venv-lattice' / 'bin'
        bin_dir.mkdir(parents=True)
        (bin_dir / 'python').symlink_to('python3')
        (bin_dir / 'python3').symlink_to(outside / 'missing-python3')
        (folder / 'external-dir').symlink_to(outside, target_is_directory=True)
        (folder / 'loop').symlink_to(folder, target_is_directory=True)
        (folder / 'file-alias').symlink_to('中文报告.txt')
        expected['跨平台资料/.venv-lattice/'] = b''
        expected['跨平台资料/.venv-lattice/bin/'] = b''
        result = subprocess.run([executable, str(archive), str(folder)], check=True, capture_output=True, text=True)
        assert result.stderr.count('已跳过符号链接：') == 5, result.stderr
        for link in ['.venv-lattice/bin/python', '.venv-lattice/bin/python3', 'external-dir', 'loop', 'file-alias']:
            assert '跨平台资料/' + link + '\n' in result.stderr

        hashes = verify(archive, expected)
        extracted = root / 'extracted'
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(extracted)], check=True)
        for name, data in expected.items():
            path = extracted / name
            assert path.is_dir() if name.endswith('/') else path.read_bytes() == data
        # Actual compression, not just stored file entries.
        repeated = root / 'repeated.txt'
        repeated.write_bytes(b'abcde' * 200_000)
        compressed = root / 'small.zip'
        subprocess.run([executable, str(compressed), str(repeated)], check=True)
        assert compressed.stat().st_size < 10_000
        if export:
            export.mkdir(parents=True, exist_ok=True)
            (export / archive.name).write_bytes(archive.read_bytes())
            (export / 'expected.json').write_text(json.dumps(hashes, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'PASS: {len(expected)} entries; UTF-8 in both headers; Unicode path extras; CRC/content; NFC; metadata filtering; ditto round trip; DEFLATE compression; 5 symlinks skipped and reported.')

if __name__ == '__main__':
    main()
