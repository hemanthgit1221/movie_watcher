"""Shared DOM normalization utilities — Phase 3."""


def normalize_whitespace(html: str) -> str:
    """Collapse ASCII whitespace runs for fingerprints and cheap matching."""
    return " ".join(html.split())


def snippet_fingerprint(normalized_html: str, *, max_chars: int = 120) -> str:
    """Short non-cryptographic fingerprint for logs / coarse diffing."""
    return normalized_html.strip()[:max_chars]
