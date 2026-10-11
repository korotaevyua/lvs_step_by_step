import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'run_lvs.sh'

@unittest.skipUnless(shutil.which('csh'), 'C-shell required')
class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lvs test ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.out = self.root / 'results'
        self.trace = self.root / 'trace'
        self.config = self.root / 'config.csh'
        for name in ('design.v', 'design.gds', 'source.net', 'extract', 'compare'):
            (self.root / name).write_text('synthetic\n')
        self.config.write_text('\n'.join([
            'set TOP = demo',
            f'set STEP_DIR = "{self.out}"',
            f'set verilog = "{self.root}/design.v"',
            f'setenv GDS "{self.root}/design.gds"',
            f'set V2LVS_SRC = "{self.root}/source.net"',
            f'set EXTR_RULE = "{self.root}/extract"',
            f'set COMP_RULE = "{self.root}/compare"',
        ]) + '\n')
        for tool in ('v2lvs', 'calibre'):
            f = self.root / tool
            f.write_text('''#!/bin/sh
stage=compare
case "$0" in *v2lvs) stage=v2cdl;; esac
out=
while [ "$#" -gt 0 ]; do
 case "$1" in
  -o) shift; out=$1;;
  -spice) shift; out=$1; stage=extraction;;
 esac
 shift
done
printf '%s\\n' "$stage" >> "$TRACE"
printf '%s stdout\\n' "$stage"
printf '%s stderr\\n' "$stage" >&2
[ "$FAIL_STAGE" = "$stage" ] && exit 7
if [ -n "$out" ] && [ "$EMPTY_STAGE" != "$stage" ]; then printf 'netlist\\n' > "$out"; fi
[ "$FAIL_AFTER_OUTPUT" = "$stage" ] && exit 7
exit 0
''')
            f.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.root}:' + os.environ['PATH'], TRACE=str(self.trace))

    def run_mode(self, mode='full', options=(), **env):
        return subprocess.run(['csh', '-f', str(RUNNER), *options, mode, str(self.config)],
                              cwd=self.root, env=dict(self.env, **env), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def successful(self, mode='full'):
        p = self.run_mode(mode)
        self.assertEqual(p.returncode, 0, p.stdout)

    def test_modes_and_input_snapshots(self):
        self.successful()
        original = (self.out / 'verilog/design.v').read_text()
        (self.root / 'design.v').write_text('changed')
        for mode in ('compare', 'extraction_compare', 'v2cdl_compare'):
            self.successful(mode)
            if mode != 'v2cdl_compare':
                self.assertEqual((self.out / 'verilog/design.v').read_text(), original)
        self.assertEqual(self.trace.read_text().splitlines(), [
            'v2cdl', 'extraction', 'compare', 'compare', 'extraction', 'compare', 'v2cdl', 'compare'])

    def test_failure_blocks_compare_and_clears_marker(self):
        self.successful()
        self.trace.write_text('')
        p = self.run_mode('v2cdl_compare', FAIL_STAGE='v2cdl')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(self.trace.read_text().splitlines(), ['v2cdl'])
        self.assertFalse((self.out / 'compare/done').exists())
        self.assertNotEqual(self.run_mode('compare').returncode, 0)

    def test_extraction_and_compare_failure(self):
        for stage in ('extraction', 'compare'):
            with self.subTest(stage=stage):
                p = self.run_mode(FAIL_STAGE=stage)
                self.assertNotEqual(p.returncode, 0, p.stdout)
                self.assertFalse((self.out / 'compare/done').exists())

    def test_empty_output_rejected(self):
        self.assertNotEqual(self.run_mode(EMPTY_STAGE='v2cdl').returncode, 0)
        self.assertFalse((self.out / 'v2cdl/done').exists())

    def test_archives_do_not_collide(self):
        # Force equal dates to exercise the daily counter deterministically.
        date = self.root / 'date'
        date.write_text('#!/bin/sh\necho 20261012\n')
        date.chmod(0o755)
        self.successful()
        self.successful()
        self.successful()
        archives = list(self.root.glob('results.archive.*'))
        self.assertEqual(len(archives), 2)
        self.assertEqual({p.name for p in archives}, {
            'results.archive.20261012_0', 'results.archive.20261012_1'})
        self.assertTrue(all((p / 'run/compare/done').exists() for p in archives))

    def test_missing_input_preserves_previous_run(self):
        self.successful()
        (self.root / 'design.gds').unlink()
        self.assertNotEqual(self.run_mode().returncode, 0)
        self.assertTrue((self.out / 'compare/done').exists())

    def test_lock_and_missing_previous_run(self):
        self.assertNotEqual(self.run_mode('compare').returncode, 0)
        self.assertFalse(Path(str(self.out) + '.lock').exists())
        Path(str(self.out) + '.lock').mkdir()
        self.assertNotEqual(self.run_mode().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_help_without_config_or_tools(self):
        self.config.write_text('echo CONFIG_WAS_EXECUTED\nexit 99\n')
        for runner in (RUNNER, RUNNER.with_name('run_lvs')):
            for flag in ('help', '--help', '-h'):
                with self.subTest(runner=runner.name, flag=flag):
                    result = subprocess.run(
                        [str(runner), flag, str(self.config)], cwd=self.root,
                        env=dict(os.environ, PATH='/usr/bin:/bin'), text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertIn('extraction_compare', result.stdout)
                    self.assertNotIn('CONFIG_WAS_EXECUTED', result.stdout)
        self.assertFalse(self.out.exists())
        self.assertFalse(self.trace.exists())

    def test_invalid_mode_before_config(self):
        self.config.unlink()
        result = self.run_mode('typo')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Usage:', result.stdout)

    def test_extraction_nonzero_with_fresh_output_continues(self):
        result = self.run_mode(FAIL_AFTER_OUTPUT='extraction')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('WARNING: extraction exited with code 7', result.stdout)
        self.assertEqual(self.trace.read_text().splitlines(), ['v2cdl', 'extraction', 'compare'])
        self.assertIn('exit_code=7', (self.out / 'extraction/done').read_text())
        self.assertTrue((self.out / 'compare/done').exists())
        self.successful('compare')

    def test_extraction_strict_mode_rejects_nonzero_with_output(self):
        with self.config.open('a') as config:
            config.write('set EXTRACTION_REQUIRE_ZERO_EXIT = 1\n')
        result = self.run_mode(FAIL_AFTER_OUTPUT='extraction')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('strict mode', result.stdout)
        self.assertEqual(self.trace.read_text().splitlines(), ['v2cdl', 'extraction'])
        self.assertFalse((self.out / 'extraction/done').exists())
        self.assertFalse((self.out / 'compare/done').exists())

    def test_failed_extraction_cannot_reuse_old_output(self):
        self.successful()
        self.trace.write_text('')
        result = self.run_mode('extraction_compare', FAIL_STAGE='extraction')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.trace.read_text().splitlines(), ['extraction'])
        self.assertFalse((self.out / 'extraction/demo.spi').exists())
        self.assertFalse((self.out / 'extraction/done').exists())
        self.assertFalse((self.out / 'compare/done').exists())

    def test_zero_exit_without_extraction_output_fails(self):
        result = self.run_mode(EMPTY_STAGE='extraction')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.trace.read_text().splitlines(), ['v2cdl', 'extraction'])
        self.assertFalse((self.out / 'extraction/done').exists())

    def test_nonzero_conversion_or_compare_still_fails_with_output(self):
        for stage in ('v2cdl', 'compare'):
            with self.subTest(stage=stage):
                result = self.run_mode(FAIL_AFTER_OUTPUT=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.out / stage / 'done').exists())

    def test_archive_date_format(self):
        self.successful()
        self.successful()
        archive, = self.root.glob('results.archive.*')
        self.assertRegex(archive.name, r'^results\.archive\.\d{8}_0$')

    def test_archive_index_skips_existing_directory_and_symlink(self):
        date = self.root / 'date'
        date.write_text('#!/bin/sh\necho 20261012\n')
        date.chmod(0o755)
        first = self.root / 'results.archive.20261012_0'
        first.mkdir()
        (first / 'keep').write_text('preserved')
        second = self.root / 'results.archive.20261012_1'
        second.symlink_to(self.root / 'nonexistent')
        self.successful()
        self.successful()
        self.assertEqual((first / 'keep').read_text(), 'preserved')
        self.assertTrue(second.is_symlink())
        self.assertTrue((self.root / 'results.archive.20261012_2/run/compare/done').exists())

    def test_quiet_mode_saves_stdout_and_stderr_without_echoing(self):
        result = self.run_mode()
        self.assertEqual(result.returncode, 0, result.stdout)
        for stage in ('v2cdl', 'extraction', 'compare'):
            log = (self.out / stage / 'log').read_text()
            for stream in ('stdout', 'stderr'):
                message = f'{stage} {stream}'
                self.assertIn(message, log)
                self.assertNotIn(message, result.stdout)

    def test_verbose_flags_show_and_save_all_tool_output(self):
        for flag in ('-v', '-verbose', '--verbose'):
            with self.subTest(flag=flag):
                result = self.run_mode(options=(flag,))
                self.assertEqual(result.returncode, 0, result.stdout)
                for stage in ('v2cdl', 'extraction', 'compare'):
                    log = (self.out / stage / 'log').read_text()
                    for stream in ('stdout', 'stderr'):
                        self.assertIn(f'{stage} {stream}', result.stdout)
                        self.assertIn(f'{stage} {stream}', log)

    def test_verbose_flag_after_config_and_default_mode(self):
        for arguments in (
                ['full', str(self.config), '-v'],
                ['-v', 'full', str(self.config)],
                ['full', '-v', str(self.config)],
                ['-v']):
            with self.subTest(arguments=arguments):
                shutil.copyfile(self.config, self.root / 'config.local.csh')
                result = subprocess.run(
                    [str(RUNNER), *arguments], cwd=self.root, env=self.env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn('compare stderr', result.stdout)

    def test_verbose_failures_are_not_hidden_by_logging(self):
        for stage in ('v2cdl', 'extraction', 'compare'):
            with self.subTest(stage=stage):
                result = self.run_mode(options=('-v',), FAIL_STAGE=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'{stage} stderr', result.stdout)
                self.assertFalse((self.out / 'compare/done').exists())
        result = self.run_mode(options=('-v',), FAIL_AFTER_OUTPUT='extraction')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('WARNING: extraction exited with code 7', result.stdout)
        self.assertIn('compare stderr', result.stdout)
        self.assertIn('exit_code=7', (self.out / 'extraction/done').read_text())

    def test_unknown_option_fails_before_loading_config(self):
        self.config.write_text('echo CONFIG_WAS_EXECUTED\nexit 99\n')
        result = self.run_mode(options=('--typo',))
        self.assertEqual(result.returncode, 2)
        self.assertIn('unknown option', result.stdout)
        self.assertNotIn('CONFIG_WAS_EXECUTED', result.stdout)

    def test_verbose_output_is_live_while_tool_is_running(self):
        # A gate blocks conversion until its first output reaches the parent.
        # This distinguishes streaming from printing a completed log afterward.
        gate = self.root / 'continue'
        tool = self.root / 'v2lvs'
        original = tool.read_text()
        tool.write_text(original.replace('out=\n', '''printf 'STREAM_READY\\n'
while [ ! -f "$STREAM_GATE" ]; do sleep 0.05; done
out=
'''))
        process = subprocess.Popen(
            [str(RUNNER), '-v', 'full', str(self.config)], cwd=self.root,
            env=dict(self.env, STREAM_GATE=str(gate)),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                captured = b''
                while b'STREAM_READY\n' not in captured:
                    self.assertTrue(selector.select(timeout=10), 'Tool output did not stream')
                    chunk = os.read(process.stdout.fileno(), 4096)
                    self.assertTrue(chunk, captured.decode())
                    captured += chunk
                self.assertIsNone(process.poll(), 'Run finished before the gate was released')
            gate.touch()
            remaining, _ = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, (captured + remaining).decode())
            self.assertIn('STREAM_READY', (self.out / 'v2cdl/log').read_text())
        finally:
            gate.touch()
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=15)

if __name__ == '__main__':
    unittest.main()
