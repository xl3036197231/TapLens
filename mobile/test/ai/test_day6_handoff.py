"""Read-only regression of the fixed Day 6 cross-branch audit."""

import unittest

import audit_day6_handoff


class DaySixHandoffTest(unittest.TestCase):
    def test_rule_pass_and_unrecoverable_school_result_stay_separate(self):
        result = audit_day6_handoff.run()
        self.assertEqual(result["checks"]["archived_day5_rule_bundle_and_png"], "PASS")
        self.assertEqual(result["checks"]["school_ai_complete_report"], "BLOCKED")
        self.assertEqual(result["a_school_http_status"], 422)
        self.assertEqual(result["current_task_readonly_get_status"], 410)
        self.assertFalse(result["complete_model_report_recoverable"])


if __name__ == "__main__":
    unittest.main()
