//! The resolution ladder: where a thread's anchor text is in the document now.
//!
//! 1. the text at the stored lines matches the anchor text → anchored;
//! 2. the exact anchor text is found elsewhere → anchored there, or, with
//!    several matches, the nearest one, marked drifted;
//! 3. (fuzzy matching: not implemented, off by design);
//! 4. nothing → orphaned, keeping the last-known lines.

use crate::format::Thread;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Anchored,
    Drifted,
    Orphaned,
}

impl State {
    pub fn as_str(self) -> &'static str {
        match self {
            State::Anchored => "anchored",
            State::Drifted => "drifted",
            State::Orphaned => "orphaned",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Resolved {
    /// Where the anchor is now; the last-known lines when orphaned.
    pub lines: (u32, u32),
    pub state: State,
}

/// Splits document text into lines; a final newline does not start a line.
pub fn document_lines(text: &str) -> Vec<String> {
    let text = text.strip_suffix('\n').unwrap_or(text);
    if text.is_empty() {
        return Vec::new();
    }
    crate::format::split_lines(text)
}

fn matches_at(doc: &[String], anchor: &[String], start: usize) -> bool {
    doc.get(start..start + anchor.len()).is_some_and(|window| window == anchor)
}

pub fn resolve(doc: &[String], thread: &Thread) -> Resolved {
    let anchor = &thread.anchor;
    let stored = thread.lines;
    // A previously drifted anchor stays drifted until accepted.
    let found = |lines| Resolved { lines, state: if thread.drifted { State::Drifted } else { State::Anchored } };
    let len = anchor.len();
    if len == 0 || len > doc.len() {
        return Resolved { lines: stored, state: State::Orphaned };
    }
    let stored_start = stored.0 as usize - 1;
    if stored.1 - stored.0 + 1 == len as u32 && matches_at(doc, anchor, stored_start) {
        return found(stored);
    }
    let starts: Vec<usize> = (0..=doc.len() - len).filter(|&start| matches_at(doc, anchor, start)).collect();
    let lines_at = |start: usize| (start as u32 + 1, (start + len) as u32);
    match starts.as_slice() {
        [] => Resolved { lines: stored, state: State::Orphaned },
        [start] => found(lines_at(*start)),
        _ => {
            // Nearest to the stored start; the earlier one on a tie.
            let nearest = *starts.iter().min_by_key(|&&start| start.abs_diff(stored_start)).expect("not empty");
            Resolved { lines: lines_at(nearest), state: State::Drifted }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc(text: &str) -> Vec<String> {
        document_lines(text)
    }

    fn thread(lines: (u32, u32), anchor: &[&str]) -> Thread {
        Thread {
            id: 1,
            lines,
            drifted: false,
            resolved: false,
            anchor: anchor.iter().map(|line| line.to_string()).collect(),
            was: None,
            messages: Vec::new(),
        }
    }

    #[test]
    fn document_lines_ignore_the_final_newline() {
        assert_eq!(doc("a\nb\n"), vec!["a", "b"]);
        assert_eq!(doc("a\r\nb"), vec!["a", "b"]);
        assert_eq!(doc("a\n\n"), vec!["a", ""]);
        assert!(doc("").is_empty());
    }

    #[test]
    fn anchored_at_the_stored_lines() {
        let resolved = resolve(&doc("one\ntwo\nthree\n"), &thread((2, 3), &["two", "three"]));
        assert_eq!(resolved, Resolved { lines: (2, 3), state: State::Anchored });
    }

    #[test]
    fn moved_when_the_text_is_found_once_elsewhere() {
        let resolved = resolve(&doc("new\nlines\none\ntwo\n"), &thread((1, 2), &["one", "two"]));
        assert_eq!(resolved, Resolved { lines: (3, 4), state: State::Anchored });
    }

    #[test]
    fn drifted_to_the_nearest_of_several_matches() {
        let text = "x\nsame\nx\nx\nx\nx\nsame\nx\n";
        let resolved = resolve(&doc(text), &thread((6, 6), &["same"]));
        assert_eq!(resolved, Resolved { lines: (7, 7), state: State::Drifted });
        let resolved = resolve(&doc(text), &thread((3, 3), &["same"]));
        assert_eq!(resolved, Resolved { lines: (2, 2), state: State::Drifted });
        // A tie goes to the earlier match.
        let resolved = resolve(&doc("same\nx\nsame\n"), &thread((2, 2), &["same"]));
        assert_eq!(resolved, Resolved { lines: (1, 1), state: State::Drifted });
    }

    #[test]
    fn orphaned_keeps_the_last_known_lines() {
        let resolved = resolve(&doc("rewritten\ncompletely\n"), &thread((2, 2), &["gone"]));
        assert_eq!(resolved, Resolved { lines: (2, 2), state: State::Orphaned });
        // Past the end of a shortened document.
        let resolved = resolve(&doc("a\n"), &thread((5, 6), &["x", "y"]));
        assert_eq!(resolved.state, State::Orphaned);
    }

    #[test]
    fn a_stored_drift_stays_until_accepted() {
        let mut drifted = thread((1, 1), &["a"]);
        drifted.drifted = true;
        assert_eq!(resolve(&doc("a\nb\n"), &drifted).state, State::Drifted);
        assert_eq!(resolve(&doc("b\nc\n"), &drifted).state, State::Orphaned);
    }

    #[test]
    fn matching_is_exact() {
        assert_eq!(resolve(&doc("two \n"), &thread((1, 1), &["two"])).state, State::Orphaned);
    }
}
