"""Task 7 notification cache tests. Runs a fake notify-send, never posts desktop alerts."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEXLUA = shutil.which('texlua')


@unittest.skipUnless(TEXLUA, 'texlua is required for Lua notification tests')
class NotificationServiceTests(unittest.TestCase):
    def test_persistent_atomic_key_and_quoted_arguments(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = pathlib.Path(temp)
            fake = temp / 'notify-send'
            fake.write_text('#!/bin/sh\nprintf "<%s>\\n" "$@" >> "$NOTIFY_LOG"\n', encoding='utf8')
            fake.chmod(0o755)
            log = temp / 'notifications.log'
            env = dict(os.environ, XDG_CACHE_HOME=str(temp / 'cache'),
                       NOTIFY_LOG=str(log), XDG_DATA_HOME=str(temp / "data"), PATH=f'{temp}:{os.environ.get("PATH", "")}')
            lua = """
                local N = dofile('lib/Notify.lua')
                assert(N.crossed(100,101,101,15))
                assert(not N.crossed(nil,101,101,15))
                assert(not N.crossed(0,200,101,15))
                assert(not N.crossed(100,101,150,15))
                assert(N.send_once('2026-11-23:Asr:15m', "Asr's alert", "$(touch /tmp/NO_NOTIFY_INJECTION);'hello'", 1795448700) == true)
            """
            self.run_lua(lua, env)
            self.run_lua(lua.replace('== true', '== false'), env)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and not log.exists():
                time.sleep(0.02)
            self.assertTrue(log.exists())
            self.assertEqual(log.read_text().splitlines(), [
                '<--app-name=Conky Prayer Reminders>', '<--hint=boolean:transient:false>',
                '<--hint=string:desktop-entry:conky-prayer-reminders>',
                "<Asr's alert>", "<$(touch /tmp/NO_NOTIFY_INJECTION);'hello'>"
            ])
            desktop = temp / 'data' / 'applications' / 'conky-prayer-reminders.desktop'
            self.assertIn('NoDisplay=true', desktop.read_text())
            journal = (temp / 'cache' / 'conky-notifications' / 'sent.cache').read_text()
            self.assertEqual(len(journal.splitlines()), 1)
            self.assertIn('2026-11-23:Asr:15m', journal)

    @staticmethod
    def run_lua(source, env):
        with tempfile.TemporaryDirectory() as directory:
            script = pathlib.Path(directory) / 'notify_test.lua'
            script.write_text(source, encoding='utf8')
            output = subprocess.run([TEXLUA, str(script)], cwd=ROOT, text=True,
                                    env=env, capture_output=True, timeout=10)
            if output.returncode:
                raise AssertionError(output.stdout + output.stderr)


if __name__ == '__main__':
    unittest.main()
