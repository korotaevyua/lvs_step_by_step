import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'run_lvs'

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
[ "$FAIL_STAGE" = "$stage" ] && exit 7
if [ -n "$out" ] && [ "$EMPTY_STAGE" != "$stage" ]; then printf 'netlist\\n' > "$out"; fi
exit 0
''')
            f.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.root}:' + os.environ['PATH'], TRACE=str(self.trace))

    def run_mode(self, mode='full', **env):
        return subprocess.run(['csh', '-f', str(RUNNER), mode, str(self.config)],
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
        self.successful()
        self.successful()
        self.successful()
        archives = list(self.root.glob('results.archive.*'))
        self.assertEqual(len(archives), 2)
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

if __name__ == '__main__':
    unittest.main()
