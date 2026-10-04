import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from parse_menu import parse_text
import import_menu

TEXT = """PIZZAS
Margarita ........ ₡7.000
tomate, mozzarella y albahaca

Vegetariana ... 8500
Pepperoni  Pequeña 5.000  Grande 9.000
BEBIDAS
Agua 1 mil
Promoción ...... 12
Refresco ₡27.000
Jugo ₡1.500
Café ₡1.200
"""

class Parse(unittest.TestCase):
    def setUp(self):
        self.d = parse_text(TEXT, "CRC")
        self.by = {i["name"]: i for i in self.d["items"]}

    def test_thousands_separators_and_symbol(self):
        self.assertEqual(self.by["Margarita"]["price"], 7000)
        self.assertEqual(self.by["Vegetariana"]["price"], 8500)

    def test_description_survives_blank_lines(self):
        self.assertEqual(self.by["Margarita"]["description"], "tomate, mozzarella y albahaca")

    def test_sizes_become_variants(self):
        p = self.by["Pepperoni"]
        self.assertEqual([(v["label"], v["price"]) for v in p["variants"]], [("Pequeña", 5000), ("Grande", 9000)])

    def test_mil_is_flagged_not_silent(self):
        self.assertEqual(self.by["Agua"]["price"], 1000)
        self.assertTrue(self.by["Agua"]["needs_review"])

    def test_tiny_number_is_never_guessed(self):
        self.assertIsNone(self.by["Promoción"]["price"])
        self.assertTrue(self.by["Promoción"]["needs_review"])

    def test_misread_currency_sign_is_flagged(self):
        self.assertTrue(any("'2'" in r for r in self.by["Refresco"]["needs_review"]))

class Import(unittest.TestCase):
    def test_refuses_unreviewed(self):
        with self.assertRaises(SystemExit):
            import_menu.plan(parse_text(TEXT, "CRC"))

    def test_skips_flagged_unless_approved(self):
        d = parse_text(TEXT, "CRC"); d["reviewed"] = True
        products, skipped = import_menu.plan(d)
        names = {p["title"] for p in products}
        self.assertIn("Margarita", names)
        self.assertNotIn("Refresco", names)
        self.assertIn("Pepperoni (Grande)", names)

if __name__ == "__main__":
    unittest.main()
