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

## Errors

The event builders raise on a bad option or argument. They do not
return an error tuple and they do not rewrite a value to make it fit.
Two errors are raised, and neither one, nor its stack trace, holds the
value that was refused:

- `error({invalid_option, Option, Reason})` for a key of the options
  map. `Option` is the key, or `options` for the map as a whole.
- `error({invalid_argument, Argument, Reason})` for `html`, `script`,
  `signals` or `paths`.

| Reason | Raised for |
|--------|------------|
| `unknown_option` | a key the function does not take |
| `not_a_map` | options that are not a map |
| `not_iodata` | `selector`, `id`, an attribute name or value, `html`, `script`, pre-encoded `signals` |
| `line_break` | `\r` or `\n` in `selector` or `id` |
| `nul` | a NUL byte in `selector` or `id` |
| `not_printable_ascii` | a byte outside `16#20` to `16#7E` in `id` |
| `unknown_mode` | `mode` |
| `unknown_namespace` | `namespace` |
| `not_a_boolean` | `use_view_transition`, `only_if_missing`, `auto_remove` |
| `not_a_non_negative_integer` | `retry` |
| `too_large` | a `retry` above 2147483647 |
| `not_a_list_of_pairs` | `attributes` |
| `invalid_name` | an attribute name |
| `closing_tag` | a `script` that contains `</script` |
| `not_json` | pre-encoded `signals` |
| `not_encodable` | a `signals` map or `paths` that `json` cannot encode |
| `not_a_list_of_binaries` | `paths` |

An option that is present must hold a valid value: `undefined` does not
stand for an absent option. `read_signals/1` reads untrusted input and
returns `{error, Reason}` instead of raising.
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
-define(MAX_RETRY, 2147483647).
-define(MODES, [
    ~"outer", ~"inner", ~"replace", ~"prepend", ~"append", ~"before", ~"after", ~"remove"
]).
-define(NAMESPACES, [~"html", ~"svg", ~"mathml"]).

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
SSE client ends it, so the client receives every line break as `\n`. A
NUL byte in `Html` is passed through.

Options:

- `selector`: a CSS selector, on one line.
- `mode`: `outer` (default), `inner`, `replace`, `prepend`, `append`,
  `before`, `after` or `remove`, as an atom or as a binary.
- `namespace`: `html` (default), `svg` or `mathml`, as an atom or as a
  binary.
- `use_view_transition`: a boolean, `false` by default.
- `id`: the SSE event id. A client sends the last `id` it received back
  in a request header when it reconnects, so an `id` is printable ASCII
  (`16#20` to `16#7E`) on one line.
- `retry`: the SSE reconnection time in milliseconds, an integer from 0
  to 2147483647 (2^31 - 1, a little under 25 days, the longest delay a
  browser timer takes).

`id` and `retry` are taken by every builder in this module and are
checked the same way everywhere.

Raises:

- `{invalid_argument, html, not_iodata}`
- `{invalid_option, selector, not_iodata | line_break | nul}`
- `{invalid_option, mode, unknown_mode}`
- `{invalid_option, namespace, unknown_namespace}`
- `{invalid_option, use_view_transition, not_a_boolean}`
- `{invalid_option, id, not_iodata | line_break | nul | not_printable_ascii}`.
  The first byte that is refused decides the reason.
- `{invalid_option, retry, not_a_non_negative_integer | too_large}`
- `{invalid_option, Key, unknown_option}` for any other key, and
  `{invalid_option, options, unknown_option | not_a_map}` when a key is
  not an atom or the options are not a map.
""".
-spec patch_elements(iodata(), patch_elements_opts()) -> iodata().
patch_elements(Html, Opts) ->
    known_options(Opts, [selector, mode, use_view_transition, namespace, id, retry]),
    [
        event_line(?EVT_PATCH_ELEMENTS),
        sse_meta_lines(Opts),
        patch_elements_option_lines(Opts),
        elements_data_lines(to_binary(Html, {invalid_argument, html, not_iodata})),
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
reads it. The check decodes the value once, so its cost grows with the
size of the payload; a map is encoded once and not checked again.

Options: `only_if_missing` (a boolean, `false` by default), plus `id`
and `retry` as in `patch_elements/2`.

Raises:

- `{invalid_argument, signals, not_iodata | not_json}` for pre-encoded
  JSON
- `{invalid_argument, signals, not_encodable}` for a map that `json`
  cannot encode
- `{invalid_option, only_if_missing, not_a_boolean}`
- the `id`, `retry`, `unknown_option` and `not_a_map` errors of
  `patch_elements/2`
""".
-spec patch_signals(map() | iodata(), patch_signals_opts()) -> iodata().
patch_signals(Signals, Opts) when is_map(Signals) ->
    signals_event(encoded_line(Signals, signals), Opts);
patch_signals(Json, Opts) ->
    Text = json_text(to_binary(Json, {invalid_argument, signals, not_iodata})),
    signals_event(data_lines(~"data: signals ", Text), Opts).

signals_event(DataLines, Opts) ->
    known_options(Opts, [only_if_missing, id, retry]),
    [
        event_line(?EVT_PATCH_SIGNALS),
        sse_meta_lines(Opts),
        patch_signals_option_lines(Opts),
        DataLines,
        $\n
    ].

encoded_line(Map, Argument) ->
    try
        [~"data: signals ", json:encode(Map), $\n]
    catch
        error:_ -> error({invalid_argument, Argument, not_encodable})
    end.

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

Options: `auto_remove` (a boolean, `true` by default, adds
`data-effect="el.remove()"`), `attributes` (extra `[{Name, Value}]`),
plus `id` and `retry` as in `patch_elements/2`.

An attribute value is escaped for a double-quoted HTML attribute (`&`,
`"`, `'`, `<` and `>`). An attribute name is written as given and must
be a plain HTML attribute name: not empty, valid UTF-8, and without
whitespace, control characters, `"`, `'`, `>`, `/` or `=`.

Escaping keeps a value inside its attribute. It does not make untrusted
text safe in an attribute whose value is code or a URL to load code
from, such as `src`, `on*` or a Datastar `data-*` expression: pass only
names you chose yourself, and only trusted values to such attributes.

`Script` is written into the element as given, without HTML escaping.
Line breaks in it are framed the way `patch_elements/2` frames `Html`.
A `Script` that contains `</script`, in any letter case, is refused,
because the element would end there. Inside a JavaScript string, write
`<\/script`.

Raises:

- `{invalid_argument, script, not_iodata | closing_tag}`
- `{invalid_option, auto_remove, not_a_boolean}`
- `{invalid_option, attributes, not_a_list_of_pairs | not_iodata | invalid_name}`
- the `id`, `retry`, `unknown_option` and `not_a_map` errors of
  `patch_elements/2`
""".
-spec execute_script(iodata(), execute_script_opts()) -> iodata().
execute_script(Script, Opts) ->
    known_options(Opts, [auto_remove, attributes, id, retry]),
    Element = script_element(Script, flag(auto_remove, Opts, true), maps:get(attributes, Opts, [])),
    PatchOpts = maps:with([id, retry], Opts),
    patch_elements(Element, PatchOpts#{selector => ~"body", mode => append}).

-doc #{equiv => remove_elements(Selector, #{})}.
-spec remove_elements(iodata()) -> iodata().
remove_elements(Selector) ->
    remove_elements(Selector, #{}).

-doc """
Remove all elements matching `Selector` from the DOM.

`Selector` is the `selector` option of `patch_elements/2` and is
checked the same way. `Opts` takes the options of `patch_elements/2`;
`selector` and `mode` in it are replaced.

Raises the option errors of `patch_elements/2`.
""".
-spec remove_elements(iodata(), patch_elements_opts()) -> iodata().
remove_elements(Selector, Opts) when is_map(Opts) ->
    patch_elements(~"", Opts#{selector => Selector, mode => remove});
remove_elements(_Selector, _Opts) ->
    error({invalid_option, options, not_a_map}).

-doc #{equiv => remove_signals(Paths, #{})}.
-spec remove_signals([binary()]) -> iodata().
remove_signals(Paths) ->
    remove_signals(Paths, #{}).

-doc """
Remove signals at the given dot-separated paths.

Builds a JSON Merge Patch where each leaf is `null` (RFC 7386 removal)
and sends it as a `datastar-patch-signals` event.

    datastar:remove_signals([~"user.name", ~"cart"]).

A path under a path that is removed as a whole adds nothing:
`[~"user", ~"user.name"]` removes `user`.

Options: as in `patch_signals/2`.

Raises:

- `{invalid_argument, paths, not_a_list_of_binaries}`
- `{invalid_argument, paths, not_encodable}` for a path to remove that
  is not valid UTF-8
- the option errors of `patch_signals/2`
""".
-spec remove_signals([binary()], patch_signals_opts()) -> iodata().
remove_signals(Paths, Opts) ->
    signals_event(encoded_line(null_merge(Paths, #{}), paths), Opts).

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

known_options(Opts, Known) when is_map(Opts) ->
    known_keys(maps:next(maps:iterator(Opts)), Known);
known_options(_Opts, _Known) ->
    error({invalid_option, options, not_a_map}).

known_keys(none, _Known) ->
    ok;
known_keys({Key, _Value, Iterator}, Known) ->
    case lists:member(Key, Known) of
        true -> known_keys(maps:next(Iterator), Known);
        false when is_atom(Key) -> error({invalid_option, Key, unknown_option});
        false -> error({invalid_option, options, unknown_option})
    end.

flag(Option, Opts, Default) ->
    case maps:get(Option, Opts, Default) of
        Flag when is_boolean(Flag) -> Flag;
        _Other -> error({invalid_option, Option, not_a_boolean})
    end.

to_binary(Value, _Error) when is_binary(Value) ->
    Value;
to_binary(Value, Error) ->
    try
        iolist_to_binary(Value)
    catch
        error:badarg -> error(Error)
    end.

event_line(Name) ->
    [~"event: ", Name, $\n].

sse_meta_lines(Opts) ->
    [id_line(Opts), retry_line(Opts)].

id_line(#{id := Id}) ->
    [~"id: ", event_id(to_binary(Id, {invalid_option, id, not_iodata})), $\n];
id_line(#{}) ->
    [].

event_id(Id) ->
    case refused_in_id(Id) of
        nothing -> Id;
        Reason -> error({invalid_option, id, Reason})
    end.

refused_in_id(~"") -> nothing;
refused_in_id(<<Byte, Rest/binary>>) when Byte >= $\s, Byte =< $~ -> refused_in_id(Rest);
refused_in_id(<<Byte, _/binary>>) when Byte =:= $\r; Byte =:= $\n -> line_break;
refused_in_id(<<0, _/binary>>) -> nul;
refused_in_id(_Other) -> not_printable_ascii.

retry_line(#{retry := Retry}) when is_integer(Retry), Retry >= 0, Retry =< ?MAX_RETRY ->
    [~"retry: ", integer_to_binary(Retry), $\n];
retry_line(#{retry := Retry}) when is_integer(Retry), Retry > ?MAX_RETRY ->
    error({invalid_option, retry, too_large});
retry_line(#{retry := _Other}) ->
    error({invalid_option, retry, not_a_non_negative_integer});
retry_line(#{}) ->
    [].

patch_elements_option_lines(Opts) ->
    [
        selector_line(Opts),
        mode_line(maps:get(mode, Opts, outer)),
        use_view_transition_line(flag(use_view_transition, Opts, false)),
        namespace_line(maps:get(namespace, Opts, html))
    ].

selector_line(#{selector := Selector}) ->
    [~"data: selector ", single_line(selector, Selector), $\n];
selector_line(#{}) ->
    [].

mode_line(outer) ->
    [];
mode_line(inner) ->
    ~"data: mode inner\n";
mode_line(replace) ->
    ~"data: mode replace\n";
mode_line(prepend) ->
    ~"data: mode prepend\n";
mode_line(append) ->
    ~"data: mode append\n";
mode_line(before) ->
    ~"data: mode before\n";
mode_line('after') ->
    ~"data: mode after\n";
mode_line(remove) ->
    ~"data: mode remove\n";
mode_line(Mode) ->
    case is_binary(Mode) andalso lists:member(Mode, ?MODES) of
        true -> [~"data: mode ", Mode, $\n];
        false -> error({invalid_option, mode, unknown_mode})
    end.

use_view_transition_line(false) -> [];
use_view_transition_line(true) -> ~"data: useViewTransition true\n".

namespace_line(html) ->
    [];
namespace_line(svg) ->
    ~"data: namespace svg\n";
namespace_line(mathml) ->
    ~"data: namespace mathml\n";
namespace_line(Namespace) ->
    case is_binary(Namespace) andalso lists:member(Namespace, ?NAMESPACES) of
        true -> [~"data: namespace ", Namespace, $\n];
        false -> error({invalid_option, namespace, unknown_namespace})
    end.

single_line(Option, Value) ->
    Bin = to_binary(Value, {invalid_option, Option, not_iodata}),
    case binary:match(Bin, line_break_or_nul()) of
        nomatch -> Bin;
        {Position, 1} -> error({invalid_option, Option, refused_byte(binary:at(Bin, Position))})
    end.

refused_byte(0) -> nul;
refused_byte(_LineBreak) -> line_break.

%% Compiling the pattern costs several times more than matching a short
%% value against it, so it is compiled once and kept.
line_break_or_nul() ->
    case persistent_term:get({?MODULE, line_break_or_nul}, undefined) of
        undefined ->
            Pattern = binary:compile_pattern([~"\r", ~"\n", ~"\0"]),
            persistent_term:put({?MODULE, line_break_or_nul}, Pattern),
            Pattern;
        Pattern ->
            Pattern
    end.

patch_signals_option_lines(Opts) ->
    case flag(only_if_missing, Opts, false) of
        true -> ~"data: onlyIfMissing true\n";
        false -> []
    end.

elements_data_lines(~"") -> [];
elements_data_lines(Html) -> data_lines(~"data: elements ", Html).

data_lines(Prefix, Bin) ->
    [[Prefix, Line, $\n] || Line <- lines(Bin)].

%% A single-pattern split is several times faster than a three-pattern one,
%% so only text with a carriage return pays for the three-pattern one.
lines(Bin) ->
    case binary:match(Bin, ~"\r") of
        nomatch -> binary:split(Bin, ~"\n", [global]);
        _ -> binary:split(Bin, [~"\r\n", ~"\r", ~"\n"], [global])
    end.

script_element(Script, AutoRemove, Attributes) ->
    %% Per Datastar SDK ADR: `type` attribute is added only when custom
    %% attributes are present.
    TypeAttribute =
        case Attributes of
            [] -> [];
            _ -> ~" type=\"application/javascript\""
        end,
    AutoRemoveAttribute =
        case AutoRemove of
            true -> ~" data-effect=\"el.remove()\"";
            false -> []
        end,
    [
        ~"<script",
        TypeAttribute,
        AutoRemoveAttribute,
        script_attributes(Attributes),
        $>,
        script_body(Script),
        ~"</script>"
    ].

script_attributes([]) ->
    [];
script_attributes([{Name, Value} | Rest]) ->
    [[$\s, attribute_name(Name), ~"=\"", attribute_value(Value), $"] | script_attributes(Rest)];
script_attributes(_Other) ->
    error({invalid_option, attributes, not_a_list_of_pairs}).

attribute_name(Name) ->
    Bin = to_binary(Name, {invalid_option, attributes, not_iodata}),
    case Bin =/= ~"" andalso plain_attribute_name(Bin) of
        true -> Bin;
        false -> error({invalid_option, attributes, invalid_name})
    end.

plain_attribute_name(~"") ->
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
    Bin = to_binary(Value, {invalid_option, attributes, not_iodata}),
    <<<<(escaped(Byte))/binary>> || <<Byte>> <= Bin>>.

escaped($&) -> ~"&amp;";
escaped($") -> ~"&quot;";
escaped($') -> ~"&#39;";
escaped($<) -> ~"&lt;";
escaped($>) -> ~"&gt;";
escaped(Byte) -> <<Byte>>.

script_body(Script) ->
    Bin = to_binary(Script, {invalid_argument, script, not_iodata}),
    case
        binary:match(Bin, ~"</") =/= nomatch andalso
            re:run(Bin, ~"</script", [caseless, {capture, none}])
    of
        match -> error({invalid_argument, script, closing_tag});
        _NoClosingTag -> Bin
    end.

null_merge([], Merge) ->
    Merge;
null_merge([Path | Rest], Merge) when is_binary(Path) ->
    null_merge(Rest, put_null(binary:split(Path, ~".", [global]), Merge));
null_merge(_Other, _Merge) ->
    error({invalid_argument, paths, not_a_list_of_binaries}).

put_null([Key], Merge) ->
    Merge#{Key => null};
put_null([Key | Rest], Merge) ->
    case Merge of
        #{Key := null} -> Merge;
        #{Key := Inner} -> Merge#{Key => put_null(Rest, Inner)};
        #{} -> Merge#{Key => put_null(Rest, #{})}
    end.
