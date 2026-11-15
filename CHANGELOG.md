# Changelog

Changes to `datastar` that a caller can notice.

## 0.1.0

The first tagged release. Compared with the untagged `main` before it.

### Breaking changes

Line endings:

- A carriage return in `Html`, in the `Script` of `execute_script/1,2`,
  in an attribute value or in pre-encoded signals JSON is now a line
  break, as `\n` already was. `\r\n` counts once. Every line gets its
  own `data:` line and the client receives each break as `\n`. Output
  for text without a carriage return is unchanged, apart from the
  changes below.
- Pre-encoded signals JSON that spans several lines is written as
  several `data: signals` lines and arrives whole.

Options:

- An option key the function does not take raises
  `{invalid_option, Key, unknown_option}`. Such a key used to be
  ignored. Options that are not a map raise
  `{invalid_option, options, not_a_map}`.
- An option that is present must hold a valid value. `selector`, `id`
  and `retry` set to `undefined` used to count as absent.
- `selector` and `id` must be iodata on one line. A value with `\r`,
  `\n` or a NUL byte raises
  `{invalid_option, Option, line_break | nul}` instead of being
  written. A value that is not iodata raises
  `{invalid_option, Option, not_iodata}`; an integer from 0 to 255 used
  to be written as one byte.
- `id` must be printable ASCII (`16#20` to `16#7E`). Anything else,
  which includes non-ASCII text and invalid UTF-8, raises
  `{invalid_option, id, not_printable_ascii}`.
- `mode` must be `outer`, `inner`, `replace`, `prepend`, `append`,
  `before`, `after` or `remove`, and `namespace` must be `html`, `svg`
  or `mathml`, as an atom or as a binary. Any other value raises
  `{invalid_option, mode, unknown_mode}` or
  `{invalid_option, namespace, unknown_namespace}`. Another binary used
  to be written as given.
- `retry` must be an integer from 0 to 2147483647. A negative or
  non-integer value raises
  `{invalid_option, retry, not_a_non_negative_integer}` and a larger
  one `{invalid_option, retry, too_large}`. A negative or larger
  integer used to be written.
- `use_view_transition`, `only_if_missing` and `auto_remove` must be
  booleans. Anything else raises
  `{invalid_option, Option, not_a_boolean}`.

`execute_script/2`:

- An attribute value is escaped for a double-quoted HTML attribute
  (`&`, `"`, `'`, `<` and `>`). A value that was escaped by the caller
  is now escaped twice.
- An attribute name must be a plain HTML attribute name: not empty,
  valid UTF-8, without whitespace, control characters, `"`, `'`, `>`,
  `/` or `=`. Any other name raises
  `{invalid_option, attributes, invalid_name}`.
- `attributes` must be a list of `{Name, Value}` pairs of iodata.
  Anything else raises
  `{invalid_option, attributes, not_a_list_of_pairs | not_iodata}`.
- A `Script` that contains `</script`, in any letter case, raises
  `{invalid_argument, script, closing_tag}`.

`patch_signals/1,2` and `remove_signals/1,2`:

- Pre-encoded signals must be exactly one JSON value, as
  `json:decode/1` reads it. Anything else, the empty string included,
  raises `{invalid_argument, signals, not_json}`. The check decodes the
  payload once; pass a map to have it encoded once and not checked.
- A signals map that `json` cannot encode raises
  `{invalid_argument, signals, not_encodable}` instead of the error of
  `json:encode/1`.
- Paths that are not a list of binaries raise
  `{invalid_argument, paths, not_a_list_of_binaries}`, and a path that
  is not valid UTF-8 raises `{invalid_argument, paths, not_encodable}`.

Errors and platform:

- `Html`, `Script` or pre-encoded signals that are not iodata raise
  `{invalid_argument, html | script | signals, not_iodata}` when the
  event is built. They used to raise `badarg`, or to give iodata that
  failed when it was sent.
- OTP 28 is the minimum. The README used to say 27.

### Changed

- No raised error, and no stack trace of one, holds the value that was
  refused.
- The nesting of the returned iodata differs in places. Its bytes are
  as described above.
- `remove_elements/1,2` is declared to take an iodata selector, and
  `attributes` to take iodata names and values, which is what they
  accepted.

### Fixed

- `remove_signals([~"a", ~"a.b"])` raised `{badmap, null}`. A path
  under a path that is removed as a whole now adds nothing.

### Added

- `CHANGELOG.md` and `SECURITY.md`.
- The module documentation lists every error reason, and each
  function's documentation names the errors it raises.
