"""Unit tests that do not talk to DiskWala."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from nw.config import Config  # noqa: E402
from nw.downloader.manager import safe_name, unique_path  # noqa: E402
from nw.extractors.base import ExtractorError  # noqa: E402
from nw.extractors.diskwala import DiskwalaExtractor  # noqa: E402


def extractor() -> DiskwalaExtractor:
    return DiskwalaExtractor(Config())


class NormalizeTests(unittest.TestCase):
    def test_s_path(self):
        host, surl = extractor().normalize("https://diskwala.com/s/abc123")
        self.assertEqual(host, "diskwala.com")
        self.assertEqual(surl, "abc123")

    def test_www_and_query(self):
        host, surl = extractor().normalize(
            "https://www.diskwala.com/sharing/link?surl=xyz789"
        )
        self.assertEqual(host, "www.diskwala.com")
        self.assertEqual(surl, "xyz789")

    def test_video_path(self):
        _, surl = extractor().normalize("https://diskwala.com/video/clip-id-42")
        self.assertEqual(surl, "clip-id-42")

    def test_app_hex_id(self):
        host, surl = extractor().normalize(
            "https://www.diskwala.com/app/6a95c4bb06ba7ea03d8c69d4"
        )
        self.assertEqual(host, "www.diskwala.com")
        self.assertEqual(surl, "6a95c4bb06ba7ea03d8c69d4")

    def test_rejects_unknown_host(self):
        with self.assertRaises(ExtractorError):
            extractor().normalize("https://example.com/s/abc")


class TokenTests(unittest.TestCase):
    def test_extracts_common_fields(self):
        html = """
        <script>
        window.jsToken = "tok_ABCDEFG123456";
        var cfg = {"sign": "sgn_zzzzzzzz", "timestamp": 1710000000,
                   "shareid": 42, "uk": 99, "app_id": 250528};
        </script>
        """
        tokens = DiskwalaExtractor._extract_tokens(html)
        self.assertEqual(tokens["jsToken"], "tok_ABCDEFG123456")
        self.assertEqual(tokens["sign"], "sgn_zzzzzzzz")
        self.assertEqual(tokens["timestamp"], "1710000000")
        self.assertEqual(tokens["shareid"], "42")
        self.assertEqual(tokens["uk"], "99")


class NameTests(unittest.TestCase):
    def test_strips_path_chars(self):
        self.assertEqual(safe_name('a/b:c*d?.mp4'), "a_b_c_d_.mp4")

    def test_unique_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "clip.mp4"
            p.write_bytes(b"x")
            nxt = unique_path(p)
            self.assertEqual(nxt.name, "clip (1).mp4")


class PayloadTests(unittest.TestCase):
    def test_items_from_list(self):
        payload = {
            "errno": 0,
            "list": [
                {
                    "fs_id": 1,
                    "server_filename": "movie.mp4",
                    "size": 1234,
                    "isdir": 0,
                    "category": 1,
                    "dlink": "https://cdn.example/file",
                }
            ],
        }
        items = DiskwalaExtractor._items_from_payload(payload, "https://diskwala.com")
        self.assertEqual(len(items), 1)
        self.assertTrue(items[0].is_video)
        self.assertEqual(items[0].direct_url, "https://cdn.example/file")
        self.assertEqual(items[0].size, 1234)


if __name__ == "__main__":
    unittest.main()
