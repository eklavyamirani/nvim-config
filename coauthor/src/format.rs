//! The threads file: a strict, dumb Markdown shape that only this crate writes.
//!
//! ```text
//! <!-- coauthor v1 · written by the coauthor CLI; do not edit by hand
//! doc: /home/me/src/project/docs/rollout.md
//! round: open -->
//!
//! ## t1 · lines 12-14
//! > The rollout takes two weeks.
//!
//! **me:** too vague, give phases
//!
//! **ai:** {edited 12-18} Split into 3 phases.
//! ```
//!
//! A section whose `##` header or body does not fit the shape is kept verbatim
//! as [`Section::Raw`], so a hand edit is never silently dropped.

use std::fmt::Write as _;

pub const MAGIC: &str = "<!-- coauthor v1";
const HEADER_NOTE: &str = " · written by the coauthor CLI; do not edit by hand";
const SEP: &str = " · ";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Round {
    /// No round has been opened yet.
    None,
    Open,
    Done,
}

impl Round {
    pub fn as_str(self) -> &'static str {
        match self {
            Round::None => "none",
            Round::Open => "open",
            Round::Done => "done",
        }
    }

    fn parse(value: &str) -> Option<Round> {
        match value {
            "none" => Some(Round::None),
            "open" => Some(Round::Open),
            "done" => Some(Round::Done),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Author {
    Me,
    Ai,
}

impl Author {
    pub fn as_str(self) -> &'static str {
        match self {
            Author::Me => "me",
            Author::Ai => "ai",
        }
    }

    fn marker(self) -> &'static str {
        match self {
            Author::Me => "**me:**",
            Author::Ai => "**ai:**",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Message {
    pub author: Author,
    /// Full text, including a leading `{edited …}` / `{no edit}` tag on AI replies.
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Thread {
    pub id: u32,
    /// 1-based, inclusive.
    pub lines: (u32, u32),
    /// Re-found by the ladder among several matches; unconfirmed until accepted.
    pub drifted: bool,
    pub resolved: bool,
    /// Anchor text, one entry per document line.
    pub anchor: Vec<String>,
    /// Anchor text before the first re-anchor, kept until the thread is resolved.
    pub was: Option<Vec<String>>,
    pub messages: Vec<Message>,
}

impl Thread {
    pub fn label(&self) -> String {
        format!("t{}", self.id)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Section {
    Thread(Thread),
    /// Text that does not parse as a thread, preserved byte for byte (minus
    /// trailing blank lines).
    Raw(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ThreadsFile {
    pub doc: String,
    pub round: Round,
    pub sections: Vec<Section>,
}

impl ThreadsFile {
    pub fn new(doc: &str) -> ThreadsFile {
        ThreadsFile { doc: doc.to_string(), round: Round::None, sections: Vec::new() }
    }

    pub fn threads(&self) -> impl Iterator<Item = &Thread> {
        self.sections.iter().filter_map(|section| match section {
            Section::Thread(thread) => Some(thread),
            Section::Raw(_) => None,
        })
    }

    pub fn threads_mut(&mut self) -> impl Iterator<Item = &mut Thread> {
        self.sections.iter_mut().filter_map(|section| match section {
            Section::Thread(thread) => Some(thread),
            Section::Raw(_) => None,
        })
    }

    pub fn raw_sections(&self) -> impl Iterator<Item = &str> {
        self.sections.iter().filter_map(|section| match section {
            Section::Raw(text) => Some(text.as_str()),
            Section::Thread(_) => None,
        })
    }

    pub fn thread_mut(&mut self, id: u32) -> Option<&mut Thread> {
        self.threads_mut().find(|thread| thread.id == id)
    }

    /// The next thread id. Ids in unparsed sections count too, so a hand-broken
    /// thread's id is never reused.
    pub fn next_id(&self) -> u32 {
        let parsed = self.threads().map(|thread| thread.id);
        let raw = self.raw_sections().filter_map(raw_section_id);
        parsed.chain(raw).max().unwrap_or(0) + 1
    }
}

fn raw_section_id(text: &str) -> Option<u32> {
    let digits: String = text.strip_prefix("## t")?.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok()
}

#[derive(Debug, PartialEq, Eq)]
pub struct ParseError(pub String);

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// Parses `## t12 · lines 3-5` (plus flags) into (id, lines, drifted, resolved).
fn parse_thread_header(line: &str) -> Option<(u32, (u32, u32), bool, bool)> {
    let mut parts = line.strip_prefix("## t")?.split(SEP);
    let id = parse_number(parts.next()?)?;
    let range = parts.next()?.strip_prefix("lines ")?;
    let lines = parse_range(range)?;
    let (mut drifted, mut resolved) = (false, false);
    for flag in parts {
        match flag {
            "drifted" if !drifted && !resolved => drifted = true,
            "resolved" if !resolved => resolved = true,
            _ => return None,
        }
    }
    Some((id, lines, drifted, resolved))
}

fn parse_number(text: &str) -> Option<u32> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

/// Parses `A-B` (1-based, A <= B).
pub fn parse_range(text: &str) -> Option<(u32, u32)> {
    let (a, b) = text.split_once('-')?;
    let (a, b) = (parse_number(a)?, parse_number(b)?);
    (a >= 1 && a <= b).then_some((a, b))
}

fn message_start(line: &str) -> Option<(Author, &str)> {
    for author in [Author::Me, Author::Ai] {
        if let Some(rest) = line.strip_prefix(author.marker()) {
            if rest.is_empty() {
                return Some((author, ""));
            }
            if let Some(text) = rest.strip_prefix(' ') {
                return Some((author, text));
            }
        }
    }
    None
}

/// A continuation line that would read as structure gets a `\` prefix.
fn needs_escape(line: &str) -> bool {
    line.starts_with('\\') || line.starts_with("## ") || message_start(line).is_some()
}

fn parse_thread(lines: &[&str]) -> Option<Thread> {
    let (id, range, drifted, resolved) = parse_thread_header(lines.first()?)?;
    let mut rest = lines[1..].iter().peekable();
    let mut anchor = Vec::new();
    while let Some(line) = rest.peek() {
        let Some(text) = line.strip_prefix('>') else { break };
        anchor.push(text.strip_prefix(' ').unwrap_or(text).to_string());
        rest.next();
    }
    if anchor.is_empty() {
        return None;
    }
    let mut was = Vec::new();
    while let Some(line) = rest.peek() {
        let Some(text) = line.strip_prefix("was:") else { break };
        was.push(text.strip_prefix(' ').unwrap_or(text).to_string());
        rest.next();
    }
    let mut messages: Vec<(Author, Vec<String>)> = Vec::new();
    for line in rest {
        if let Some((author, text)) = message_start(line) {
            messages.push((author, vec![text.to_string()]));
        } else if let Some((_, body)) = messages.last_mut() {
            body.push(line.strip_prefix('\\').unwrap_or(line).to_string());
        } else if !line.trim().is_empty() {
            return None;
        }
    }
    let messages = messages
        .into_iter()
        .map(|(author, mut body)| {
            while body.last().is_some_and(|line| line.trim().is_empty()) {
                body.pop();
            }
            Message { author, text: body.join("\n") }
        })
        .collect();
    let was = (!was.is_empty()).then_some(was);
    Some(Thread { id, lines: range, drifted, resolved, anchor, was, messages })
}

pub fn parse(text: &str) -> Result<ThreadsFile, ParseError> {
    let text = text.replace("\r\n", "\n");
    let lines: Vec<&str> = text.split('\n').collect();
    if !lines.first().is_some_and(|line| line.starts_with(MAGIC)) {
        return Err(ParseError("not a coauthor v1 threads file".into()));
    }
    let end = lines
        .iter()
        .position(|line| line.trim_end().ends_with("-->"))
        .ok_or_else(|| ParseError("unterminated threads file header".into()))?;
    let (mut doc, mut round) = (None, None);
    for line in &lines[1..=end] {
        let line = line.trim_end().strip_suffix("-->").unwrap_or(line).trim_end();
        if let Some(value) = line.strip_prefix("doc: ") {
            doc = Some(value.to_string());
        } else if let Some(value) = line.strip_prefix("round: ") {
            round = Some(Round::parse(value).ok_or_else(|| ParseError(format!("unknown round state: {value}")))?);
        }
    }
    let doc = doc.ok_or_else(|| ParseError("threads file header has no doc: line".into()))?;
    let round = round.unwrap_or(Round::None);

    let body = &lines[end + 1..];
    let mut chunks: Vec<Vec<&str>> = Vec::new();
    for line in body {
        if line.starts_with("## ") || chunks.is_empty() {
            chunks.push(Vec::new());
        }
        chunks.last_mut().expect("pushed above").push(line);
    }
    let mut sections = Vec::new();
    for chunk in chunks {
        let start = chunk.iter().position(|line| !line.trim().is_empty()).unwrap_or(chunk.len());
        let mut chunk = chunk[start..].to_vec();
        while chunk.last().is_some_and(|line| line.trim().is_empty()) {
            chunk.pop();
        }
        if chunk.is_empty() {
            continue;
        }
        match parse_thread(&chunk) {
            Some(thread) => sections.push(Section::Thread(thread)),
            None => sections.push(Section::Raw(chunk.join("\n"))),
        }
    }
    Ok(ThreadsFile { doc, round, sections })
}

pub fn render(file: &ThreadsFile) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "{MAGIC}{HEADER_NOTE}");
    let _ = writeln!(out, "doc: {}", file.doc);
    let _ = writeln!(out, "round: {} -->", file.round.as_str());
    for section in &file.sections {
        out.push('\n');
        match section {
            Section::Raw(text) => {
                out.push_str(text);
                out.push('\n');
            }
            Section::Thread(thread) => render_thread(&mut out, thread),
        }
    }
    out
}

fn render_thread(out: &mut String, thread: &Thread) {
    let _ = write!(out, "## t{}{SEP}lines {}-{}", thread.id, thread.lines.0, thread.lines.1);
    if thread.drifted {
        let _ = write!(out, "{SEP}drifted");
    }
    if thread.resolved {
        let _ = write!(out, "{SEP}resolved");
    }
    out.push('\n');
    for line in &thread.anchor {
        out.push('>');
        if !line.is_empty() {
            out.push(' ');
            out.push_str(line);
        }
        out.push('\n');
    }
    for line in thread.was.iter().flatten() {
        out.push_str("was:");
        if !line.is_empty() {
            out.push(' ');
            out.push_str(line);
        }
        out.push('\n');
    }
    for message in &thread.messages {
        out.push('\n');
        out.push_str(message.author.marker());
        let mut lines = message.text.split('\n');
        let first = lines.next().unwrap_or("");
        if !first.is_empty() {
            out.push(' ');
            out.push_str(first);
        }
        out.push('\n');
        for line in lines {
            if needs_escape(line) {
                out.push('\\');
            }
            out.push_str(line);
            out.push('\n');
        }
    }
}

/// Normalises message text to what survives a render/parse round trip:
/// LF line endings and no trailing blank lines.
pub fn normalize_message(text: &str) -> String {
    let text = text.replace("\r\n", "\n");
    let mut lines: Vec<&str> = text.split('\n').collect();
    while lines.last().is_some_and(|line| line.trim().is_empty()) {
        lines.pop();
    }
    lines.join("\n")
}

/// Splits document text into lines the way anchors store them.
pub fn split_lines(text: &str) -> Vec<String> {
    text.split('\n').map(|line| line.strip_suffix('\r').unwrap_or(line).to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn thread(id: u32) -> Thread {
        Thread {
            id,
            lines: (12, 14),
            drifted: false,
            resolved: false,
            anchor: vec!["The rollout takes two weeks.".into()],
            was: None,
            messages: vec![Message { author: Author::Me, text: "too vague, give phases".into() }],
        }
    }

    const EXAMPLE: &str = "<!-- coauthor v1 · written by the coauthor CLI; do not edit by hand
doc: /home/me/src/project/docs/rollout.md
round: open -->

## t1 · lines 12-14
> The rollout takes two weeks.

**me:** too vague, give phases

**ai:** {edited 12-18} Split into 3 phases.

**me:** why 3 and not 2?

**ai:** {no edit} Phase 2 has the migration freeze; merging it with 1 hides that dependency.
";

    #[test]
    fn design_example_parses_and_renders_identically() {
        let file = parse(EXAMPLE).unwrap();
        assert_eq!(file.doc, "/home/me/src/project/docs/rollout.md");
        assert_eq!(file.round, Round::Open);
        let threads: Vec<_> = file.threads().collect();
        assert_eq!(threads.len(), 1);
        assert_eq!(threads[0].lines, (12, 14));
        assert_eq!(threads[0].messages.len(), 4);
        assert_eq!(threads[0].messages[1].author, Author::Ai);
        assert_eq!(threads[0].messages[1].text, "{edited 12-18} Split into 3 phases.");
        assert_eq!(render(&file), EXAMPLE);
    }

    #[test]
    fn awkward_text_round_trips() {
        let mut file = ThreadsFile::new("C:\\Users\\me\\notes · draft.md");
        let mut tricky = thread(3);
        tricky.lines = (1, 5);
        tricky.drifted = true;
        tricky.resolved = true;
        tricky.anchor = vec!["".into(), " leading space".into(), "> quoted".into(), "## heading".into(), "".into()];
        tricky.was = Some(vec!["old".into(), "".into(), "was: nested".into()]);
        tricky.messages = vec![
            Message {
                author: Author::Me,
                text: "line one\n\n## not a header\n**ai:** not a reply\n\\backslash\n  indented".into(),
            },
            Message { author: Author::Ai, text: "".into() },
            Message { author: Author::Ai, text: "{no edit} ok".into() },
        ];
        file.sections.push(Section::Thread(tricky));
        file.sections.push(Section::Thread(thread(4)));
        file.round = Round::Done;
        let rendered = render(&file);
        assert_eq!(parse(&rendered).unwrap(), file, "rendered:\n{rendered}");
        assert_eq!(render(&parse(&rendered).unwrap()), rendered);
    }

    #[test]
    fn crlf_is_accepted() {
        let file = parse(&EXAMPLE.replace('\n', "\r\n")).unwrap();
        assert_eq!(render(&file), EXAMPLE);
    }

    #[test]
    fn unparseable_sections_are_kept_verbatim() {
        let broken = "## t7 lines twelve\n> anchor\n\n**me:** hand-edited header";
        let stray = "## t8 · lines 3-4\nno anchor here\n\n**me:** text";
        let text = format!("{}\n\n{broken}\n\n{stray}\n\n## t2 · lines 1-1\n> a\n\n**me:** hi\n", EXAMPLE.trim_end());
        let file = parse(&text).unwrap();
        assert_eq!(file.raw_sections().collect::<Vec<_>>(), vec![broken, stray]);
        assert_eq!(file.threads().count(), 2);
        assert_eq!(render(&file), text);
        // Ids in unparsed sections are never reused.
        assert_eq!(file.next_id(), 9);
    }

    #[test]
    fn stray_text_before_the_first_thread_is_kept() {
        let text = "<!-- coauthor v1\ndoc: /d.md\nround: none -->\n\nstray note\n";
        let file = parse(text).unwrap();
        assert_eq!(file.raw_sections().collect::<Vec<_>>(), vec!["stray note"]);
        assert!(render(&file).ends_with("\nstray note\n"));
    }

    #[test]
    fn header_errors() {
        assert!(parse("# not ours\n").is_err());
        assert!(parse("<!-- coauthor v1\ndoc: /d.md\n").is_err());
        assert!(parse("<!-- coauthor v1\nround: open -->\n").is_err());
        assert!(parse("<!-- coauthor v1\ndoc: /d.md\nround: maybe -->\n").is_err());
    }

    #[test]
    fn empty_file_and_ids() {
        let file = ThreadsFile::new("/d.md");
        assert_eq!(
            render(&file),
            "<!-- coauthor v1 · written by the coauthor CLI; do not edit by hand\ndoc: /d.md\nround: none -->\n"
        );
        assert_eq!(parse(&render(&file)).unwrap(), file);
        assert_eq!(file.next_id(), 1);
    }

    #[test]
    fn ranges() {
        assert_eq!(parse_range("3-5"), Some((3, 5)));
        assert_eq!(parse_range("4-4"), Some((4, 4)));
        assert_eq!(parse_range("5-3"), None);
        assert_eq!(parse_range("0-3"), None);
        assert_eq!(parse_range("+1-3"), None);
        assert_eq!(parse_range("3"), None);
    }

    #[test]
    fn message_normalisation() {
        assert_eq!(normalize_message("a\r\nb\n\n  \n"), "a\nb");
    }
}
