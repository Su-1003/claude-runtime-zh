import unittest
from build_dictionary import eligible, literal, canonical


class DictionarySafetyTests(unittest.TestCase):
    def test_unit_identifiers_and_icu_are_not_rules(self):
        for value in ("hours", "Hours", "hour", "SECONDS", "{hours}", "Updated {hours}h ago",
                      "unit.hours", "hours()", "<button>", "x => hours", "true"):
            with self.subTest(value=value):
                self.assertFalse(eligible(value, "小时"))

    def test_real_display_phrase_is_allowed(self):
        self.assertTrue(eligible("New chat", "新建聊天"))
        self.assertTrue(eligible("Don't show again", "不再显示"))

    def test_quoted_resource_strings_are_decoded_as_text(self):
        self.assertEqual(literal('"Save changes"'), "Save changes")
        self.assertIsNone(literal(None))

    def test_code_and_incomplete_translations_are_rejected(self):
        self.assertFalse(eligible("Save", "保存 {name}"))
        self.assertFalse(eligible("API key", "API key"))
        self.assertFalse(eligible("https://example.com", "示例"))

    def test_typographic_quotes_and_long_explanations_are_allowed(self):
        self.assertEqual(canonical(" What Anthropic doesn’t see\n"), "What Anthropic doesn't see")
        self.assertTrue(eligible("Claude saves what it learns about you and your work during Cowork sessions. These files are stored on this device.", "Claude 会保存协作中了解的内容。"))


if __name__ == "__main__":
    unittest.main()
