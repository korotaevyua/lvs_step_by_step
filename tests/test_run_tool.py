import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / 'scripts/run_tool.sh'


class LoggingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lvs log test ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / 'tool log'

    def run_tool(self, mode, *command, **env):
        return subprocess.run(
            [str(HELPER), mode, str(self.log), *command],
            env=dict(os.environ, **env), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)

    def test_both_modes_preserve_exact_tool_failure_and_log(self):
        for mode in ('--quiet', '--verbose'):
            with self.subTest(mode=mode):
                self.log.write_text('old output\n')
                result = self.run_tool(
                    mode, 'sh', '-c',
                    'printf "%s\\n" "$1"; printf "stderr\\n" >&2; exit 7',
                    'test', 'argument with spaces')
                self.assertEqual(result.returncode, 7, result.stdout)
                expected = 'argument with spaces\nstderr\n'
                self.assertEqual(self.log.read_text(), expected)
                self.assertEqual(result.stdout, expected if mode == '--verbose' else '')

    def test_logging_failure_fails_a_successful_tool(self):
        # Simulate a tee failure after it has consumed all tool output.
        tee = self.root / 'tee'
        tee.write_text('#!/bin/sh\ncat >/dev/null\nexit 9\n')
        tee.chmod(0o755)
        result = self.run_tool(
            '--verbose', 'sh', '-c', 'echo output',
            PATH=f'{self.root}:' + os.environ['PATH'])
        self.assertEqual(result.returncode, 9)

    def test_tool_error_has_priority_over_logging_error(self):
        tee = self.root / 'tee'
        tee.write_text('#!/bin/sh\ncat >/dev/null\nexit 9\n')
        tee.chmod(0o755)
        result = self.run_tool(
            '--verbose', 'sh', '-c', 'echo output; exit 7',
            PATH=f'{self.root}:' + os.environ['PATH'])
        self.assertEqual(result.returncode, 7)

    def test_unavailable_log_does_not_launch_tool(self):
        self.log.mkdir()
        marker = self.root / 'tool_was_launched'
        for mode in ('--quiet', '--verbose'):
            with self.subTest(mode=mode):
                result = self.run_tool(mode, 'touch', str(marker))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
