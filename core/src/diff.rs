use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DiffLineKind {
    Context,
    Added,
    Removed,
    Header,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiffLine {
    pub kind: DiffLineKind,
    pub text: String,
}

impl DiffLine {
    fn new(kind: DiffLineKind, text: String) -> Self {
        DiffLine { kind, text }
    }
}

struct Op<'a> {
    kind: DiffLineKind,
    text: &'a str,
    old_index: usize,
    new_index: usize,
}

pub const DEFAULT_CONTEXT: usize = 3;

pub fn lines(old: &str, new: &str, path: &str, context: usize) -> Vec<DiffLine> {
    let a: Vec<&str> = if old.is_empty() { Vec::new() } else { old.split('\n').collect() };
    let b: Vec<&str> = new.split('\n').collect();
    let ops = edits(&a, &b);
    if ops.iter().all(|op| op.kind == DiffLineKind::Context) {
        return Vec::new();
    }

    let old_label = if old.is_empty() { "/dev/null".to_string() } else { format!("a/{path}") };
    let mut result = vec![
        DiffLine::new(DiffLineKind::Header, format!("--- {old_label}")),
        DiffLine::new(DiffLineKind::Header, format!("+++ b/{path}")),
    ];
    let mut groups: Vec<(usize, usize)> = Vec::new();
    for (index, _) in ops.iter().enumerate().filter(|(_, op)| op.kind != DiffLineKind::Context) {
        match groups.last_mut() {
            Some(last) if index - last.1 <= context * 2 => last.1 = index,
            _ => groups.push((index, index)),
        }
    }
    for (first, last) in groups {
        let start = first.saturating_sub(context);
        let end = ops.len().min(last + context + 1);
        let hunk = &ops[start..end];
        let old_start = hunk
            .iter()
            .find(|op| op.kind != DiffLineKind::Added)
            .map(|op| op.old_index + 1)
            .unwrap_or(ops[start].old_index);
        let new_start = hunk
            .iter()
            .find(|op| op.kind != DiffLineKind::Removed)
            .map(|op| op.new_index + 1)
            .unwrap_or(ops[start].new_index);
        let old_count = hunk.iter().filter(|op| op.kind != DiffLineKind::Added).count();
        let new_count = hunk.iter().filter(|op| op.kind != DiffLineKind::Removed).count();
        result.push(DiffLine::new(
            DiffLineKind::Header,
            format!("@@ -{old_start},{old_count} +{new_start},{new_count} @@"),
        ));
        for op in hunk {
            let prefix = match op.kind {
                DiffLineKind::Added => "+",
                DiffLineKind::Removed => "-",
                _ => " ",
            };
            result.push(DiffLine::new(op.kind, format!("{prefix}{}", op.text)));
        }
    }
    result
}

pub fn text(old: &str, new: &str, path: &str) -> String {
    lines(old, new, path, DEFAULT_CONTEXT)
        .into_iter()
        .map(|line| line.text)
        .collect::<Vec<_>>()
        .join("\n")
}

fn edits<'a>(a: &[&'a str], b: &[&'a str]) -> Vec<Op<'a>> {
    let (n, m) = (a.len(), b.len());
    let mut table = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            table[i][j] = if a[i] == b[j] { table[i + 1][j + 1] + 1 } else { table[i + 1][j].max(table[i][j + 1]) };
        }
    }
    let mut ops = Vec::with_capacity(n + m);
    let (mut i, mut j) = (0, 0);
    while i < n || j < m {
        if i < n && j < m && a[i] == b[j] {
            ops.push(Op { kind: DiffLineKind::Context, text: a[i], old_index: i, new_index: j });
            i += 1;
            j += 1;
        } else if j < m && (i == n || table[i][j + 1] >= table[i + 1][j]) {
            ops.push(Op { kind: DiffLineKind::Added, text: b[j], old_index: i, new_index: j });
            j += 1;
        } else {
            ops.push(Op { kind: DiffLineKind::Removed, text: a[i], old_index: i, new_index: j });
            i += 1;
        }
    }
    ops
}
