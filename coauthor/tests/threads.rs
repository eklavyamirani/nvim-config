//! Thread commands, the anchoring ladder and agent output, through the binary.

mod common;

use common::Env;
use serde_json::Value;
use std::fs;
use std::process::Stdio;

const DOC: &str = "# Rollout\n\nThe rollout takes two weeks.\nWe start Monday.\nShip it.\n";

fn setup() -> Env {
    let env = Env::new();
    env.write_doc("docs/rollout.md", DOC);
    env
}

fn thread<'a>(state: &'a Value, id: &str) -> &'a Value {
    state["threads"].as_array().unwrap().iter().find(|thread| thread["id"] == id).unwrap()
}

fn threads_file(env: &Env) -> String {
    let path = env.json(&["path", "docs/rollout.md"])["path"].as_str().unwrap().to_string();
    fs::read_to_string(path).unwrap()
}

#[test]
fn comment_creates_threads_with_cli_assigned_ids() {
    let env = setup();
    let first = env.json(&["comment", "docs/rollout.md", "--lines", "3-3", "too", "vague"]);
    assert_eq!(first["result"]["thread"], "t1");
    let t1 = thread(&first, "t1");
    assert_eq!(t1["anchor"], serde_json::json!(["The rollout takes two weeks."]));
    assert_eq!(t1["status"], "awaiting_ai");
    assert_eq!(t1["messages"][0]["text"], "too vague");
    assert_eq!(t1["messages"][0]["id"], "t1.1");

    // Anchor text from the editor wins over the file on disk.
    let second = env.json(&[
        "comment",
        "docs/rollout.md",
        "--lines",
        "4-5",
        "--anchor-text",
        "We start Tuesday.\nShip it.",
        "which day?",
    ]);
    assert_eq!(second["result"]["thread"], "t2");
    assert_eq!(thread(&second, "t2")["anchor"], serde_json::json!(["We start Tuesday.", "Ship it."]));
    // Not on disk, so the ladder cannot find it.
    assert_eq!(thread(&second, "t2")["state"], "orphaned");
    assert!(threads_file(&env).contains("## t2 · lines 4-5\n> We start Tuesday.\n> Ship it.\n\n**me:** which day?"));

    assert!(
        env.fails(&["comment", "docs/rollout.md", "--lines", "4-5", "--anchor-text", "one line", "x"])
            .contains("1 line")
    );
    assert!(env.fails(&["comment", "docs/rollout.md", "--lines", "9-9", "x"]).contains("outside the document"));
    assert!(env.fails(&["comment", "docs/rollout.md", "--lines", "5-4", "x"]).contains("invalid line range"));
    assert!(env.fails(&["comment", "docs/rollout.md", "--lines", "1-1", " "]).contains("empty"));
}

#[test]
fn user_and_agent_replies_append_with_tags() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "give phases"]);
    let state = env.json(&["reply", "docs/rollout.md", "t1", "--edited", "3-5,8", "Split", "into", "phases."]);
    assert_eq!(state["result"]["message"], "t1.2");
    let t1 = thread(&state, "t1");
    assert_eq!(t1["status"], "awaiting_me");
    assert_eq!(t1["messages"][1]["text"], "{edited 3-5, 8} Split into phases.");
    assert_eq!(t1["messages"][1]["edited"], serde_json::json!([[3, 5], [8, 8]]));
    assert_eq!(t1["messages"][1]["body"], "Split into phases.");

    let state = env.json(&["comment", "docs/rollout.md", "--thread", "t1", "why 3?"]);
    assert_eq!(thread(&state, "t1")["status"], "awaiting_ai");
    assert_eq!(state["result"]["message"], "t1.3");

    let state = env.json(&["reply", "docs/rollout.md", "1", "--no-edit", "Because of the freeze."]);
    let reply = &thread(&state, "t1")["messages"][3];
    assert_eq!(reply["text"], "{no edit} Because of the freeze.");
    assert_eq!(reply["no_edit"], true);
    assert_eq!(reply["edited"], Value::Null);

    assert!(threads_file(&env).ends_with(
        "**me:** give phases\n\n**ai:** {edited 3-5, 8} Split into phases.\n\n**me:** why 3?\n\n**ai:** {no edit} Because of the freeze.\n"
    ));

    // Exactly one of --edited / --no-edit; valid ranges; existing threads.
    assert!(!env.run(&["reply", "docs/rollout.md", "t1", "text"]).status.success());
    assert!(!env.run(&["reply", "docs/rollout.md", "t1", "--no-edit", "--edited", "1", "x"]).status.success());
    assert!(env.fails(&["reply", "docs/rollout.md", "t1", "--edited", "3-x", "x"]).contains("invalid --edited"));
    assert!(env.fails(&["reply", "docs/rollout.md", "t9", "--no-edit", "x"]).contains("no thread t9"));
    assert!(env.fails(&["reply", "docs/rollout.md", "x1", "--no-edit", "x"]).contains("invalid thread id"));
}

#[test]
fn multi_line_messages_survive() {
    let env = setup();
    let text = "first\n\n## looks like a header\n**ai:** looks like a reply\n\\backslash";
    let state = env.json(&["comment", "docs/rollout.md", "--lines", "1-1", text]);
    assert_eq!(thread(&state, "t1")["messages"][0]["text"], text);
    let again = env.json(&["list", "docs/rollout.md"]);
    assert_eq!(thread(&again, "t1")["messages"][0]["text"], text);
    assert_eq!(thread(&again, "t1")["messages"].as_array().unwrap().len(), 1);
}

#[test]
fn resolve_hides_a_thread_until_a_new_message() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "a"]);
    env.ok(&["comment", "docs/rollout.md", "--lines", "4-4", "b"]);
    env.ok(&["move", "docs/rollout.md", "t1", "5-5"]);
    let state = env.json(&["resolve", "docs/rollout.md", "t1"]);
    assert_eq!(thread(&state, "t1")["status"], "resolved");
    assert_eq!(thread(&state, "t1")["was"], Value::Null, "resolving drops was:");
    assert_eq!(state["counts"]["resolved"], 1);
    assert!(threads_file(&env).contains("## t1 · lines 5-5 · resolved\n"));
    let listed = env.ok(&["list", "docs/rollout.md"]);
    assert!(!listed.contains("### t1") && listed.contains("### t2"));
    let state = env.json(&["comment", "docs/rollout.md", "--thread", "t1", "reopen"]);
    assert_eq!(thread(&state, "t1")["status"], "awaiting_ai");
}

#[test]
fn ladder_reports_anchored_moved_drifted_and_orphaned() {
    let env = Env::new();
    env.write_doc("d.md", "intro\nkeep\nrepeat\nmoves\ngoes away\nend\n");
    for (lines, text) in [("2-2", "anchored"), ("3-3", "drifts"), ("4-4", "moves"), ("5-5", "orphans")] {
        env.ok(&["comment", "d.md", "--lines", lines, text]);
    }
    // Lines inserted above; "repeat" now appears twice; "goes away" is gone.
    env.write_doc("d.md", "new\nrepeat\nintro\nkeep\nrepeat\nother\nmoves\nend\n");
    let state = env.json(&["list", "d.md"]);
    let check = |id: &str, lines: [u32; 2], state_name: &str| {
        let t = thread(&state, id);
        assert_eq!(t["lines"], serde_json::json!(lines), "{id}");
        assert_eq!(t["state"], state_name, "{id}");
    };
    check("t1", [4, 4], "anchored");
    check("t2", [2, 2], "drifted");
    check("t3", [7, 7], "anchored");
    check("t4", [5, 5], "orphaned");
    assert_eq!(thread(&state, "t3")["moved"], true);
    assert_eq!(thread(&state, "t4")["moved"], false);
    assert_eq!(thread(&state, "t4")["stored"], serde_json::json!([5, 5]));
    assert_eq!(state["counts"]["orphaned"], 1);
    assert_eq!(state["counts"]["drifted"], 1);
    let text = env.ok(&["list", "d.md"]);
    assert!(text.contains("### t4 · orphaned, was line 5 · awaiting ai"), "{text}");
    assert!(text.contains("### t2 · lines 2-2, drifted · awaiting ai"), "{text}");
}

#[test]
fn list_never_writes() {
    let env = setup();
    // No threads: nothing is created.
    let empty = env.json(&["list", "docs/rollout.md"]);
    assert_eq!(empty["exists"], false);
    assert_eq!(empty["revision"], Value::Null);
    assert!(!std::path::Path::new(empty["path"].as_str().unwrap()).exists());

    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "a"]);
    let before = threads_file(&env);
    env.write_doc("docs/rollout.md", &format!("inserted\n{DOC}"));
    let state = env.json(&["list", "docs/rollout.md"]);
    assert_eq!(thread(&state, "t1")["lines"], serde_json::json!([4, 4]));
    env.ok(&["list", "docs/rollout.md", "--awaiting", "ai"]);
    assert_eq!(threads_file(&env), before, "list saved re-found anchors");
    // The revision is the SHA-256 of the file's bytes, as Neovim's sha256() computes it.
    assert_eq!(state["revision"], coauthor::sha256::hex(before.as_bytes()));
}

#[test]
fn list_filters_by_whose_turn_it_is() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "a"]);
    env.ok(&["comment", "docs/rollout.md", "--lines", "4-4", "b"]);
    env.ok(&["reply", "docs/rollout.md", "t2", "--no-edit", "done"]);
    let ids = |args: &[&str]| -> Vec<String> {
        env.json(args)["threads"].as_array().unwrap().iter().map(|t| t["id"].as_str().unwrap().to_string()).collect()
    };
    assert_eq!(ids(&["list", "docs/rollout.md", "--awaiting", "ai"]), ["t1"]);
    assert_eq!(ids(&["list", "docs/rollout.md", "--awaiting", "me"]), ["t2"]);
    assert_eq!(ids(&["list", "docs/rollout.md"]), ["t1", "t2"]);
    let text = env.ok(&["list", "docs/rollout.md", "--awaiting", "ai"]);
    assert!(text.contains("### t1") && !text.contains("### t2"));
}

#[test]
fn list_prints_the_agent_rules_and_commands_first() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "give phases"]);
    let text = env.ok(&["list", "docs/rollout.md"]);
    let rules = "\
- Reply to every thread awaiting ai with `coauthor reply`. Editing the document
  is optional: answer with --no-edit when the comment is a question or you
  disagree.
- Edit the document with your normal file tools. Never edit threads files.
- If your edit moves or rewrites a thread's anchored text, run `coauthor move`.
- When you are finished, run `coauthor done DOC`.";
    let rules_at = text.find(rules).expect("rules missing");
    let commands_at = text.find("coauthor reply docs/rollout.md ID --edited 6,10-12 TEXT").expect("commands missing");
    for command in [
        "coauthor reply docs/rollout.md ID --no-edit TEXT",
        "coauthor move docs/rollout.md ID A-B",
        "coauthor done docs/rollout.md",
    ] {
        assert!(text.contains(command), "{command} missing:\n{text}");
    }
    let thread_at =
        text.find("### t1 · lines 3-3 · awaiting ai\n> The rollout takes two weeks.\n\n**me:** give phases").unwrap();
    assert!(rules_at < commands_at && commands_at < thread_at);

    // Paths that need quoting are quoted.
    env.write_doc("my notes.md", "x\n");
    assert!(env.ok(&["list", "my notes.md"]).contains("coauthor done 'my notes.md'"));
}

#[test]
fn move_re_anchors_and_keeps_the_original_text_as_was() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "a"]);
    env.write_doc("docs/rollout.md", "# Rollout\n\nPhase 1 takes a week.\nPhase 2 takes a week.\n");
    let state = env.json(&["move", "docs/rollout.md", "t1", "3-4"]);
    let t1 = thread(&state, "t1");
    assert_eq!(t1["lines"], serde_json::json!([3, 4]));
    assert_eq!(t1["anchor"], serde_json::json!(["Phase 1 takes a week.", "Phase 2 takes a week."]));
    assert_eq!(t1["was"], serde_json::json!(["The rollout takes two weeks."]));
    assert_eq!(t1["state"], "anchored");
    // A second move keeps the original text.
    let state = env.json(&["move", "docs/rollout.md", "t1", "4-4"]);
    assert_eq!(thread(&state, "t1")["was"], serde_json::json!(["The rollout takes two weeks."]));
    assert!(
        threads_file(&env).contains("## t1 · lines 4-4\n> Phase 2 takes a week.\nwas: The rollout takes two weeks.\n")
    );
    assert!(env.fails(&["move", "docs/rollout.md", "t1", "4-9"]).contains("outside the document"));
    assert!(env.fails(&["move", "docs/rollout.md", "t7", "1-1"]).contains("no thread t7"));
}

#[test]
fn moving_to_the_same_text_accepts_a_drift_without_was() {
    let env = Env::new();
    env.write_doc("d.md", "a\nsame\nb\n");
    env.ok(&["comment", "d.md", "--lines", "2-2", "x"]);
    env.write_doc("d.md", "same\nc\nc\nc\nsame\n");
    let state = env.json(&["done", "d.md"]);
    assert_eq!(thread(&state, "t1")["state"], "drifted");
    assert_eq!(state["result"]["drifted"], serde_json::json!(["t1"]));
    let state = env.json(&["move", "d.md", "t1", "1-1"]);
    assert_eq!(thread(&state, "t1")["state"], "anchored");
    assert_eq!(thread(&state, "t1")["was"], Value::Null);
}

#[test]
fn done_saves_re_found_anchors_and_ends_the_round() {
    let env = Env::new();
    env.write_doc("d.md", "intro\nkeep\nrepeat\nmoves\ngoes away\nend\n");
    for (lines, text) in [("2-2", "anchored"), ("3-3", "drifts"), ("4-4", "moves"), ("5-5", "orphans")] {
        env.ok(&["comment", "d.md", "--lines", lines, text]);
    }
    assert_eq!(env.json(&["round", "d.md", "open"])["round"], "open");
    env.write_doc("d.md", "new\nrepeat\nintro\nkeep\nrepeat\nother\nmoves\nend\n");
    let state = env.json(&["done", "d.md"]);
    assert_eq!(state["round"], "done");
    assert_eq!(state["result"]["moved"], serde_json::json!(["t1", "t2", "t3"]));
    assert_eq!(state["result"]["drifted"], serde_json::json!(["t2"]));
    assert_eq!(state["result"]["orphaned"], serde_json::json!(["t4"]));
    let path = env.json(&["path", "d.md"])["path"].as_str().unwrap().to_string();
    let file = fs::read_to_string(path).unwrap();
    assert!(file.contains("round: done -->"));
    assert!(file.contains("## t1 · lines 4-4\n"));
    assert!(file.contains("## t2 · lines 2-2 · drifted\n"));
    assert!(file.contains("## t3 · lines 7-7\n"));
    assert!(file.contains("## t4 · lines 5-5\n> goes away\n"), "orphans keep their last-known line");
    // Saved: the next list finds them at the stored lines.
    let state = env.json(&["list", "d.md"]);
    assert_eq!(thread(&state, "t3")["moved"], false);
    assert_eq!(thread(&state, "t2")["state"], "drifted");
    assert!(env.ok(&["done", "d.md"]).starts_with("Round done."));
}

#[test]
fn sync_saves_editor_positions_and_text() {
    let env = setup();
    env.ok(&["comment", "docs/rollout.md", "--lines", "3-3", "a"]);
    env.ok(&["comment", "docs/rollout.md", "--lines", "4-4", "b"]);
    env.write_doc("docs/rollout.md", "# Rollout\n\nIntro.\nThe rollout takes three weeks.\nWe start Monday.\n");
    let state = env.json(&[
        "sync",
        "docs/rollout.md",
        "--anchors",
        r#"[{"id":"t1","lines":[4,4]},{"id":"t2","lines":[5,5]},{"id":"t9","lines":[1,1]},{"id":"t2","lines":[5,5]}]"#,
    ]);
    assert_eq!(state["result"]["skipped"], serde_json::json!(["t9"]));
    let t1 = thread(&state, "t1");
    assert_eq!(t1["anchor"], serde_json::json!(["The rollout takes three weeks."]));
    assert_eq!(t1["was"], Value::Null, "the user's own edit is not a re-anchor");
    assert_eq!(t1["state"], "anchored");
    assert_eq!(thread(&state, "t2")["lines"], serde_json::json!([5, 5]));

    // From stdin, for long lists.
    let mut child = env
        .command()
        .args(["--json", "sync", "docs/rollout.md", "--anchors", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    use std::io::Write as _;
    child.stdin.take().unwrap().write_all(br#"[{"id":"t1","lines":[3,4]}]"#).unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let state: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(thread(&state, "t1")["anchor"], serde_json::json!(["Intro.", "The rollout takes three weeks."]));

    assert!(env.fails(&["sync", "docs/rollout.md", "--anchors", "{}"]).contains("array"));
    assert!(
        env.fails(&["sync", "docs/rollout.md", "--anchors", r#"[{"id":"t1","lines":[2,1]}]"#])
            .contains("invalid lines")
    );
}

#[test]
fn concurrent_processes_never_lose_a_comment() {
    let env = setup();
    let processes = 6;
    let per_process = 8;
    let children: Vec<_> = (0..processes)
        .map(|process| {
            let script: Vec<String> = (0..per_process).map(|n| format!("p{process} c{n}")).collect();
            let env = &env;
            let mut handles = Vec::new();
            for text in script {
                handles.push(
                    env.command()
                        .args(["comment", "docs/rollout.md", "--lines", "3-3", &text])
                        .stdout(Stdio::null())
                        .spawn()
                        .unwrap(),
                );
            }
            handles
        })
        .collect();
    for mut child in children.into_iter().flatten() {
        assert!(child.wait().unwrap().success());
    }
    let state = env.json(&["list", "docs/rollout.md"]);
    let mut ids: Vec<u64> =
        state["threads"].as_array().unwrap().iter().map(|t| t["id"].as_str().unwrap()[1..].parse().unwrap()).collect();
    ids.sort();
    assert_eq!(ids, (1..=(processes * per_process) as u64).collect::<Vec<_>>());
}

#[test]
fn help_documents_every_command() {
    let env = Env::new();
    let help = env.ok(&["--help"]);
    for command in ["list", "reply", "move", "done", "comment", "resolve", "sync", "round", "path", "mv", "rm", "prune"]
    {
        assert!(help.contains(&format!("  {command} ")), "{command} missing from --help:\n{help}");
        let sub = env.ok(&[command, "--help"]);
        assert!(sub.contains("Usage: coauthor"), "{command} --help");
    }
    assert!(env.ok(&["reply", "--help"]).contains("--edited <RANGES>"));
}
