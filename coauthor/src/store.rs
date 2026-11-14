//! Where threads files live and how they are written.
//!
//! One threads file per document, in the state directory, named after the
//! document's canonical absolute path. Every write is a read-modify-write under
//! one exclusive advisory lock for the whole state directory, then
//! write-to-temp and rename, so a reader never sees a half-written file.

use crate::format::{self, ThreadsFile};
use crate::sha256;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write as _};
use std::path::{Component, Path, PathBuf};

pub type Result<T> = std::result::Result<T, String>;

pub const EXTENSION: &str = ".threads.md";
const LOCK_FILE: &str = ".lock";

/// `$XDG_STATE_HOME/coauthor` (default `~/.local/state/coauthor`), or
/// `%LOCALAPPDATA%\coauthor` on Windows.
pub fn state_dir() -> Result<PathBuf> {
    state_dir_from(|name| std::env::var_os(name).filter(|value| !value.is_empty()).map(PathBuf::from))
}

fn state_dir_from(env: impl Fn(&str) -> Option<PathBuf>) -> Result<PathBuf> {
    if cfg!(windows) {
        return env("LOCALAPPDATA")
            .map(|dir| dir.join("coauthor"))
            .ok_or_else(|| "LOCALAPPDATA is not set".to_string());
    }
    // The XDG spec says to ignore relative values.
    if let Some(dir) = env("XDG_STATE_HOME").filter(|dir| dir.is_absolute()) {
        return Ok(dir.join("coauthor"));
    }
    env("HOME")
        .map(|home| home.join(".local").join("state").join("coauthor"))
        .ok_or_else(|| "neither XDG_STATE_HOME nor HOME is set".to_string())
}

/// `std::fs::canonicalize` returns Windows verbatim paths (`\\?\C:\…`); strip
/// the prefix so the key and the recorded path are the ordinary form.
pub fn strip_verbatim(path: &str) -> String {
    if let Some(rest) = path.strip_prefix(r"\\?\UNC\") {
        format!(r"\\{rest}")
    } else if let Some(rest) = path.strip_prefix(r"\\?\") {
        rest.to_string()
    } else {
        path.to_string()
    }
}

/// The canonical absolute path of a document. The document need not exist
/// (`rm` and `mv` work on moved or deleted ones): the deepest existing ancestor
/// is canonicalized and the rest appended.
pub fn canonical_doc(doc: &Path) -> Result<String> {
    let absolute = std::path::absolute(doc).map_err(|err| format!("{}: {err}", doc.display()))?;
    // Lexically, like `std::path::absolute` already does on Windows.
    let mut normal = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normal.pop();
            }
            other => normal.push(other),
        }
    }
    let mut existing = normal.as_path();
    let mut tail = Vec::new();
    let mut path = loop {
        if let Ok(path) = fs::canonicalize(existing) {
            break path;
        }
        match (existing.parent(), existing.file_name()) {
            (Some(parent), Some(name)) => {
                tail.push(name.to_os_string());
                existing = parent;
            }
            _ => break existing.to_path_buf(),
        }
    };
    path.extend(tail.iter().rev());
    let path = path.to_str().ok_or_else(|| format!("{}: path is not valid UTF-8", doc.display()))?;
    Ok(strip_verbatim(path))
}

/// `<basename>-<first 8 hex of sha256(path)>.threads.md`. Splits on both
/// separators so the result does not depend on the platform it runs on.
pub fn threads_file_name(canonical: &str) -> String {
    let base = canonical.rsplit(['/', '\\']).next().unwrap_or(canonical);
    // Keep the name well under the 255-byte limit of common filesystems.
    let mut base: String = base.chars().take(100).collect();
    if base.is_empty() {
        base.push_str("doc");
    }
    format!("{base}-{}{EXTENSION}", &sha256::hex(canonical.as_bytes())[..8])
}

pub struct Store {
    pub dir: PathBuf,
}

/// Held for the duration of a read-modify-write; released on drop.
pub struct Lock(#[allow(dead_code)] File);

impl Store {
    /// The state directory is created on first use, so a sandboxed agent that
    /// may only write to existing directories finds it there.
    pub fn open() -> Result<Store> {
        let dir = state_dir()?;
        fs::create_dir_all(&dir).map_err(|err| format!("{}: {err}", dir.display()))?;
        Ok(Store { dir })
    }

    pub fn at(dir: PathBuf) -> Result<Store> {
        fs::create_dir_all(&dir).map_err(|err| format!("{}: {err}", dir.display()))?;
        Ok(Store { dir })
    }

    pub fn path_for(&self, canonical: &str) -> PathBuf {
        self.dir.join(threads_file_name(canonical))
    }

    pub fn lock(&self) -> Result<Lock> {
        let path = self.dir.join(LOCK_FILE);
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(&path)
            .map_err(|err| format!("{}: {err}", path.display()))?;
        file.lock().map_err(|err| format!("{}: {err}", path.display()))?;
        Ok(Lock(file))
    }

    /// Reads a threads file; `None` when it does not exist. Also returns the raw
    /// bytes' revision.
    pub fn read(&self, path: &Path) -> Result<Option<(ThreadsFile, String)>> {
        let bytes = match fs::read(path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(err) => return Err(format!("{}: {err}", path.display())),
        };
        let text = String::from_utf8(bytes).map_err(|_| format!("{}: not valid UTF-8", path.display()))?;
        let file = format::parse(&text).map_err(|err| format!("{}: {err}", path.display()))?;
        Ok(Some((file, sha256::hex(text.as_bytes()))))
    }

    /// Loads the threads for `canonical`, checking the file really belongs to it.
    pub fn load(&self, canonical: &str) -> Result<Option<(ThreadsFile, String)>> {
        let path = self.path_for(canonical);
        let loaded = self.read(&path)?;
        if let Some((file, _)) = &loaded
            && file.doc != canonical
        {
            return Err(format!(
                "{} belongs to {}, not {canonical} (name hash collision); move one of the documents",
                path.display(),
                file.doc
            ));
        }
        Ok(loaded)
    }

    /// Writes `file` atomically; returns the written bytes' revision.
    pub fn write(&self, path: &Path, file: &ThreadsFile) -> Result<String> {
        let text = format::render(file);
        write_atomic(path, text.as_bytes()).map_err(|err| format!("{}: {err}", path.display()))?;
        Ok(sha256::hex(text.as_bytes()))
    }

    /// Read-modify-write of one document's threads under the lock. `change`
    /// receives the current threads (a new, empty file when there are none).
    pub fn update<T>(
        &self,
        canonical: &str,
        change: impl FnOnce(&mut ThreadsFile) -> Result<T>,
    ) -> Result<(T, ThreadsFile, String)> {
        let _lock = self.lock()?;
        let mut file = match self.load(canonical)? {
            Some((file, _)) => file,
            None => ThreadsFile::new(canonical),
        };
        let value = change(&mut file)?;
        let revision = self.write(&self.path_for(canonical), &file)?;
        Ok((value, file, revision))
    }

    /// Every threads file in the state directory.
    pub fn all(&self) -> Result<Vec<PathBuf>> {
        let mut paths = Vec::new();
        for entry in fs::read_dir(&self.dir).map_err(|err| format!("{}: {err}", self.dir.display()))? {
            let path = entry.map_err(|err| err.to_string())?.path();
            let name = path.file_name().and_then(|name| name.to_str()).unwrap_or("");
            if name.ends_with(EXTENSION) && !name.starts_with('.') {
                paths.push(path);
            }
        }
        paths.sort();
        Ok(paths)
    }
}

pub fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or(Path::new("."));
    let name = path.file_name().and_then(|name| name.to_str()).unwrap_or("threads");
    let temp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
    let result = (|| {
        let mut file = File::create(&temp)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        rename(&temp, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

/// On Windows a rename onto a file another process has open (a virus scanner,
/// an editor reading it) fails with access denied for a moment; retry briefly.
fn rename(from: &Path, to: &Path) -> io::Result<()> {
    let mut attempts = 0;
    loop {
        match fs::rename(from, to) {
            Err(err) if cfg!(windows) && err.kind() == io::ErrorKind::PermissionDenied && attempts < 40 => {
                attempts += 1;
                std::thread::sleep(std::time::Duration::from_millis(25));
            }
            result => return result,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verbatim_prefixes_are_stripped() {
        assert_eq!(strip_verbatim(r"\\?\C:\Users\me\doc.md"), r"C:\Users\me\doc.md");
        assert_eq!(strip_verbatim(r"\\?\UNC\server\share\doc.md"), r"\\server\share\doc.md");
        assert_eq!(strip_verbatim("/home/me/doc.md"), "/home/me/doc.md");
    }

    #[test]
    fn file_names_are_keyed_by_the_full_path() {
        let unix = threads_file_name("/home/me/src/project/docs/rollout.md");
        assert_eq!(
            unix,
            format!("rollout.md-{}.threads.md", &sha256::hex(b"/home/me/src/project/docs/rollout.md")[..8])
        );
        let windows = threads_file_name(r"C:\Users\me\src\project\docs\rollout.md");
        assert!(windows.starts_with("rollout.md-") && windows.ends_with(".threads.md"), "{windows}");
        // Same name, different directory (another worktree): different file.
        assert_ne!(threads_file_name("/a/rollout.md"), threads_file_name("/b/rollout.md"));
        assert_eq!(threads_file_name("/a/rollout.md").len(), "rollout.md-".len() + 8 + ".threads.md".len());
        let long = format!("/a/{}.md", "x".repeat(300));
        assert!(threads_file_name(&long).len() < 128);
    }

    #[test]
    fn state_dir_follows_the_platform_convention() {
        let env = |values: &'static [(&'static str, &'static str)]| {
            move |name: &str| values.iter().find(|(key, _)| *key == name).map(|(_, value)| PathBuf::from(value))
        };
        if cfg!(windows) {
            let dir =
                state_dir_from(env(&[("LOCALAPPDATA", r"C:\Users\me\AppData\Local"), ("XDG_STATE_HOME", r"C:\x")]));
            assert_eq!(dir.unwrap(), PathBuf::from(r"C:\Users\me\AppData\Local\coauthor"));
            assert!(state_dir_from(env(&[])).is_err());
        } else {
            let dir = state_dir_from(env(&[("XDG_STATE_HOME", "/xdg/state"), ("HOME", "/home/me")]));
            assert_eq!(dir.unwrap(), PathBuf::from("/xdg/state/coauthor"));
            let dir = state_dir_from(env(&[("XDG_STATE_HOME", "relative"), ("HOME", "/home/me")]));
            assert_eq!(dir.unwrap(), PathBuf::from("/home/me/.local/state/coauthor"));
            assert!(state_dir_from(env(&[])).is_err());
        }
    }

    #[test]
    fn canonical_paths_of_missing_documents() {
        let dir = std::env::temp_dir().join(format!("coauthor-canonical-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let real = canonical_doc(&dir).unwrap();
        let missing = canonical_doc(&dir.join("gone").join("..").join("not-yet.md")).unwrap();
        assert_eq!(Path::new(&missing), Path::new(&real).join("not-yet.md"));
        assert!(!missing.starts_with(r"\\?\"));
        fs::remove_dir_all(&dir).unwrap();
    }
}
