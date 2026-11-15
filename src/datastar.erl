-module(datastar).
-moduledoc """
Erlang SDK for the [Datastar](https://data-star.dev) hypermedia framework.

Builds `iodata()` for Datastar v1 SSE events and parses incoming signal
payloads. Zero runtime dependencies. Framework-agnostic: pipe the output
into any chunked HTTP response (Cowboy `stream_body/3`, Mochiweb, inets,
whatever you have).

## Events

The Datastar v1 protocol defines two wire events:

- `datastar-patch-elements` — patch HTML into the DOM
- `datastar-patch-signals` — patch signals into the client-side store

`execute_script/1,2`, `remove_elements/1,2`, and `remove_signals/1,2`
compile down to these two events as ergonomic sugar.

## Quickstart

    Headers = datastar:sse_headers(),
    Event1  = datastar:patch_elements(~"<div id=\"status\">ready</div>"),
    Event2  = datastar:patch_signals(#{count => 1}),
    %% read signals sent from the browser:
    {ok, #{~"count" := N}} = datastar:read_signals(Body).
""".

-export([
    sse_headers/0,
    protocol_version/0,
    patch_elements/1, patch_elements/2,
    patch_signals/1, patch_signals/2,
    execute_script/1, execute_script/2,
    remove_elements/1, remove_elements/2,
    remove_signals/1, remove_signals/2,
    read_signals/1
]).

-export_type([
    mode/0,
    namespace/0,
    patch_elements_opts/0,
    patch_signals_opts/0,
    execute_script_opts/0
]).

-define(EVT_PATCH_ELEMENTS, ~"datastar-patch-elements").
-define(EVT_PATCH_SIGNALS, ~"datastar-patch-signals").

-type mode() ::
    outer | inner | replace | prepend | append | before | 'after' | remove | binary().
-type namespace() :: html | svg | mathml | binary().

-type patch_elements_opts() :: #{
    selector => iodata(),
    mode => mode(),
    use_view_transition => boolean(),
    namespace => namespace(),
    id => iodata(),
    retry => non_neg_integer()
}.

-type patch_signals_opts() :: #{
    only_if_missing => boolean(),
    id => iodata(),
    retry => non_neg_integer()
}.

-type execute_script_opts() :: #{
    auto_remove => boolean(),
    attributes => [{Name :: iodata(), Value :: iodata()}],
    id => iodata(),
    retry => non_neg_integer()
}.

-doc "Datastar protocol version this SDK targets.".
-spec protocol_version() -> binary().
protocol_version() -> ~"1.0".

-doc """
SSE response headers required by Datastar.

Returned as `[{binary(), binary()}]`, usable directly with
`cowboy_req:stream_reply/3`.
""".
-spec sse_headers() -> [{binary(), binary()}].
sse_headers() ->
    [
        {~"content-type", ~"text/event-stream"},
        {~"cache-control", ~"no-cache"},
        {~"connection", ~"keep-alive"}
    ].

-doc #{equiv => patch_elements(Html, #{})}.
-spec patch_elements(iodata()) -> iodata().
patch_elements(Html) ->
    patch_elements(Html, #{}).

-doc """
Build a `datastar-patch-elements` event that morphs `Html` into the DOM.

`Html` is split into one `data: elements <line>` per line, as required
by SSE framing. A line ends at `\r\n`, `\r` or `\n`, which is where an
SSE client ends it, so the client receives every line break as `\n`.

Options: `selector`, `mode` (default `outer`), `use_view_transition`,
`namespace` (default `html`), plus standard SSE `id` / `retry`.

`selector`, `mode`, `namespace` and `id` each take one line of the
event. A value with `\r`, `\n` or a NUL byte in it is refused with
`error({invalid_option, Option, line_break | nul})`, and a `retry` that
is not a non-negative integer with
`error({invalid_option, retry, not_a_non_negative_integer})`. The same
holds for these options in every other function of this module. NUL is
refused because a client drops an `id` that contains one; in `Html` it
is passed through.
""".
-spec patch_elements(iodata(), patch_elements_opts()) -> iodata().
patch_elements(Html, Opts) ->
    [
        event_line(?EVT_PATCH_ELEMENTS),
        sse_meta_lines(Opts),
        patch_elements_option_lines(Opts),
        elements_data_lines(Html),
        $\n
    ].

-doc #{equiv => patch_signals(Signals, #{})}.
-spec patch_signals(map() | iodata()) -> iodata().
patch_signals(Signals) ->
    patch_signals(Signals, #{}).

-doc """
Build a `datastar-patch-signals` event applying an RFC 7386 JSON Merge
Patch to the client signal store.

`Signals` may be a map (encoded via OTP's `json`) or pre-encoded JSON
iodata.

A map is written on one line: `json` escapes every control character,
`\r` and `\n` included. Pre-encoded JSON is split into one
`data: signals <line>` per line the same way `patch_elements/2` splits
HTML, so JSON that was pretty-printed arrives whole.

Pre-encoded JSON must be exactly one JSON value, as `json:decode/1`
reads it. Anything else is refused with
`error({invalid_argument, signals, not_json})`. The check decodes the
value once, so its cost grows with the size of the payload; a map is
encoded once and not checked again.

Options: `only_if_missing`, plus standard SSE `id` / `retry`.
""".
-spec patch_signals(map() | iodata(), patch_signals_opts()) -> iodata().
patch_signals(Signals, Opts) when is_map(Signals) ->
    signals_event(iolist_to_binary(json:encode(Signals)), Opts);
patch_signals(Json, Opts) ->
    signals_event(json_text(iolist_to_binary(Json)), Opts).

signals_event(Json, Opts) ->
    [
        event_line(?EVT_PATCH_SIGNALS),
        sse_meta_lines(Opts),
        patch_signals_option_lines(Opts),
        data_lines(~"data: signals ", Json),
        $\n
    ].

json_text(Bin) ->
    try json:decode(Bin) of
        _Value -> Bin
    catch
        error:_ -> error({invalid_argument, signals, not_json})
    end.

-doc #{equiv => execute_script(Script, #{})}.
-spec execute_script(iodata()) -> iodata().
execute_script(Script) ->
    execute_script(Script, #{}).

-doc """
Append a `<script>` to `<body>` so the browser executes it.

Compiles to `patch_elements/2` with `selector => ~"body"` and
`mode => append`, per the Datastar SDK spec.

Options: `auto_remove` (default `true`, adds `data-effect="el.remove()"`),
`attributes` (extra `[{Name, Value}]`), plus standard SSE `id` / `retry`.

An attribute value is escaped for a double-quoted HTML attribute (`&`,
`"`, `'`, `<` and `>`). An attribute name is written as given and must
be a plain HTML attribute name: not empty, valid UTF-8, and without
whitespace, control characters, `"`, `'`, `>`, `/` or `=`. Any other
name is refused with `error({invalid_option, attributes, invalid_name})`.

Escaping keeps a value inside its attribute. It does not make untrusted
text safe in an attribute whose value is code or a URL to load code
from, such as `src`, `on*` or a Datastar `data-*` expression: pass only
names you chose yourself, and only trusted values to such attributes.

`Script` is written into the element as given, without HTML escaping.
Line breaks in it are framed the way `patch_elements/2` frames `Html`.
A `Script` that contains `</script`, in any letter case, is refused
with `error({invalid_argument, script, closing_tag})`, because the
element would end there. Inside a JavaScript string, write `<\/script`.
""".
-spec execute_script(iodata(), execute_script_opts()) -> iodata().
execute_script(Script, Opts) ->
    AutoRemove = maps:get(auto_remove, Opts, true),
    Attrs = maps:get(attributes, Opts, []),
    ScriptEl = build_script_element(Script, AutoRemove, Attrs),
    PatchOpts = maps:with([id, retry], Opts),
    patch_elements(ScriptEl, PatchOpts#{selector => ~"body", mode => append}).

-doc #{equiv => remove_elements(Selector, #{})}.
-spec remove_elements(binary()) -> iodata().
remove_elements(Selector) ->
    remove_elements(Selector, #{}).

-doc """
Remove all elements matching `Selector` from the DOM.

`Selector` is a single-line value, see `patch_elements/2`.
""".
-spec remove_elements(binary(), patch_elements_opts()) -> iodata().
remove_elements(Selector, Opts) ->
    patch_elements(~"", Opts#{selector => Selector, mode => remove}).

-doc #{equiv => remove_signals(Paths, #{})}.
-spec remove_signals([binary()]) -> iodata().
remove_signals(Paths) ->
    remove_signals(Paths, #{}).

-doc """
Remove signals at the given dot-separated paths.

Builds a JSON Merge Patch where each leaf is `null` (RFC 7386 removal)
and sends it as a `datastar-patch-signals` event.

    datastar:remove_signals([~"user.name", ~"cart"]).
""".
-spec remove_signals([binary()], patch_signals_opts()) -> iodata().
remove_signals(Paths, Opts) ->
    patch_signals(build_null_merge(Paths), Opts).

-doc """
Decode a JSON signal payload into a map.

Datastar sends signals as URL-encoded JSON in the `datastar` query
parameter for `GET`, or as a JSON body otherwise. Once the framework
has URL-decoded the query value, both paths are raw JSON — pass it here.

    case datastar:read_signals(Body) of
        {ok, #{~"count" := N}} -> ...;
        {error, _Reason}       -> ...
    end.
""".
-spec read_signals(iodata()) ->
    {ok, map()} | {error, {invalid_json, term()} | not_an_object}.
read_signals(Payload) ->
    try json:decode(iolist_to_binary(Payload)) of
        Map when is_map(Map) -> {ok, Map};
        _ -> {error, not_an_object}
    catch
        error:Reason -> {error, {invalid_json, Reason}}
    end.

%% -- internal -----------------------------------------------------------------

event_line(Name) ->
    [~"event: ", Name, $\n].

sse_meta_lines(Opts) ->
    [id_line(maps:get(id, Opts, undefined)), retry_line(maps:get(retry, Opts, undefined))].

id_line(undefined) -> [];
id_line(Id) -> [~"id: ", single_line(id, Id), $\n].

retry_line(undefined) -> [];
retry_line(Retry) when is_integer(Retry), Retry >= 0 -> [~"retry: ", integer_to_binary(Retry), $\n];
retry_line(_Retry) -> error({invalid_option, retry, not_a_non_negative_integer}).

patch_elements_option_lines(Opts) ->
    [
        selector_line(maps:get(selector, Opts, undefined)),
        mode_line(maps:get(mode, Opts, outer)),
        use_view_transition_line(maps:get(use_view_transition, Opts, false)),
        namespace_line(maps:get(namespace, Opts, html))
    ].

selector_line(undefined) -> [];
selector_line(Sel) -> [~"data: selector ", single_line(selector, Sel), $\n].

mode_line(outer) -> [];
mode_line(inner) -> ~"data: mode inner\n";
mode_line(replace) -> ~"data: mode replace\n";
mode_line(prepend) -> ~"data: mode prepend\n";
mode_line(append) -> ~"data: mode append\n";
mode_line(before) -> ~"data: mode before\n";
mode_line('after') -> ~"data: mode after\n";
mode_line(remove) -> ~"data: mode remove\n";
mode_line(Mode) when is_binary(Mode) -> [~"data: mode ", single_line(mode, Mode), $\n].

use_view_transition_line(false) -> [];
use_view_transition_line(true) -> ~"data: useViewTransition true\n".

namespace_line(html) -> [];
namespace_line(svg) -> ~"data: namespace svg\n";
namespace_line(mathml) -> ~"data: namespace mathml\n";
namespace_line(Ns) when is_binary(Ns) -> [~"data: namespace ", single_line(namespace, Ns), $\n].

single_line(Option, Value) ->
    Bin = iolist_to_binary(Value),
    case binary:match(Bin, [~"\r", ~"\n", <<0>>]) of
        nomatch -> Bin;
        {Position, 1} -> error({invalid_option, Option, refused_byte(binary:at(Bin, Position))})
    end.

refused_byte(0) -> nul;
refused_byte(_LineBreak) -> line_break.

patch_signals_option_lines(Opts) ->
    case maps:get(only_if_missing, Opts, false) of
        true -> ~"data: onlyIfMissing true\n";
        false -> []
    end.

elements_data_lines(Html) ->
    case iolist_to_binary(Html) of
        <<>> -> [];
        Bin -> data_lines(~"data: elements ", Bin)
    end.

data_lines(Prefix, Bin) ->
    [[Prefix, Line, $\n] || Line <- lines(Bin)].

%% A single-pattern split is several times faster than a three-pattern one,
%% and text without a carriage return is the common case.
lines(Bin) ->
    case binary:match(Bin, ~"\r") of
        nomatch -> binary:split(Bin, ~"\n", [global]);
        _ -> binary:split(Bin, [~"\r\n", ~"\r", ~"\n"], [global])
    end.

build_script_element(Script, AutoRemove, Attrs) ->
    %% Per Datastar SDK ADR: `type` attribute is added only when custom
    %% attributes are present.
    TypeAttr =
        case Attrs of
            [] -> [];
            _ -> ~" type=\"application/javascript\""
        end,
    AutoAttr =
        case AutoRemove of
            true -> ~" data-effect=\"el.remove()\"";
            false -> []
        end,
    CustomAttrs = [
        [$\s, attribute_name(Name), ~"=\"", attribute_value(Value), $"]
     || {Name, Value} <- Attrs
    ],
    [~"<script", TypeAttr, AutoAttr, CustomAttrs, $>, script_body(Script), ~"</script>"].

script_body(Script) ->
    Bin = iolist_to_binary(Script),
    case re:run(Bin, ~"</script", [caseless, {capture, none}]) of
        nomatch -> Bin;
        match -> error({invalid_argument, script, closing_tag})
    end.

attribute_name(Name) ->
    Bin = iolist_to_binary(Name),
    case Bin =/= ~"" andalso plain_attribute_name(Bin) of
        true -> Bin;
        false -> error({invalid_option, attributes, invalid_name})
    end.

plain_attribute_name(<<>>) ->
    true;
plain_attribute_name(<<Char/utf8, Rest/binary>>) when
    Char > $\s,
    Char < 16#7F orelse Char > 16#9F,
    Char =/= $",
    Char =/= $',
    Char =/= $>,
    Char =/= $/,
    Char =/= $=
->
    plain_attribute_name(Rest);
plain_attribute_name(_Other) ->
    false.

attribute_value(Value) ->
    <<<<(escaped(Byte))/binary>> || <<Byte>> <= iolist_to_binary(Value)>>.

escaped($&) -> ~"&amp;";
escaped($") -> ~"&quot;";
escaped($') -> ~"&#39;";
escaped($<) -> ~"&lt;";
escaped($>) -> ~"&gt;";
escaped(Byte) -> <<Byte>>.

build_null_merge(Paths) ->
    build_null_merge(Paths, #{}).

build_null_merge([], Acc) ->
    Acc;
build_null_merge([Path | Rest], Acc) ->
    Parts = binary:split(Path, ~".", [global]),
    build_null_merge(Rest, put_null(Parts, Acc)).

put_null([Key], Acc) ->
    Acc#{Key => null};
put_null([Key | Rest], Acc) ->
    Inner = maps:get(Key, Acc, #{}),
    Acc#{Key => put_null(Rest, Inner)}.
