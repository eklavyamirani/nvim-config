//! Comment threads on a document, shared by an editor and a coding agent.
//! The `coauthor` binary is the only writer of threads files; see README.md.

pub mod anchor;
pub mod cli;
pub mod format;
pub mod sha256;
pub mod store;
