# datastar

Erlang SDK for [Datastar](https://data-star.dev), the hypermedia framework
that collapses HTMX + Alpine into a single `data-*` vocabulary with SSE as
a first-class transport.

- **Pure Erlang, zero runtime deps.** Uses OTP's built-in `json` module
  and nothing else.
- **Framework-agnostic.** Returns `iodata()`. Plug into Cowboy, Nova, or
  anything else that can stream chunked HTTP.
- **v1 protocol.** Targets Datastar SDK v1 (`datastar-patch-elements`,
  `datastar-patch-signals`; `execute-script` / `remove-*` as sugar).
- **First SDK for the BEAM in Erlang.**

## Install

Add to `rebar.config`:

```erlang
{deps, [
    {datastar, {git, "https://github.com/Taure/datastar.git", {tag, "vX.Y.Z"}}}
]}.
```

`vX.Y.Z` is a placeholder. Put the release you want in its place; the
releases are listed in [CHANGELOG.md](CHANGELOG.md).

Requires OTP 28 or later.

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
both paths are just raw JSON. Hand it to `read_signals/1`:

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

One module, `datastar`: everything (event builders, headers, signal
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

## Line endings

An SSE client ends a line at `\r\n`, `\r` or `\n`. The builders follow the
same rule:

| Input | What happens to `\r`, `\n`, `\r\n` |
|-------|-----------------------------------|
| `Html` of `patch_elements/1,2`, `Script` and attribute values of `execute_script/1,2` | Each one ends a line. Every line gets its own `data: elements` prefix. The client receives the break as `\n`. |
| Pre-encoded JSON of `patch_signals/1,2` | Same, with a `data: signals` prefix. JSON allows a line break between tokens only. |
| A map given to `patch_signals/1,2`, the paths of `remove_signals/1,2` | Encoded by `json`, which escapes every control character, so the value is one line. |
| `selector`, `id` | Refused: `error({invalid_option, Option, line_break})`. |

A NUL byte in `selector` or `id` is refused too
(`error({invalid_option, Option, nul})`), because a client drops an `id`
that contains one. In HTML and scripts it is passed through unchanged; in
a map it is escaped as `\u0000`. U+2028 and U+2029 are not line breaks in
SSE and are sent as the UTF-8 text they are.

## What the builders check

The builders raise on a bad option or argument. They do not return an
error tuple and they do not rewrite a value to make it fit.

| Input | Rule |
|-------|------|
| Options | A map. Every key is one the function takes. A key that is present holds a valid value: `undefined` does not stand for an absent option. |
| `selector` | iodata on one line. |
| `mode` | `outer`, `inner`, `replace`, `prepend`, `append`, `before`, `after` or `remove`, as an atom or a binary. |
| `namespace` | `html`, `svg` or `mathml`, as an atom or a binary. |
| `use_view_transition`, `only_if_missing`, `auto_remove` | A boolean. |
| `id` | Printable ASCII (`16#20` to `16#7E`) on one line. A client sends the last `id` back in a request header when it reconnects. |
| `retry` | An integer from 0 to 2147483647 milliseconds (2^31 - 1, a little under 25 days, the longest delay a browser timer takes). |
| Pre-encoded JSON of `patch_signals/1,2` | Exactly one JSON value, as `json:decode/1` reads it. |
| `attributes` of `execute_script/2` | A list of `{Name, Value}`. A value is escaped for a double-quoted HTML attribute. A name is written as given and must be a plain HTML attribute name: not empty, valid UTF-8, without whitespace, control characters, `"`, `'`, `>`, `/` or `=`. |
| `Script` of `execute_script/1,2` | Must not contain `</script`, in any letter case: the element would end there. Inside a JavaScript string, write `<\/script`. |

Two errors are raised:

- `error({invalid_option, Option, Reason})` for a key of the options map
- `error({invalid_argument, Argument, Reason})` for `html`, `script`,
  `signals` or `paths`

Neither one, nor its stack trace, holds the value that was refused. The
module documentation lists every `Reason` and the errors each function
raises.

The check on pre-encoded JSON decodes the payload once, so it takes time
in proportion to its size. A caller that holds the signals as a map can
pass the map: it is encoded once and not checked again.

The builders do not escape `Html` or `Script`. Escaping text that goes
into markup is the job of whatever builds the markup. Escaping an
attribute value of `execute_script/2` keeps it inside its attribute; it
does not make untrusted text safe in an attribute whose value is code
or a URL to load code from, such as `src`, `on*` or a Datastar `data-*`
expression.

## Upgrading

Every change a caller can notice is listed in
[CHANGELOG.md](CHANGELOG.md), breaking changes first.

## License

Apache-2.0.
