---
description: Prefer descriptive variable names over abbreviations
category: clarity
applies_to:
  file_extensions: [".py", ".js", ".ts", ".swift", ".go"]
---

# Descriptive Variable Names

Variable names should clearly communicate their purpose without requiring readers to decipher abbreviations or acronyms. Well-named variables make code self-documenting and reduce cognitive load.

## Requirements

### Use Full Words Over Abbreviations

Prefer complete words that clearly indicate what the variable represents:

```python
# ❌ Bad: Unclear abbreviations
usr = get_user()
req = parse_request()
cfg = load_config()

# ✅ Good: Clear, descriptive names
user = get_user()
request = parse_request()
config = load_config()
```

### Context-Appropriate Length

Variable names should be as long as necessary for clarity, considering their scope:

```python
# ✅ Good: Short names for short scope
for item in items:
    process(item)

# ✅ Good: Descriptive names for longer scope
def process_order(order_id):
    customer_account = fetch_customer_by_order(order_id)
    payment_method = customer_account.default_payment_method
    transaction_result = charge_payment_method(payment_method)
    return transaction_result
```

### Why This Matters

1. **Readability** — Code is read far more often than written; clear names save time
2. **Maintainability** — Future developers can understand code without historical context
3. **Reduced errors** — Similar abbreviations (e.g., `msg` vs `mgs`) are less likely to be confused
4. **Self-documentation** — Reduces need for explanatory comments

### Common Acceptable Abbreviations

Some abbreviations are widely understood and acceptable:
- Loop counters: `i`, `j`, `k` (in short loops)
- Common acronyms: `id`, `url`, `api`, `html`, `json`
- Mathematical variables: `x`, `y`, `n` (when contextually clear)

## What to Check

When reviewing code:

1. **Single-letter names** — Look for single letters used outside loop counters
2. **Vowel-removed abbreviations** — Names like `usr`, `msg`, `cfg` that drop vowels
3. **Domain-specific jargon** — Acronyms that aren't universally understood
4. **Similar names** — Variables with abbreviated names that could be confused

## GitHub Comment

```
Consider using a more descriptive variable name here. Full words make the code easier to read and maintain without requiring readers to decipher abbreviations.
```
