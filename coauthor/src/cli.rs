//! Command-line interface. Every command takes the document path; `--json`
//! gives machine output (Neovim always uses it), the default is readable text.

use crate::anchor::{self, State};
use crate::format::{self, Author, Message, Round, Section, Thread, ThreadsFile};
use crate::store::{self, Result, Store};
use clap::{Parser, Subcommand, ValueEnum};
use serde_json::{Value, json};
use std::fs;
use std::io::Read as _;
use std::path::{Path, PathBuf};

/// Printed by `coauthor list`, verbatim from the design.
pub const AGENT_RULES: &str = "\
- Reply to every thread awaiting ai with `coauthor reply`. Editing the document
  is optional: answer with --no-edit when the comment is a question or you
  disagree.
- Edit the document with your normal file tools. Never edit threads files.
- If your edit moves or rewrites a thread's anchored text, run `coauthor move`.
- When you are finished, run `coauthor done DOC`.";

const AFTER_HELP: &str = "\
Agents: start with `coauthor list DOC`; it prints the rules and the threads.
Line ranges are 1-based and inclusive (A-B). Thread ids look like t3.";

#[derive(Parser)]
#[command(
    name = "coauthor",
    version,
    about = "Comment threads on a document, shared by an editor and a coding agent.",
    long_about = "Comment threads on a document, shared by an editor and a coding agent.\n\n\
        Threads live in one file per document in the state directory, never in the document. \
        This command is the only writer of those files.",
    after_help = AFTER_HELP
)]
struct Cli {
    /// Print machine-readable JSON instead of text.
    #[arg(long, global = true)]
    json: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Clone, Copy, ValueEnum)]
enum Who {
    Ai,
    Me,
}

#[derive(Clone, Copy, ValueEnum)]
enum RoundState {
    Open,
}

#[derive(Subcommand)]
enum Command {
    /// Agent entry point: print the rules, the commands and DOC's threads.
    /// Read-only: re-found anchors are reported, never saved.
    #[command(display_order = 1)]
    List {
        doc: PathBuf,
        /// Only threads awaiting this side.
        #[arg(long, value_enum)]
        awaiting: Option<Who>,
    },
    /// Agent reply to thread ID; give --edited when you changed the document.
    #[command(display_order = 2)]
    Reply {
        doc: PathBuf,
        id: String,
        /// Document lines your edit produced, e.g. 6,10-12.
        #[arg(long, value_name = "RANGES", required_unless_present = "no_edit", conflicts_with = "no_edit")]
        edited: Option<String>,
        /// The reply did not change the document.
        #[arg(long)]
        no_edit: bool,
        /// Reply text (words are joined with spaces).
        #[arg(required = true, num_args = 1.., allow_hyphen_values = true)]
        text: Vec<String>,
    },
    /// Re-anchor thread ID to lines A-B of DOC as it is now; saved immediately.
    #[command(display_order = 3)]
    Move { doc: PathBuf, id: String, range: String },
    /// End the round: re-find every anchor in the final document and save it.
    #[command(display_order = 4)]
    Done { doc: PathBuf },
    /// New thread on lines A-B (--lines), or a reply to one (--thread).
    #[command(display_order = 5)]
    Comment {
        doc: PathBuf,
        /// Lines the new thread is anchored to.
        #[arg(long, value_name = "A-B", required_unless_present = "thread", conflicts_with = "thread")]
        lines: Option<String>,
        /// The commented text; defaults to those lines of DOC on disk.
        #[arg(long, value_name = "TEXT", requires = "lines", allow_hyphen_values = true)]
        anchor_text: Option<String>,
        /// Reply to this thread instead.
        #[arg(long, value_name = "ID")]
        thread: Option<String>,
        /// Message text (words are joined with spaces).
        #[arg(required = true, num_args = 1.., allow_hyphen_values = true)]
        text: Vec<String>,
    },
    /// Mark thread ID resolved.
    #[command(display_order = 6)]
    Resolve { doc: PathBuf, id: String },
    /// Save anchor positions from the editor, as JSON [{"id": "t1", "lines": [A, B]}, ...]
    /// ("-" reads stdin). Anchor text is read from DOC, which must be saved.
    #[command(display_order = 7)]
    Sync {
        doc: PathBuf,
        #[arg(long, value_name = "JSON")]
        anchors: String,
    },
    /// Start a round: the document now belongs to the agent until `done`.
    #[command(display_order = 8)]
    Round {
        doc: PathBuf,
        #[arg(value_enum)]
        state: RoundState,
    },
    /// Print the threads file of DOC.
    #[command(display_order = 20)]
    Path { doc: PathBuf },
    /// Re-key OLD's threads to NEW after moving or renaming the document.
    #[command(display_order = 21)]
    Mv { old: PathBuf, new: PathBuf },
    /// Delete DOC's threads file.
    #[command(display_order = 22)]
    Rm { doc: PathBuf },
    /// Delete threads files whose document no longer exists.
    #[command(display_order = 23)]
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
        Command::List { doc, awaiting } => list(&store, &doc, awaiting, json),
        Command::Reply { doc, id, edited, no_edit: _, text } => {
            reply(&store, &doc, &id, edited.as_deref(), &text, json)
        }
        Command::Move { doc, id, range } => move_thread(&store, &doc, &id, &range, json),
        Command::Done { doc } => done(&store, &doc, json),
        Command::Comment { doc, lines, anchor_text, thread, text } => match (lines, thread) {
            (Some(lines), _) => comment_new(&store, &doc, &lines, anchor_text.as_deref(), &text, json),
            (None, Some(thread)) => comment_reply(&store, &doc, &thread, &text, json),
            (None, None) => Err("give --lines A-B or --thread ID".into()),
        },
        Command::Resolve { doc, id } => resolve(&store, &doc, &id, json),
        Command::Sync { doc, anchors } => sync(&store, &doc, &anchors, json),
        Command::Round { doc, state: RoundState::Open } => round_open(&store, &doc, json),
        Command::Path { doc } => path(&store, &doc, json),
        Command::Mv { old, new } => mv(&store, &old, &new, json),
        Command::Rm { doc } => rm(&store, &doc, json),
        Command::Prune { dry_run } => prune(&store, dry_run, json),
    }
}

// ---------------------------------------------------------------- helpers

fn parse_id(id: &str) -> Result<u32> {
    let digits = id.strip_prefix('t').unwrap_or(id);
    digits
        .parse::<u32>()
        .ok()
        .filter(|id| *id > 0 && digits.bytes().all(|b| b.is_ascii_digit()))
        .ok_or_else(|| format!("invalid thread id {id:?}; ids look like t3"))
}

fn parse_lines(range: &str) -> Result<(u32, u32)> {
    format::parse_range(range.trim())
        .ok_or_else(|| format!("invalid line range {range:?}; expected A-B with 1 <= A <= B"))
}

/// `6,10-12` or `6, 10-12`.
pub fn parse_ranges(text: &str) -> Option<Vec<(u32, u32)>> {
    text.split(',')
        .map(|part| {
            let part = part.trim();
            if part.contains('-') {
                format::parse_range(part)
            } else {
                part.parse::<u32>()
                    .ok()
                    .filter(|line| *line > 0 && part.bytes().all(|b| b.is_ascii_digit()))
                    .map(|line| (line, line))
            }
        })
        .collect()
}

fn format_ranges(ranges: &[(u32, u32)]) -> String {
    let parts: Vec<String> =
        ranges.iter().map(|&(a, b)| if a == b { a.to_string() } else { format!("{a}-{b}") }).collect();
    parts.join(", ")
}

/// Splits a leading `{edited …}` / `{no edit}` tag off an AI reply.
pub fn parse_tag(text: &str) -> (Option<Vec<(u32, u32)>>, bool, &str) {
    if let Some(body) = text.strip_prefix("{no edit}") {
        return (None, true, body.strip_prefix(' ').unwrap_or(body));
    }
    if let Some(rest) = text.strip_prefix("{edited ")
        && let Some((ranges, body)) = rest.split_once('}')
        && let Some(ranges) = parse_ranges(ranges)
    {
        return (Some(ranges), false, body.strip_prefix(' ').unwrap_or(body));
    }
    (None, false, text)
}

fn message_text(words: &[String]) -> Result<String> {
    let text = format::normalize_message(&words.join(" "));
    if text.trim().is_empty() { Err("the message is empty".into()) } else { Ok(text) }
}

/// The document's lines, or `None` when it cannot be read.
fn read_document(canonical: &str) -> Option<Vec<String>> {
    fs::read(canonical).ok().map(|bytes| anchor::document_lines(&String::from_utf8_lossy(&bytes)))
}

fn require_document(canonical: &str) -> Result<Vec<String>> {
    read_document(canonical).ok_or_else(|| format!("cannot read {canonical}"))
}

fn slice(doc: &[String], (a, b): (u32, u32)) -> Result<Vec<String>> {
    doc.get(a as usize - 1..b as usize)
        .map(<[String]>::to_vec)
        .ok_or_else(|| format!("lines {a}-{b} are outside the document ({} lines)", doc.len()))
}

fn find_thread(file: &mut ThreadsFile, id: u32) -> Result<&mut Thread> {
    file.thread_mut(id).ok_or_else(|| format!("no thread t{id}"))
}

/// A path as a shell word, for the commands `list` prints.
fn shell_word(path: &str) -> String {
    if !path.is_empty() && path.chars().all(|c| c.is_ascii_alphanumeric() || "_-./:\\@+,=".contains(c)) {
        path.to_string()
    } else {
        format!("'{}'", path.replace('\'', r"'\''"))
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Status {
    AwaitingAi,
    AwaitingMe,
    Resolved,
}

impl Status {
    fn of(thread: &Thread) -> Status {
        if thread.resolved {
            return Status::Resolved;
        }
        match thread.messages.last().map(|message| message.author) {
            Some(Author::Me) => Status::AwaitingAi,
            _ => Status::AwaitingMe,
        }
    }

    fn key(self) -> &'static str {
        match self {
            Status::AwaitingAi => "awaiting_ai",
            Status::AwaitingMe => "awaiting_me",
            Status::Resolved => "resolved",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Status::AwaitingAi => "awaiting ai",
            Status::AwaitingMe => "awaiting me",
            Status::Resolved => "resolved",
        }
    }
}

// ---------------------------------------------------------------- output

/// Everything Neovim needs about a document's threads, resolved against the
/// document on disk. Every command that changes threads prints this too.
struct Snapshot<'a> {
    canonical: &'a str,
    path: PathBuf,
    file: Option<&'a ThreadsFile>,
    revision: Option<String>,
    doc: Option<Vec<String>>,
}

impl Snapshot<'_> {
    fn resolve(&self, thread: &Thread) -> anchor::Resolved {
        anchor::resolve(self.doc.as_deref().unwrap_or(&[]), thread)
    }

    fn threads(&self) -> Vec<&Thread> {
        self.file.map(|file| file.threads().collect()).unwrap_or_default()
    }

    fn to_json(&self, result: Value) -> Value {
        let mut counts = json!({ "awaiting_ai": 0, "awaiting_me": 0, "resolved": 0, "orphaned": 0, "drifted": 0 });
        let threads: Vec<Value> = self
            .threads()
            .into_iter()
            .map(|thread| {
                let resolved = self.resolve(thread);
                let status = Status::of(thread);
                counts[status.key()] = (counts[status.key()].as_u64().unwrap_or(0) + 1).into();
                if status != Status::Resolved && resolved.state != State::Anchored {
                    let key = resolved.state.as_str();
                    counts[key] = (counts[key].as_u64().unwrap_or(0) + 1).into();
                }
                thread_json(thread, resolved, status)
            })
            .collect();
        let unparsed: Vec<&str> = self.file.map(|file| file.raw_sections().collect()).unwrap_or_default();
        json!({
            "doc": self.canonical,
            "path": display(&self.path),
            "exists": self.file.is_some(),
            "doc_exists": self.doc.is_some(),
            "round": self.file.map_or(Round::None, |file| file.round).as_str(),
            "revision": self.revision,
            "threads": threads,
            "counts": counts,
            "unparsed": unparsed,
            "result": result,
        })
    }
}

fn thread_json(thread: &Thread, resolved: anchor::Resolved, status: Status) -> Value {
    let label = thread.label();
    let messages: Vec<Value> = thread
        .messages
        .iter()
        .enumerate()
        .map(|(index, message)| {
            let (edited, no_edit, body) = if message.author == Author::Ai {
                parse_tag(&message.text)
            } else {
                (None, false, message.text.as_str())
            };
            json!({
                "id": format!("{label}.{}", index + 1),
                "author": message.author.as_str(),
                "text": message.text,
                "body": body,
                "edited": edited.map(|ranges| ranges.iter().map(|&(a, b)| json!([a, b])).collect::<Vec<_>>()),
                "no_edit": no_edit,
            })
        })
        .collect();
    json!({
        "id": label,
        "lines": [resolved.lines.0, resolved.lines.1],
        "stored": [thread.lines.0, thread.lines.1],
        "state": resolved.state.as_str(),
        "moved": resolved.state != State::Orphaned && resolved.lines != thread.lines,
        "status": status.key(),
        "resolved": thread.resolved,
        "anchor": thread.anchor,
        "was": thread.was,
        "messages": messages,
    })
}

fn snapshot_after<'a>(
    store: &Store,
    canonical: &'a str,
    file: &'a ThreadsFile,
    revision: String,
    json: bool,
    result: Value,
    text: String,
) -> Result<String> {
    if !json {
        return Ok(format!("{text}\n"));
    }
    let snapshot = Snapshot {
        canonical,
        path: store.path_for(canonical),
        file: Some(file),
        revision: Some(revision),
        doc: read_document(canonical),
    };
    Ok(format!("{}\n", snapshot.to_json(result)))
}

fn render_thread_text(out: &mut String, thread: &Thread, resolved: anchor::Resolved, status: Status) {
    let (a, b) = resolved.lines;
    let place = match resolved.state {
        State::Orphaned => format!("orphaned, was line {}", thread.lines.0),
        State::Drifted => format!("lines {a}-{b}, drifted"),
        State::Anchored => format!("lines {a}-{b}"),
    };
    out.push_str(&format!("### {} · {place} · {}\n", thread.label(), status.label()));
    for line in &thread.anchor {
        out.push_str(&format!("> {line}\n").replace("> \n", ">\n"));
    }
    for line in thread.was.iter().flatten() {
        out.push_str(&format!("was: {line}\n"));
    }
    for message in &thread.messages {
        out.push_str(&format!("\n**{}:** {}\n", message.author.as_str(), message.text));
    }
    out.push('\n');
}

// ---------------------------------------------------------------- commands

fn list(store: &Store, doc: &Path, awaiting: Option<Who>, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let path = store.path_for(&canonical);
    let loaded = store.load(&canonical)?;
    let (file, revision) = match &loaded {
        Some((file, revision)) => (Some(file), Some(revision.clone())),
        None => (None, None),
    };
    let snapshot = Snapshot { canonical: &canonical, path, file, revision, doc: read_document(&canonical) };
    let wanted = |status: Status| match awaiting {
        None => status != Status::Resolved,
        Some(Who::Ai) => status == Status::AwaitingAi,
        Some(Who::Me) => status == Status::AwaitingMe,
    };
    if json {
        let mut value = snapshot.to_json(Value::Null);
        if awaiting.is_some()
            && let Some(threads) = value["threads"].as_array_mut()
        {
            let keep = |key: &str| match awaiting {
                Some(Who::Ai) => key == "awaiting_ai",
                Some(Who::Me) => key == "awaiting_me",
                None => true,
            };
            threads.retain(|thread| keep(thread["status"].as_str().unwrap_or("")));
        }
        return Ok(format!("{value}\n"));
    }

    let shown = doc.to_string_lossy();
    let word = shell_word(&shown);
    let round = snapshot.file.map_or(Round::None, |file| file.round).as_str();
    let mut out = format!("# Coauthor threads on {shown} (round: {round})\n\n");
    out.push_str("## Rules\n\n");
    out.push_str(AGENT_RULES);
    out.push_str("\n\n## Commands\n\n");
    for (command, what) in [
        (format!("coauthor reply {word} ID --edited 6,10-12 TEXT"), "reply after changing the document"),
        (format!("coauthor reply {word} ID --no-edit TEXT"), "reply without changing the document"),
        (format!("coauthor move {word} ID A-B"), "re-anchor a thread to lines A-B"),
        (format!("coauthor done {word}"), "end the round"),
    ] {
        out.push_str(&format!("    {command}\n        {what}\n"));
    }
    out.push_str("\nIDs look like t3; line ranges are 1-based and inclusive, in the document as it is now.\n");
    // Found in a live run: a headless agent may be allowed only commands that
    // start with `coauthor`, and a chain or a leading line continuation is denied.
    out.push_str(
        "Run each coauthor command as its own shell command: no `&&` chains, `;` or `\\` line continuations.\n\n",
    );
    if snapshot.doc.is_none() {
        out.push_str(&format!("Warning: cannot read {canonical}; every thread shows as orphaned.\n\n"));
    }
    let threads = snapshot.threads();
    let count = |status| threads.iter().filter(|thread| Status::of(thread) == status).count();
    out.push_str(&format!(
        "## Threads (awaiting ai: {} · awaiting me: {})\n\n",
        count(Status::AwaitingAi),
        count(Status::AwaitingMe)
    ));
    let mut any = false;
    for thread in threads.iter().filter(|thread| wanted(Status::of(thread))) {
        any = true;
        render_thread_text(&mut out, thread, snapshot.resolve(thread), Status::of(thread));
    }
    if !any {
        out.push_str("No threads to show.\n");
    }
    let unparsed = snapshot.file.map_or(0, |file| file.raw_sections().count());
    if unparsed > 0 {
        out.push_str(&format!("\n{unparsed} section(s) of the threads file could not be read and are ignored.\n"));
    }
    Ok(out.trim_end().to_string() + "\n")
}

fn reply(store: &Store, doc: &Path, id: &str, edited: Option<&str>, words: &[String], json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let id = parse_id(id)?;
    let tag = match edited {
        Some(ranges) => {
            let ranges = parse_ranges(ranges)
                .ok_or_else(|| format!("invalid --edited {ranges:?}; expected lines like 6,10-12"))?;
            format!("{{edited {}}}", format_ranges(&ranges))
        }
        None => "{no edit}".to_string(),
    };
    let text = format!("{tag} {}", message_text(words)?);
    let (message_id, file, revision) = store.update(&canonical, |file| {
        let thread = find_thread(file, id)?;
        thread.messages.push(Message { author: Author::Ai, text });
        thread.resolved = false;
        Ok(format!("t{id}.{}", thread.messages.len()))
    })?;
    let message = format!("Replied to t{id} ({message_id})");
    snapshot_after(store, &canonical, &file, revision, json, json!({ "message": message_id }), message)
}

fn move_thread(store: &Store, doc: &Path, id: &str, range: &str, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let id = parse_id(id)?;
    let lines = parse_lines(range)?;
    let (_, file, revision) = store.update(&canonical, |file| {
        let anchor = slice(&require_document(&canonical)?, lines)?;
        let thread = find_thread(file, id)?;
        if anchor != thread.anchor && thread.was.is_none() {
            thread.was = Some(std::mem::take(&mut thread.anchor));
        }
        thread.anchor = anchor;
        thread.lines = lines;
        thread.drifted = false;
        Ok(())
    })?;
    let text = format!("t{id} anchored to lines {}-{}", lines.0, lines.1);
    snapshot_after(store, &canonical, &file, revision, json, json!({ "thread": format!("t{id}") }), text)
}

fn done(store: &Store, doc: &Path, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let (summary, file, revision) = store.update(&canonical, |file| {
        let lines = require_document(&canonical)?;
        let (mut moved, mut drifted, mut orphaned) = (Vec::new(), Vec::new(), Vec::new());
        for thread in file.threads_mut() {
            let resolved = anchor::resolve(&lines, thread);
            match resolved.state {
                State::Orphaned => orphaned.push(thread.label()),
                State::Drifted => drifted.push(thread.label()),
                State::Anchored => {}
            }
            if resolved.state != State::Orphaned && resolved.lines != thread.lines {
                moved.push(thread.label());
                thread.lines = resolved.lines;
            }
            thread.drifted = resolved.state == State::Drifted;
        }
        file.round = Round::Done;
        Ok(json!({ "moved": moved, "drifted": drifted, "orphaned": orphaned }))
    })?;
    let count = |key: &str| summary[key].as_array().map_or(0, Vec::len);
    let text = format!(
        "Round done. Anchors re-found: {} moved, {} drifted, {} orphaned.",
        count("moved"),
        count("drifted"),
        count("orphaned")
    );
    snapshot_after(store, &canonical, &file, revision, json, summary, text)
}

fn comment_new(
    store: &Store,
    doc: &Path,
    range: &str,
    anchor_text: Option<&str>,
    words: &[String],
    json: bool,
) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let lines = parse_lines(range)?;
    let text = message_text(words)?;
    let anchor = match anchor_text {
        Some(anchor_text) => {
            let anchor = format::split_lines(anchor_text);
            let expected = (lines.1 - lines.0 + 1) as usize;
            if anchor.len() != expected {
                return Err(format!(
                    "--anchor-text has {} line(s) but lines {}-{} are {expected}",
                    anchor.len(),
                    lines.0,
                    lines.1
                ));
            }
            anchor
        }
        None => slice(&require_document(&canonical)?, lines)?,
    };
    let (id, file, revision) = store.update(&canonical, |file| {
        let id = file.next_id();
        file.sections.push(Section::Thread(Thread {
            id,
            lines,
            drifted: false,
            resolved: false,
            anchor,
            was: None,
            messages: vec![Message { author: Author::Me, text }],
        }));
        Ok(id)
    })?;
    let message = format!("t{id} created on lines {}-{}", lines.0, lines.1);
    snapshot_after(store, &canonical, &file, revision, json, json!({ "thread": format!("t{id}") }), message)
}

fn comment_reply(store: &Store, doc: &Path, id: &str, words: &[String], json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let id = parse_id(id)?;
    let text = message_text(words)?;
    let (message_id, file, revision) = store.update(&canonical, |file| {
        let thread = find_thread(file, id)?;
        thread.messages.push(Message { author: Author::Me, text });
        thread.resolved = false;
        Ok(format!("t{id}.{}", thread.messages.len()))
    })?;
    let message = format!("Replied to t{id} ({message_id})");
    snapshot_after(store, &canonical, &file, revision, json, json!({ "message": message_id }), message)
}

fn resolve(store: &Store, doc: &Path, id: &str, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let id = parse_id(id)?;
    let (_, file, revision) = store.update(&canonical, |file| {
        let thread = find_thread(file, id)?;
        thread.resolved = true;
        thread.was = None;
        Ok(())
    })?;
    snapshot_after(
        store,
        &canonical,
        &file,
        revision,
        json,
        json!({ "thread": format!("t{id}") }),
        format!("t{id} resolved"),
    )
}

fn sync(store: &Store, doc: &Path, anchors: &str, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let input = if anchors == "-" {
        let mut text = String::new();
        std::io::stdin().read_to_string(&mut text).map_err(|err| format!("reading stdin: {err}"))?;
        text
    } else {
        anchors.to_string()
    };
    let entries: Value = serde_json::from_str(&input).map_err(|err| format!("--anchors is not valid JSON: {err}"))?;
    let entries = entries.as_array().ok_or("--anchors must be a JSON array")?;
    let mut wanted = Vec::new();
    for entry in entries {
        let id = entry["id"].as_str().ok_or("each anchor needs an \"id\" string")?;
        let pair = entry["lines"].as_array().filter(|pair| pair.len() == 2);
        let numbers = pair.and_then(|pair| Some((pair[0].as_u64()?, pair[1].as_u64()?)));
        let (a, b) = numbers.ok_or("each anchor needs \"lines\": [A, B]")?;
        let lines = (u32::try_from(a).unwrap_or(0), u32::try_from(b).unwrap_or(0));
        if lines.0 < 1 || lines.0 > lines.1 {
            return Err(format!("invalid lines [{a}, {b}] for {id}"));
        }
        wanted.push((parse_id(id)?, lines));
    }
    let (result, file, revision) = store.update(&canonical, |file| {
        let doc = require_document(&canonical)?;
        let (mut synced, mut skipped) = (Vec::new(), Vec::new());
        for (id, lines) in wanted {
            let (Some(thread), Ok(anchor)) = (file.thread_mut(id), slice(&doc, lines)) else {
                skipped.push(format!("t{id}"));
                continue;
            };
            thread.lines = lines;
            thread.anchor = anchor;
            synced.push(format!("t{id}"));
        }
        Ok(json!({ "synced": synced, "skipped": skipped }))
    })?;
    let count = |key: &str| result[key].as_array().map_or(0, Vec::len);
    let text = format!("Synced {} anchor(s), skipped {}", count("synced"), count("skipped"));
    snapshot_after(store, &canonical, &file, revision, json, result, text)
}

fn round_open(store: &Store, doc: &Path, json: bool) -> Result<String> {
    let canonical = store::canonical_doc(doc)?;
    let (_, file, revision) = store.update(&canonical, |file| {
        file.round = Round::Open;
        Ok(())
    })?;
    snapshot_after(store, &canonical, &file, revision, json, json!({ "round": "open" }), "Round open".into())
}

// ---------------------------------------------------------------- housekeeping

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
