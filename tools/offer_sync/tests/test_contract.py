import copy
import glob
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import contract  # noqa: E402

FIX = os.path.join(HERE, "data")


def load(name):
    return json.load(open(os.path.join(FIX, name + ".json"), encoding="utf-8"))


class Contract(unittest.TestCase):
    def test_fixtures_validate(self):
        files = sorted(glob.glob(os.path.join(FIX, "offer_*.json")) + glob.glob(os.path.join(FIX, "not_offer.json")))
        self.assertGreaterEqual(len(files), 4)
        for f in files:
            self.assertEqual(contract.validate(json.load(open(f, encoding="utf-8"))), [], f)

    def test_json_schema_agrees(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest("jsonschema not installed")
        schema = json.load(open(os.path.join(os.path.dirname(HERE), "offer.schema.json")))
        for f in glob.glob(os.path.join(FIX, "*.json")):
            if os.path.basename(f).startswith(("offer_", "not_offer")):
                jsonschema.validate(json.load(open(f, encoding="utf-8")), schema)

    def bad(self, **change):
        o = copy.deepcopy(load("offer_example_monday"))
        o.update(change)
        return contract.validate(o)

    def test_rejects_bad_values(self):
        self.assertTrue(self.bad(weekdays=[7]))
        self.assertTrue(self.bad(weekdays=[0, 0]))
        self.assertTrue(self.bad(variants=[{"label": "", "price": 0}]))
        self.assertTrue(self.bad(variants=[{"label": "", "price": -5}]))
        self.assertTrue(self.bad(currency="crc"))
        self.assertTrue(self.bad(confidence=1.5))
        self.assertTrue(self.bad(valid_from="2026-10-10", valid_until="2026-10-01"))
        self.assertTrue(self.bad(time_window={"from": "25:00", "to": "10:00"}))
        self.assertTrue(self.bad(discount={"type": "percent", "amount": 150}))
        self.assertTrue(self.bad(extra="x"))
        self.assertTrue(self.bad(variants=[{"label": "", "price": 1}, {"label": "", "price": 2}]))
        self.assertTrue(self.bad(variants=[], discount=None))

    def test_source_must_be_https(self):
        o = load("offer_example_monday")
        o["source"]["post_url"] = "javascript:alert(1)"
        self.assertTrue(contract.validate(o))

    def test_not_offer_needs_no_price(self):
        self.assertEqual(contract.validate(load("not_offer")), [])


if __name__ == "__main__":
    unittest.main()
