import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import sources  # noqa: E402
import sync  # noqa: E402

SHOP = {"name": "Example", "page_url": "https://www.facebook.com/examplepizza", "page_id": "1", "source": "graph",
        "site": "https://shop.example", "currency": "CRC", "user": "bot"}
POSTS = [{"post_id": "3", "url": "https://www.facebook.com/examplepizza/posts/3", "text": "Lunes de promo: 2 pizzas por ₡12.000", "posted_at": "", "image_urls": ["https://x/a.jpg"]},
         {"post_id": "2", "url": "https://www.facebook.com/examplepizza/posts/2", "text": "Gracias a todos", "posted_at": "", "image_urls": []}]
REPLY = json.dumps({"is_offer": True, "title": "Lunes", "variants": [{"label": "", "price": 12000}], "weekdays": [0], "confidence": 0.9})


def run(posts=POSTS, poster=None, state=None, dry=False, src_error=None):
    sent = []

    class Src(sources.FixtureSource):
        def recent(self, seen=(), max_pages=3):
            if src_error:
                raise src_error
            return super().recent(seen)

    def default_poster(site, user, pw, offer):
        sent.append((site, user, pw, offer))
        return 201, {"status": "created_draft"}
    state = {} if state is None else state
    lines, needs = sync.run_shop(SHOP, state, {"RSY_EXAMPLE_WP_PASSWORD": "pw"}, lambda s, u, image=None: REPLY,
                                 lambda shop, env: Src(posts), poster or default_poster,
                                 lambda url: (b"\xff\xd8\xff\xe0data", "jpg"), dry)
    return lines, needs, state, sent


class Runner(unittest.TestCase):
    def test_sends_offer_with_image_and_remembers_posts(self):
        lines, needs, state, sent = run()
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0][2], "pw")
        self.assertEqual(sent[0][3]["image"]["mime"], "image/jpeg")
        self.assertEqual(sorted(state["Example"]), ["2", "3"])
        self.assertFalse(needs)

    def test_second_run_does_nothing(self):
        _, _, state, _ = run()
        _, _, _, sent = run(state=state)
        self.assertEqual(sent, [])

    def test_dry_run_sends_and_remembers_nothing(self):
        lines, _, state, sent = run(dry=True)
        self.assertEqual(sent, [])
        self.assertNotIn("3", state.get("Example", []))
        self.assertTrue(any("WOULD SEND" in l for l in lines))

    def test_server_error_retries_next_run(self):
        _, _, state, _ = run(poster=lambda *a: (500, {}))
        self.assertNotIn("3", state["Example"])

    def test_bad_credentials_flag_a_person(self):
        _, needs, state, _ = run(poster=lambda *a: (401, {}))
        self.assertTrue(needs)
        self.assertNotIn("3", state["Example"])

    def test_expired_facebook_token_flags_a_person_not_a_crash(self):
        lines, needs, _, _ = run(src_error=sources.SourceError("reconnect", "token expired"))
        self.assertTrue(needs)
        self.assertIn("reconnect", lines[0])

    def test_rate_limit_is_quiet(self):
        _, needs, _, _ = run(src_error=sources.SourceError("rate", "slow down"))
        self.assertFalse(needs)

    def test_config_validation(self):
        p = os.path.join(HERE, "bad_shops.json")
        json.dump([{"name": "x"}], open(p, "w"))
        try:
            with self.assertRaises(SystemExit):
                sync.load_shops(p)
        finally:
            os.remove(p)

    def test_env_name(self):
        self.assertEqual(sync.env_name({"name": "Way Forward"}, "FB_TOKEN"), "RSY_WAY_FORWARD_FB_TOKEN")


if __name__ == "__main__":
    unittest.main()
