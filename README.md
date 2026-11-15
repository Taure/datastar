# datastar

Erlang SDK for [Datastar](https://data-star.dev) — the hypermedia framework
that collapses HTMX + Alpine into a single `data-*` vocabulary with SSE as
a first-class transport.

- **Pure Erlang, zero runtime deps.** Uses OTP's built-in `json` module
  (OTP 27+) and nothing else.
- **Framework-agnostic.** Returns `iodata()`. Plug into Cowboy, Nova, or
  anything else that can stream chunked HTTP.
- **v1 protocol.** Targets Datastar SDK v1 (`datastar-patch-elements`,
  `datastar-patch-signals`; `execute-script` / `remove-*` as sugar).
- **First SDK for the BEAM in Erlang.**

## Install

Add to `rebar.config`:

```erlang
{deps, [
    {datastar, {git, "https://github.com/Taure/datastar.git", {branch, "main"}}}
]}.
```

Requires OTP 27+ (for the built-in `json` module).

## Quickstart

### Emit events

```erlang
%% 1. Send the SSE response headers when handling the request.
Headers = datastar:sse_headers().
%% -> [{~"content-type", ~"text/event-stream"},
%%     {~"cache-control", ~"no-cache"},
%%     {~"connection", ~"keep-alive"}]

%% 2. Build events (each is iodata) and write them to the stream.
Event1 = datastar:patch_elements(~"<div id=\"status\">ready</div>").

Event2 = datastar:patch_elements(
    ~"<li>apple</li>\n<li>pear</li>",
    #{selector => ~"#list", mode => append}
).

Event3 = datastar:patch_signals(#{count => 5, user => #{name => ~"jo"}}).

Event4 = datastar:execute_script(~"console.log('hello')").

Event5 = datastar:remove_elements(~"#banner").

Event6 = datastar:remove_signals([~"user.email", ~"cart"]).
```

### Read signals from the request

Datastar sends the current signal store on every action: as a URL-encoded
JSON string in the `datastar` query parameter for `GET`, or as the JSON
body otherwise. After your web framework has URL-decoded the query value,
both paths are just raw JSON — hand it to `read_signals/1`:

```erlang
case datastar:read_signals(Body) of
    {ok, #{~"count" := N}} -> ...;
    {error, _Reason}       -> ...
end.
```

## Cowboy integration

```erlang
init(Req0, State) ->
    Req1 = cowboy_req:stream_reply(200, maps:from_list(datastar:sse_headers()), Req0),
    Event = datastar:patch_elements(~"<p id=\"hello\">hi</p>"),
    Req  = cowboy_req:stream_body(Event, nofin, Req1),
    {ok, Req, State}.
```

For long-lived streams, use `cowboy_loop` and write a new event each time
you want to push an update.

## Nova integration

`datastar` itself has no Nova dependency. A thin adapter
(`nova_datastar`) with return-tuple conventions and an `Accept`-header
plugin is planned as a separate library.

## Module layout

One module, `datastar` — everything (event builders, headers, signal
reader) lives there.

## Protocol coverage

| Datastar event              | Function                       |
|-----------------------------|--------------------------------|
| `datastar-patch-elements`   | `datastar:patch_elements/1,2`  |
| `datastar-patch-signals`    | `datastar:patch_signals/1,2`   |
| Script execution (sugar)    | `datastar:execute_script/1,2`  |
| Element removal (sugar)     | `datastar:remove_elements/1,2` |
| Signal removal (sugar)      | `datastar:remove_signals/1,2`  |

All `data:`-level fields from the v1 spec are supported: `selector`,
`mode`, `useViewTransition`, `namespace`, `onlyIfMissing`, `signals`,
`elements`, plus the standard SSE `id` and `retry` fields.

## Line endings and option values

An SSE client ends a line at `\r\n`, `\r` or `\n`. The builders follow the
same rule:

| Input | What happens to `\r`, `\n`, `\r\n` |
|-------|-----------------------------------|
| `Html` of `patch_elements/1,2`, `Script` and `attributes` of `execute_script/1,2` | Each one ends a line. Every line gets its own `data: elements` prefix. The client receives the break as `\n`. |
| Pre-encoded JSON of `patch_signals/1,2` | Same, with a `data: signals` prefix. |
| A map given to `patch_signals/1,2`, the paths of `remove_signals/1,2` | Encoded by `json`, which escapes every control character, so the value is one line. |
| `selector`, `mode`, `namespace`, `id` | Refused: `error({invalid_option, Option, line_break})`. |
| `retry` | Must be a non-negative integer: `error({invalid_option, retry, not_a_non_negative_integer})`. |

A NUL byte in `selector`, `mode`, `namespace` or `id` is refused too
(`error({invalid_option, Option, nul})`), because a client drops an `id`
that contains one. In HTML, scripts and pre-encoded JSON it is passed
through unchanged; in a map it is escaped as `\u0000`. U+2028 and U+2029
are not line breaks in SSE and are sent as the UTF-8 text they are.

The builders do not escape HTML. `execute_script/2` writes the script
body and the attribute names and values as given.

## Upgrading

Changes after `fcc11f3` that a caller can notice:

- A carriage return in streamed HTML, in a script or in pre-encoded
  signals JSON is now a line break, as `\n` already was. `\r\n` counts
  once. The browser receives `\n` in its place.
- Pre-encoded signals JSON that spans several lines is now sent as
  several `data: signals` lines and arrives whole.
- `selector`, `mode`, `namespace` and `id` values containing `\r`, `\n`
  or NUL raise `{invalid_option, Option, line_break | nul}` instead of
  being written. Validate or strip such values before passing them.
- `retry` raises `{invalid_option, retry, not_a_non_negative_integer}`
  for anything but a non-negative integer.

## License

Apache-2.0.
