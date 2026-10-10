use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::models::UserPrompt;
use crate::util::trim_spaces;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Correction {
    pub prompt: UserPrompt,
    pub rule: Option<String>,
    pub score: i64,
}

pub const OPENERS: &[&str] = &[
    "non", "no", "nope", "nan", "stop", "arrête", "arrete", "attends", "wait", "pas ça", "pas ca",
    "c'est pas", "ce n'est pas", "c'est faux", "faux", "wrong", "that's wrong", "that's not", "not what i",
    "je t'ai dit", "je t'avais dit", "i told you", "i said", "on a dit", "j'ai dit", "pourquoi tu", "why did you",
    "why are you", "tu as oublié", "t'as oublié", "you forgot", "encore", "again", "revert", "annule", "undo",
];

pub const RULE_MARKERS: &[&str] = &[
    "toujours", "jamais", "always", "never", "don't", "do not", "n'utilise pas", "n'ajoute pas", "ne touche pas",
    "ne mets pas", "ne fais pas", "il ne faut pas", "évite", "evite", "avoid", "prefer", "préfère", "prefere",
    "instead of", "plutôt que", "plutot que", "au lieu de", "n'oublie pas", "remember to", "make sure",
    "assure-toi", "à chaque fois", "a chaque fois", "every time", "each time", "no more", "arrête de", "arrete de",
    "stop using", "stop adding", "by default", "par défaut",
];

pub const SPECIFIC_MARKERS: &[&str] =
    &["http", "/issues/", "/pull/", "ce fichier", "this file", "cette pr", "this pr", "ce ticket", "la version d'avant"];

pub const CORRECTION_PHRASES: &[&str] = &[
    "je t'ai dit", "je t'avais dit", "i told you", "i said", "on a dit", "tu as oublié", "t'as oublié",
    "you forgot", "pas comme ça", "pas comme ca", "c'est pas ce que", "that's not what", "not what i asked",
    "pourquoi tu as", "why did you", "tu n'aurais pas dû", "you shouldn't have", "you should not have",
    "encore une fois", "once again", "combien de fois", "how many times",
];

const CLEAN_PREFIXES: &[&str] = &[
    "non,", "non ", "no,", "no ", "nope,", "nan,", "stop,", "attends,", "wait,", "mais ", "but ",
    "je t'ai dit de ", "je t'ai dit que ", "je t'ai dit ", "i told you to ", "i told you ", "i said ",
    "on a dit ", "j'ai dit ", "encore une fois,", "encore une fois ", "again,", "please ", "stp ", "s'il te plaît ",
];

const STOP_WORDS: &[&str] = &[
    "le", "la", "les", "de", "des", "un", "une", "et", "à", "a", "en", "the", "an", "to", "of",
    "and", "in", "on", "is", "it", "pas", "ne", "you", "tu", "je", "i", "que", "qui", "pour", "for",
];

pub fn detect(prompt: &UserPrompt) -> Option<Correction> {
    let text = &prompt.text;
    let length = text.chars().count();
    if !(6..=700).contains(&length) || text.starts_with('/') {
        return None;
    }
    let lower = text.to_lowercase();
    let mut score = 0;
    let head: String = lower.chars().take(24).collect();
    let opens_with_correction = OPENERS.iter().any(|opener| {
        head == *opener || [" ", ",", ".", "!"].iter().any(|separator| head.starts_with(&format!("{opener}{separator}")))
    });
    if opens_with_correction {
        score += 2;
    }
    score += CORRECTION_PHRASES.iter().filter(|phrase| lower.contains(*phrase)).count() as i64 * 2;
    let rule = extract_rule(text);
    if rule.is_some() {
        score += 1;
    }
    if score < 2 {
        return None;
    }
    Some(Correction { prompt: prompt.clone(), rule, score })
}

pub fn extract_rule(text: &str) -> Option<String> {
    let flattened = text.replace('\n', ". ");
    let sentences = flattened
        .split(['.', '!', '?', ';'])
        .filter(|part| !part.is_empty())
        .map(trim_spaces)
        .filter(|sentence| sentence.chars().count() >= 8);
    let mut best: Option<&str> = None;
    for sentence in sentences {
        let lower = sentence.to_lowercase();
        let is_rule = RULE_MARKERS.iter().any(|marker| lower.contains(marker))
            && !SPECIFIC_MARKERS.iter().any(|marker| lower.contains(marker));
        if !is_rule {
            continue;
        }
        if best.is_none_or(|current| marker_count(current) < marker_count(sentence)) {
            best = Some(sentence);
        }
    }
    let cleaned = clean(best?);
    let length = cleaned.chars().count();
    (8..=220).contains(&length).then_some(cleaned)
}

pub fn marker_count(sentence: &str) -> usize {
    let lower = sentence.to_lowercase();
    RULE_MARKERS.iter().filter(|marker| lower.contains(*marker)).count()
}

pub fn clean(sentence: &str) -> String {
    let mut text = sentence.to_string();
    let mut changed = true;
    while changed {
        changed = false;
        for prefix in CLEAN_PREFIXES {
            if text.to_lowercase().starts_with(prefix) {
                let rest: String = text.chars().skip(prefix.chars().count()).collect();
                text = trim_spaces(&rest).to_string();
                changed = true;
            }
        }
    }
    let mut chars = text.chars();
    let Some(first) = chars.next() else { return text };
    let mut result: String = first.to_uppercase().collect();
    result.push_str(chars.as_str());
    if !result.ends_with('.') {
        result.push('.');
    }
    result
}

pub fn words(text: &str) -> HashSet<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| word.chars().count() > 1 && !STOP_WORDS.contains(word))
        .map(str::to_string)
        .collect()
}

pub fn similarity(a: &str, b: &str) -> f64 {
    let (wa, wb) = (words(a), words(b));
    if wa.is_empty() || wb.is_empty() {
        return 0.0;
    }
    wa.intersection(&wb).count() as f64 / wa.union(&wb).count() as f64
}
