import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sources  # noqa: E402


def fx(name):
    with open(os.path.join(HERE, "fixtures", name + ".json"), "rb") as f:
        return f.read()


def fetcher(pages):
    """Returns replies in order and records every URL asked for."""
    calls = []

    def fetch(url, headers):
        calls.append((url, headers))
        return pages[min(len(calls) - 1, len(pages) - 1)]
    fetch.calls = calls
    return fetch


class Graph(unittest.TestCase):
    def test_normalises_and_follows_paging(self):
        f = fetcher([(200, fx("graph_page1")), (200, fx("graph_page2"))])
        src = sources.GraphApiSource("111", "TOKEN", fetch=f)
        posts = src.recent()
        self.assertEqual([p["post_id"] for p in posts], ["111_300", "111_299", "111_298"])
        self.assertEqual(posts[0]["text"], "Lunes de promo: 2 pizzas por ₡12.000")
        self.assertEqual(posts[0]["image_urls"], ["https://scontent.xx.fbcdn.net/v/t39/a.jpg"])
        self.assertEqual(posts[1]["image_urls"], [])
        self.assertEqual(src.calls, 2)
        self.assertIn("access_token=TOKEN", f.calls[0][0])

    def test_stops_at_a_seen_post(self):
        f = fetcher([(200, fx("graph_page1")), (200, fx("graph_page2"))])
        posts = sources.GraphApiSource("111", "T", fetch=f).recent(seen={"111_299"})
        self.assertEqual([p["post_id"] for p in posts], ["111_300"])
        self.assertEqual(len(f.calls), 1)

    def test_call_cap_and_page_cap(self):
        f = fetcher([(200, fx("graph_page1"))])
        src = sources.GraphApiSource("111", "T", fetch=f, max_calls=1)
        src.recent(max_pages=5)
        self.assertEqual(len(f.calls), 1)

    def test_expired_token_asks_for_reconnect(self):
        with self.assertRaises(sources.SourceError) as cm:
            sources.GraphApiSource("111", "T", fetch=fetcher([(400, fx("graph_error190"))])).recent()
        self.assertEqual(cm.exception.kind, "reconnect")
        self.assertNotIn("T", str(cm.exception).split())

    def test_garbage_reply_is_a_clean_error(self):
        with self.assertRaises(sources.SourceError) as cm:
            sources.GraphApiSource("111", "T", fetch=fetcher([(200, b"<html>")])).recent()
        self.assertEqual(cm.exception.kind, "error")

    def test_token_never_in_error_text(self):
        with self.assertRaises(sources.SourceError) as cm:
            sources.GraphApiSource("111", "SECRETTOKEN", fetch=fetcher([(500, b"nope")])).recent()
        self.assertNotIn("SECRETTOKEN", str(cm.exception))


class ScrapeCreators(unittest.TestCase):
    def test_normalises_and_skips_unusable_posts(self):
        f = fetcher([(200, fx("sc_page1")), (200, b'{"posts": []}')])
        src = sources.ScrapeCreatorsSource("https://www.facebook.com/examplepizza", "KEY", fetch=f)
        posts = src.recent()
        self.assertEqual([p["post_id"] for p in posts], ["300", "299"])
        self.assertEqual(posts[0]["image_urls"], ["https://scontent.xx.fbcdn.net/v/t39/a.jpg"])
        self.assertEqual(f.calls[0][1], {"x-api-key": "KEY"})
        self.assertIn("cursor=CUR1", f.calls[1][0])

    def test_key_and_credit_problems_ask_a_person(self):
        for status in (401, 402):
            with self.assertRaises(sources.SourceError) as cm:
                sources.ScrapeCreatorsSource("https://www.facebook.com/x", "K", fetch=fetcher([(status, b"{}")])).recent()
            self.assertEqual(cm.exception.kind, "reconnect")
        with self.assertRaises(sources.SourceError) as cm:
            sources.ScrapeCreatorsSource("https://www.facebook.com/x", "K", fetch=fetcher([(429, b"{}")])).recent()
        self.assertEqual(cm.exception.kind, "rate")

    def test_call_cap(self):
        f = fetcher([(200, fx("sc_page1"))])
        sources.ScrapeCreatorsSource("https://www.facebook.com/x", "K", fetch=f, max_calls=2).recent(max_pages=9)
        self.assertEqual(len(f.calls), 2)


class Images(unittest.TestCase):
    JPEG = b"\xff\xd8\xff\xe0" + b"0" * 20
    PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 20

    def get(self, url, body, status=200, public=True):
        return sources.download_image(url, fetch=lambda u, h: (status, body), resolver=lambda host: public)

    def test_accepts_real_images(self):
        self.assertEqual(self.get("https://scontent.xx.fbcdn.net/a.jpg", self.JPEG), (self.JPEG, "jpg"))
        self.assertEqual(self.get("https://cdn.example.com/a", self.PNG)[1], "png")

    def test_rejects_unsafe_or_wrong(self):
        self.assertIsNone(self.get("http://cdn.example.com/a.jpg", self.JPEG))
        self.assertIsNone(self.get("https://127.0.0.1/a.jpg", self.JPEG, public=False))
        self.assertIsNone(self.get("https://user@cdn.example.com/a.jpg", self.JPEG))
        self.assertIsNone(self.get("https://cdn.example.com:8443/a.jpg", self.JPEG))
        self.assertIsNone(self.get("https://cdn.example.com/a.jpg", b"<html>not an image</html>"))
        self.assertIsNone(self.get("https://cdn.example.com/a.jpg", self.JPEG, status=404))
        self.assertIsNone(self.get("https://cdn.example.com/a.jpg", self.JPEG + b"0" * sources.MAX_IMAGE_BYTES))
        self.assertIsNone(self.get("", self.JPEG))

    def test_private_resolution_is_refused(self):
        self.assertFalse(sources._public_host("localhost"))


class Fixture(unittest.TestCase):
    def test_stops_at_seen(self):
        posts = [{"post_id": "3"}, {"post_id": "2"}, {"post_id": "1"}]
        self.assertEqual(sources.FixtureSource(posts).recent(seen={"2"}), [{"post_id": "3"}])


if __name__ == "__main__":
    unittest.main()
