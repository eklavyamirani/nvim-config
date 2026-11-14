//! Storage, locking and the housekeeping commands, through the real binary
//! where a command exists and through the library otherwise.

mod common;

use coauthor::format::{Author, Message, Section, Thread, ThreadsFile};
use coauthor::store::{self, Store};
use common::Env;
use std::collections::BTreeSet;
use std::fs;

fn thread(id: u32, text: &str) -> Thread {
    Thread {
        id,
        lines: (1, 1),
        drifted: false,
        resolved: false,
        anchor: vec!["# Title".into()],
        was: None,
        messages: vec![Message { author: Author::Me, text: text.into() }],
    }
}

fn add_thread(env: &Env, doc: &str, text: &str) {
    let canonical = store::canonical_doc(&env.path(doc)).unwrap();
    Store::at(env.state.clone())
        .unwrap()
        .update(&canonical, |file: &mut ThreadsFile| {
            let id = file.next_id();
            file.sections.push(Section::Thread(thread(id, text)));
            Ok(())
        })
        .unwrap();
}

#[test]
fn path_reports_the_keyed_file_without_creating_it() {
    let env = Env::new();
    env.write_doc("docs/rollout.md", "# Title\n");
    let out = env.json(&["path", "docs/rollout.md"]);
    let path = out["path"].as_str().unwrap();
    assert!(path.starts_with(env.state.to_str().unwrap()), "{path} not in {}", env.state.display());
    assert!(path.contains("rollout.md-") && path.ends_with(".threads.md"));
    assert_eq!(out["exists"], false);
    assert!(!std::path::Path::new(path).exists());
    // The state directory itself is created, for sandboxed agents.
    assert!(env.state.is_dir());
    // Absolute and relative spellings key to the same file.
    let absolute = env.json(&["path", env.path("docs/rollout.md").to_str().unwrap()]);
    assert_eq!(absolute["path"], out["path"]);
    let text = env.ok(&["path", "docs/./rollout.md"]);
    assert_eq!(text.trim(), path);

    add_thread(&env, "docs/rollout.md", "hello");
    assert_eq!(env.json(&["path", "docs/rollout.md"])["exists"], true);
    let file = fs::read_to_string(path).unwrap();
    assert!(file.contains(&format!("doc: {}", out["doc"].as_str().unwrap())), "{file}");
}

#[test]
fn mv_rekeys_threads_to_the_new_path() {
    let env = Env::new();
    env.write_doc("old.md", "# Title\n");
    add_thread(&env, "old.md", "keep me");
    let old_path = env.json(&["path", "old.md"])["path"].as_str().unwrap().to_string();
    fs::rename(env.path("old.md"), env.path("new.md")).unwrap();

    let moved = env.json(&["mv", "old.md", "new.md"]);
    assert_eq!(moved["from"], old_path.as_str());
    let new = env.json(&["path", "new.md"]);
    assert_eq!(new["exists"], true);
    assert_eq!(moved["to"], new["path"]);
    assert!(!std::path::Path::new(&old_path).exists());
    let text = fs::read_to_string(new["path"].as_str().unwrap()).unwrap();
    assert!(text.contains(&format!("doc: {}", new["doc"].as_str().unwrap())));
    assert!(text.contains("**me:** keep me"));

    // Refuses to overwrite existing threads or to move nothing.
    env.write_doc("other.md", "# Title\n");
    add_thread(&env, "other.md", "other");
    assert!(env.fails(&["mv", "new.md", "other.md"]).contains("already has threads"));
    assert!(env.fails(&["mv", "old.md", "new.md"]).contains("has no threads"));
}

#[test]
fn rm_deletes_one_documents_threads() {
    let env = Env::new();
    env.write_doc("a.md", "# Title\n");
    env.write_doc("b.md", "# Title\n");
    add_thread(&env, "a.md", "a");
    add_thread(&env, "b.md", "b");
    assert_eq!(env.json(&["rm", "a.md"])["removed"], true);
    assert_eq!(env.json(&["path", "a.md"])["exists"], false);
    assert_eq!(env.json(&["path", "b.md"])["exists"], true);
    // Idempotent.
    assert_eq!(env.json(&["rm", "a.md"])["removed"], false);
    assert!(env.ok(&["rm", "a.md"]).contains("has no threads"));
}

#[test]
fn prune_deletes_threads_of_missing_documents_only() {
    let env = Env::new();
    env.write_doc("kept.md", "# Title\n");
    env.write_doc("gone.md", "# Title\n");
    add_thread(&env, "kept.md", "a");
    add_thread(&env, "gone.md", "b");
    let gone = env.json(&["path", "gone.md"])["path"].as_str().unwrap().to_string();
    fs::remove_file(env.path("gone.md")).unwrap();
    // Not ours: a file that is not a threads file is never touched.
    fs::write(env.state.join("stray.threads.md"), "hand written\n").unwrap();

    let dry = env.json(&["prune", "--dry-run"]);
    assert_eq!(dry["removed"].as_array().unwrap().len(), 1);
    assert!(std::path::Path::new(&gone).exists());

    let pruned = env.json(&["prune"]);
    assert_eq!(pruned["removed"][0]["path"], gone.as_str());
    assert_eq!(pruned["skipped"].as_array().unwrap().len(), 1);
    assert!(!std::path::Path::new(&gone).exists());
    assert_eq!(env.json(&["path", "kept.md"])["exists"], true);
    assert!(env.state.join("stray.threads.md").exists());
    assert!(env.ok(&["prune"]).contains("Skipped"));
}

#[test]
fn concurrent_writers_never_lose_an_update() {
    let env = Env::new();
    env.write_doc("busy.md", "# Title\n");
    let writers = 8;
    let per_writer = 25;
    std::thread::scope(|scope| {
        for writer in 0..writers {
            let env = &env;
            scope.spawn(move || {
                for n in 0..per_writer {
                    add_thread(env, "busy.md", &format!("writer {writer} comment {n}"));
                }
            });
        }
    });
    let canonical = store::canonical_doc(&env.path("busy.md")).unwrap();
    let (file, _) = Store::at(env.state.clone()).unwrap().load(&canonical).unwrap().unwrap();
    let ids: BTreeSet<u32> = file.threads().map(|thread| thread.id).collect();
    assert_eq!(ids, (1..=writers * per_writer).collect());
    let texts: BTreeSet<&str> = file.threads().map(|thread| thread.messages[0].text.as_str()).collect();
    assert_eq!(texts.len() as u32, writers * per_writer);
    // No temp file is left behind.
    let leftovers: Vec<_> = fs::read_dir(&env.state)
        .unwrap()
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_name().to_string_lossy().ends_with(".tmp"))
        .collect();
    assert!(leftovers.is_empty());
}

#[test]
fn a_colliding_threads_file_is_refused() {
    let env = Env::new();
    env.write_doc("doc.md", "# Title\n");
    let path = env.json(&["path", "doc.md"])["path"].as_str().unwrap().to_string();
    fs::write(&path, "<!-- coauthor v1\ndoc: /elsewhere/doc.md\nround: none -->\n").unwrap();
    assert!(env.fails(&["rm", "doc.md"]).contains("collision"));
    assert!(std::path::Path::new(&path).exists());
}
