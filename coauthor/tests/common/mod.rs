//! A private state directory and working directory per test.

#![allow(dead_code)]

use serde_json::Value;
use std::path::PathBuf;
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU32, Ordering};

static COUNTER: AtomicU32 = AtomicU32::new(0);

pub struct Env {
    pub root: PathBuf,
    pub work: PathBuf,
    /// `<state root>/coauthor`, where the binary keeps threads files.
    pub state: PathBuf,
}

impl Env {
    pub fn new() -> Env {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let root = std::env::temp_dir().join(format!("coauthor-test-{}-{id}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let work = root.join("work");
        std::fs::create_dir_all(&work).unwrap();
        // Canonical, so paths the binary prints compare equal (macOS /var -> /private/var).
        let root = std::fs::canonicalize(&root).unwrap();
        let root = PathBuf::from(coauthor::store::strip_verbatim(root.to_str().unwrap()));
        let work = root.join("work");
        let state = root.join("state").join("coauthor");
        Env { root, work, state }
    }

    pub fn path(&self, relative: &str) -> PathBuf {
        self.work.join(relative)
    }

    pub fn write_doc(&self, relative: &str, text: &str) {
        let path = self.path(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    pub fn read_doc(&self, relative: &str) -> String {
        std::fs::read_to_string(self.path(relative)).unwrap()
    }

    /// The binary, with its state directory pointed at this test's (both the
    /// Unix and the Windows variable, so the same test runs everywhere).
    pub fn command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_coauthor"));
        let state_root = self.state.parent().unwrap();
        command.current_dir(&self.work).env("XDG_STATE_HOME", state_root).env("LOCALAPPDATA", state_root);
        command
    }

    pub fn run(&self, args: &[&str]) -> Output {
        self.command().args(args).output().unwrap()
    }

    pub fn ok(&self, args: &[&str]) -> String {
        let output = self.run(args);
        assert!(output.status.success(), "coauthor {args:?} failed: {}", String::from_utf8_lossy(&output.stderr));
        String::from_utf8(output.stdout).unwrap()
    }

    pub fn json(&self, args: &[&str]) -> Value {
        let mut all = vec!["--json"];
        all.extend_from_slice(args);
        serde_json::from_str(&self.ok(&all)).unwrap()
    }

    pub fn fails(&self, args: &[&str]) -> String {
        let output = self.run(args);
        assert!(!output.status.success(), "coauthor {args:?} unexpectedly succeeded");
        String::from_utf8(output.stderr).unwrap()
    }
}

impl Drop for Env {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}
