# PowerShell 5.1 reads `"$var:"` as a drive reference

**Rule:** In Windows PowerShell 5.1, `"$var:something"` inside a double-quoted string is parsed as a drive-qualified variable (`$var:` looks like `$env:` or `$function:`), not as `$var` followed by a literal colon. Use `"${var}:something"` whenever a variable is immediately followed by a colon in a string.

**Why:** This silently produces an empty or wrong value instead of an error, so it is easy to ship and hard to notice until the output is inspected closely.

**How to apply:** Whenever building a string in PowerShell where a variable is directly followed by `:`, always use the `${var}` brace form. Prefer this defensively in any script meant to run on Windows PowerShell 5.1, not just where a bug was already seen.
