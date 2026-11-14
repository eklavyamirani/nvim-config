//! Command-line interface. Every command takes the document path; `--json`
//! gives machine output (Neovim always uses it), the default is readable text.

use crate::store::{self, Result, Store};
use clap::{Parser, Subcommand};
use serde_json::{Value, json};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Parser)]
#[command(
    name = "coauthor",
    version,
    about = "Comment threads on a document, shared by an editor and a coding agent.",
    long_about = "Comment threads on a document, shared by an editor and a coding agent.\n\n\
        Threads live in one file per document in the state directory, never in the document. \
        This command is the only writer of those files."
)]
struct Cli {
    /// Print machine-readable JSON instead of text.
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print the threads file of DOC.
    Path { doc: PathBuf },
    /// Re-key OLD's threads to NEW after moving or renaming the document.
    Mv { old: PathBuf, new: PathBuf },
    /// Delete DOC's threads file.
    Rm { doc: PathBuf },
    /// Delete threads files whose document no longer exists.
    Prune {
        /// List what would be deleted without deleting it.
        #[arg(long)]
        dry_run: bool,
    },
}

pub fn main() -> i32 {
    let cli = Cli::parse();
    match run(cli.command, cli.json) {
        Ok(output) => {
            print!("{output}");
            0
        }
        Err(err) => {
            eprintln!("coauthor: {err}");
            1
        }
    }
}

fn run(command: Command, json: bool) -> Result<String> {
    let store = Store::open()?;
    match command {
        Command::Path { doc } => path(&store, &doc, json),
        Command::Mv { old, new } => mv(&store, &old, &new, json),
        Command::Rm { doc } => rm(&store, &doc, json),
        Command::Prune { dry_run } => prune(&store, dry_run, json),
    }
}

fn out(json: bool, value: Value, text: String) -> String {
    if json { format!("{value}\n") } else { format!("{text}\n") }
}

fn display(path: &Path) -> String {
    path.display().to_string()
}

fn path(store: &Store, doc: &Path, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let path = store.path_for(&canonical);
    let exists = path.is_file();
    Ok(out(json, json!({ "doc": canonical, "path": display(&path), "exists": exists }), display(&path)))
}

fn mv(store: &Store, old: &Path, new: &Path, json: bool) -> Result<String> {
    let (old, new) = (store::canonical_doc(old)?, store::canonical_doc(new)?);
    let (from, to) = (store.path_for(&old), store.path_for(&new));
    let _lock = store.lock()?;
    let Some((mut file, _)) = store.load(&old)? else {
        return Err(format!("{old} has no threads"));
    };
    if old == new {
        return Ok(out(json, json!({ "from": display(&from), "to": display(&to) }), format!("{old} unchanged")));
    }
    if to.exists() {
        return Err(format!("{new} already has threads ({}); remove them first with `coauthor rm`", to.display()));
    }
    file.doc = new.clone();
    store.write(&to, &file)?;
    fs::remove_file(&from).map_err(|err| format!("{}: {err}", from.display()))?;
    Ok(out(json, json!({ "from": display(&from), "to": display(&to) }), format!("Moved threads of {old} to {new}")))
}

fn rm(store: &Store, doc: &Path, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let path = store.path_for(&canonical);
    let _lock = store.lock()?;
    // Refuses a colliding file that belongs to another document.
    let removed = store.load(&canonical)?.is_some();
    if removed {
        fs::remove_file(&path).map_err(|err| format!("{}: {err}", path.display()))?;
    }
    let text = if removed { format!("Removed {}", path.display()) } else { format!("{canonical} has no threads") };
    Ok(out(json, json!({ "path": display(&path), "removed": removed }), text))
}

fn prune(store: &Store, dry_run: bool, json: bool) -> Result<String> {
    let _lock = store.lock()?;
    let (mut removed, mut skipped) = (Vec::new(), Vec::new());
    for path in store.all()? {
        let doc = match store.read(&path) {
            Ok(Some((file, _))) => file.doc,
            Ok(None) => continue,
            Err(err) => {
                skipped.push(json!({ "path": display(&path), "reason": err }));
                continue;
            }
        };
        if Path::new(&doc).exists() {
            continue;
        }
        if !dry_run {
            fs::remove_file(&path).map_err(|err| format!("{}: {err}", path.display()))?;
        }
        removed.push(json!({ "path": display(&path), "doc": doc }));
    }
    let verb = if dry_run { "Would remove" } else { "Removed" };
    let mut text: Vec<String> = removed
        .iter()
        .map(|entry| {
            format!(
                "{verb} {} ({} no longer exists)",
                entry["path"].as_str().unwrap_or(""),
                entry["doc"].as_str().unwrap_or("")
            )
        })
        .collect();
    text.extend(skipped.iter().map(|entry| {
        format!("Skipped {}: {}", entry["path"].as_str().unwrap_or(""), entry["reason"].as_str().unwrap_or(""))
    }));
    if text.is_empty() {
        text.push("Nothing to prune".into());
    }
    Ok(out(json, json!({ "removed": removed, "skipped": skipped, "dry_run": dry_run }), text.join("\n")))
}

#[cfg(test)]
mod tests {
    use super::Cli;
    use clap::CommandFactory;

    #[test]
    fn cli_definition_is_valid() {
        Cli::command().debug_assert();
    }
}
