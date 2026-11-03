"""Exercise the shipped templates as an installed project's ./dev command."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


TEMPLATES = Path(__file__).resolve().parents[1] / "skills/dev-tool/templates"


class EnvironmentProfilesTest(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="dev-tool profiles ")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        commands = self.root / ".dev/commands"
        commands.mkdir(parents=True)
        shutil.copy(TEMPLATES / "dev", self.root / "dev")
        (self.root / "dev").chmod(0o755)
        shutil.copy(TEMPLATES / "dispatch.sh", self.root / ".dev/dispatch.sh")
        shutil.copy(TEMPLATES / "commands/env.sh", commands / "env.sh")
        shutil.copy(TEMPLATES / "DEV_TOOL.md", self.root / "DEV_TOOL.md")
        (commands / "server.sh").write_text(
            "dev_describe() { echo server; }\n"
            "dev_verbs() { dev_verb up '' server; }\n"
            "dev_run() { printf '%s' \"$PROFILE_TEST_VALUE\"; }\n"
        )
        self.git("init", "--quiet")
        (self.root / ".gitignore").write_text(".dev/environments/\n")

    def git(self, *arguments):
        return subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            check=True, capture_output=True,
        )

    def dev(self, *arguments, input=None, expected=0, environment=None):
        result = subprocess.run(
            [str(self.root / "dev"), *arguments],
            cwd=self.root,
            input=input,
            text=True,
            capture_output=True,
            env=environment,
            start_new_session=True,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def profile(self, name="local"):
        return self.root / f".dev/environments/{name}.env"

    def create(self, name="local"):
        self.dev("env", "create", name)

    def test_create_list_and_refuse_overwrite(self):
        self.dev("env", "list")
        self.create()
        self.assertEqual(self.profile().stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.dev("env", "list").stdout, "local\n")
        self.profile().write_text("KEEP=value\n")
        self.dev("env", "create", "local", expected=1)
        self.assertEqual(self.profile().read_text(), "KEEP=value\n")

    def test_set_replace_mask_and_literal_values(self):
        self.create()
        marker = self.root / "should-not-exist"
        value = f" space = $(touch '{marker}') `false` $HOME \\\" # end "
        self.dev("env", "set", "local", "PROFILE_TEST_VALUE", "--stdin", input=value)
        self.dev("env", "set", "local", "EMPTY", "--stdin", input="\n")
        result = self.dev("env", "show", "local")
        self.assertEqual(result.stdout, "PROFILE_TEST_VALUE=<hidden>\nEMPTY=<hidden>\n")
        result = self.dev(
            "env", "run", "local", "--", "./dev", "server", "up",
            environment={**os.environ, "PROFILE_TEST_VALUE": "parent"},
        )
        self.assertEqual(result.stdout, value)
        self.assertFalse(marker.exists())
        self.dev("env", "set", "local", "PROFILE_TEST_VALUE", "--stdin", input="new\n")
        self.assertEqual(self.profile().read_text(), "EMPTY=\nPROFILE_TEST_VALUE=new\n")
        self.assertEqual(self.profile().stat().st_mode & 0o777, 0o600)

    def test_profiles_inherit_environment_and_preserve_arguments(self):
        self.create()
        self.create("remote")
        self.profile().write_text("# comment\n\nPROFILE_TEST_VALUE=local\n")
        self.profile("remote").write_text("PROFILE_TEST_VALUE=remote")
        inherited = {**os.environ, "PROFILE_TEST_VALUE": "parent", "INHERITED": "kept"}
        for profile in ("local", "remote"):
            result = self.dev(
                "env", "run", profile, "--", "bash", "-c",
                'printf "%s|%s|%s|%s" "$PROFILE_TEST_VALUE" "$INHERITED" "$1" "$2"',
                "test", "with spaces", "", environment=inherited,
            )
            self.assertEqual(result.stdout, f"{profile}|kept|with spaces|")
        self.assertEqual(inherited["PROFILE_TEST_VALUE"], "parent")

    def test_child_exit_status_is_preserved(self):
        self.create()
        self.dev("env", "run", "local", "--", "bash", "-c", "exit 23", expected=23)

    def test_gitignore_required_and_tracked_files_refused(self):
        (self.root / ".gitignore").write_text("")
        self.dev("env", "create", "local", expected=1)
        self.assertFalse(self.profile().exists())
        (self.root / ".gitignore").write_text(".dev/environments/\n")
        self.create()
        self.git("add", "--force", ".dev/environments/local.env")
        for arguments in (
            ("set", "local", "KEY", "--stdin"),
            ("show", "local"), ("run", "local", "--", "true"),
        ):
            self.dev("env", *arguments, input="secret\n", expected=1)
        self.assertEqual(self.profile().read_text(), "")

    def test_invalid_names_and_symbolic_links_refused(self):
        for name in ("../outside", "-local", "", "a/b", "a.env"):
            self.dev("env", "create", name, expected=1)
        self.create()
        target = self.root / "target"
        target.write_text("KEY=secret\n")
        self.profile().unlink()
        self.profile().symlink_to(target)
        self.dev("env", "set", "local", "KEY", "--stdin", input="new\n", expected=1)
        self.dev("env", "run", "local", "--", "true", expected=1)
        self.assertEqual(target.read_text(), "KEY=secret\n")
        self.profile().unlink()
        self.profile().parent.rmdir()
        self.profile().parent.symlink_to(self.root, target_is_directory=True)
        self.dev("env", "create", "local", expected=1)

    def test_invalid_files_fail_before_execution_without_values(self):
        self.create()
        marker = self.root / "executed"
        for content in (
            "KEY=secret\ninvalid secret\n", "KEY=secret\nKEY=duplicate\n",
            "export KEY=secret\n", "KEY=secret\x00suffix\n", "KEY=secret\r\n",
        ):
            with self.subTest(content=repr(content)):
                self.profile().write_text(content)
                result = self.dev(
                    "env", "run", "local", "--", "touch", str(marker), expected=1,
                )
                self.assertNotIn("secret", result.stdout + result.stderr)
                self.assertFalse(marker.exists())
                self.dev("env", "show", "local", expected=1)

    def test_stdin_validation_and_no_terminal(self):
        self.create()
        for value in ("", "one\ntwo\n", "one\n\n", "one\r\n", "one\x00two"):
            self.dev("env", "set", "local", "KEY", "--stdin", input=value, expected=1)
            self.assertEqual(self.profile().read_text(), "")
        self.dev("env", "set", "local", "KEY", expected=1)
        self.dev("env", "set", "local", "INVALID-KEY", "--stdin", input="value", expected=1)

    def test_discovery_completion_and_document_generation(self):
        self.assertIn("env", self.dev().stdout)
        self.assertIn("create", self.dev("env").stdout)
        self.dev("env", "unknown", expected=1)
        self.assertIn("env", self.dev("complete").stdout.splitlines())
        self.assertEqual(self.dev("complete", "env", "set").stdout, "--stdin\n")
        self.assertEqual(self.dev("complete", "nonexistent").stdout, "")
        self.dev("docs")
        first = (self.root / "DEV_TOOL.md").read_bytes()
        self.dev("docs")
        self.assertEqual(first, (self.root / "DEV_TOOL.md").read_bytes())
        self.assertIn(b"env run", first)

    def test_missing_profiles_and_usage_errors(self):
        for arguments in (
            ("create",), ("create", "local", "extra"), ("list", "extra"),
            ("set", "missing", "KEY", "--stdin"), ("show", "missing"),
            ("run", "missing", "--", "true"), ("run", "local", "true"),
            ("run", "local", "--"), ("set", "local", "KEY", "secret"),
        ):
            self.dev("env", *arguments, input="value\n", expected=1)


if __name__ == "__main__":
    unittest.main()
