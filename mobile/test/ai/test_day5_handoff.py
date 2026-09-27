"""Synthetic school-report checks; never calls a Provider or emits live evidence."""
import copy
import unittest

from audit_day5_handoff import audit_ai_report, check_secret_markers
import test_validate_day4_evidence as audit_fixtures


class SchoolReportTest(unittest.TestCase):
    def setUp(self):
        fixture_test = audit_fixtures.DayFourAuditTest()
        fixture_test.setUp()
        self.bundle = fixture_test.synthetic_bundle()
        self.report = copy.deepcopy(self.bundle["report"])
        self.report["sources"]["ai"] = True
        self.report["token_usage"] = {"request_count": 1, "prompt_tokens": 3,
            "completion_tokens": 2, "total_tokens": 5, "model": "cuc/deepseek"}

    def test_school_report_keeps_original_evidence(self):
        audit_ai_report(self.bundle, self.report)
        self.report["evidence"][0]["detail"] = "Modified by model"
        with self.assertRaisesRegex(ValueError, "differs from source"):
            audit_ai_report(self.bundle, self.report)

    def test_wrong_provider_and_context_are_rejected(self):
        self.report["token_usage"]["model"] = "deepseek-flash"
        with self.assertRaisesRegex(ValueError, "model name"):
            audit_ai_report(self.bundle, self.report)

        self.report["token_usage"]["model"] = "cuc/deepseek"
        self.report["created_at"] = "2026-09-27T12:00:00Z"
        with self.assertRaisesRegex(ValueError, "created_at"):
            audit_ai_report(self.bundle, self.report)

    def test_rule_or_mock_report_cannot_replace_real_school_result(self):
        with self.assertRaisesRegex(ValueError, "real-AI"):
            audit_ai_report(self.bundle, self.bundle["report"])

    def test_metadata_password_field_name_is_not_a_credential(self):
        check_secret_markers({"fields": [{"name": "password", "type": "password"}]})
        with self.assertRaisesRegex(ValueError, "credential field"):
            check_secret_markers({"password": "not-a-real-password"})


if __name__ == "__main__":
    unittest.main()
