-module(datastar_sse).
-moduledoc """
Builds iodata for Datastar SSE events, per the Datastar v1 SDK specification.

All functions are pure and return `iodata()` — compose them freely with
`cowboy_req:stream_body/3` or any other chunked-transfer sink. No IO, no
state, no framework dependency.

## Events

The Datastar v1 protocol defines two wire events:

- `datastar-patch-elements` — patch HTML into the DOM
- `datastar-patch-signals` — patch signals into the client-side store

`execute_script/1,2`, `remove_elements/1,2`, and `remove_signals/1,2` are
ergonomic sugar that compile down to these two events.
""".

-export([
    headers/0,
    patch_elements/1,
    patch_elements/2,
    patch_signals/1,
    patch_signals/2,
    execute_script/1,
    execute_script/2,
    remove_elements/1,
    remove_elements/2,
    remove_signals/1,
    remove_signals/2
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
    selector => binary(),
    mode => mode(),
    use_view_transition => boolean(),
    namespace => namespace(),
    id => binary(),
    retry => pos_integer()
}.

-type patch_signals_opts() :: #{
    only_if_missing => boolean(),
    id => binary(),
    retry => pos_integer()
}.

-type execute_script_opts() :: #{
    auto_remove => boolean(),
    attributes => [{binary(), binary()}],
    id => binary(),
    retry => pos_integer()
}.

-doc """
SSE response headers required by Datastar.

Returned as `[{binary(), binary()}]`, directly usable with
`cowboy_req:stream_reply/3`.
""".
-spec headers() -> [{binary(), binary()}].
headers() ->
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

HTML containing newlines is split into one `data: elements <line>` per line,
as required by the SSE framing rules.

Options (all optional):

- `selector` — CSS selector of target element. If absent, each top-level
  element in `Html` must carry an `id` attribute.
- `mode` — one of `outer` (default), `inner`, `replace`, `prepend`,
  `append`, `before`, `'after'`, `remove`. A binary is also accepted.
- `use_view_transition` — wrap the patch in a View Transition.
- `namespace` — `html` (default), `svg`, or `mathml`.
- `id`, `retry` — standard SSE fields.
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
Build a `datastar-patch-signals` event applying an RFC 7386 JSON Merge Patch
to the client signal store.

`Signals` may be a map (encoded with OTP's `json` module) or pre-encoded
JSON iodata.

Options:

- `only_if_missing` — do not overwrite signals that already exist.
- `id`, `retry` — standard SSE fields.
""".
-spec patch_signals(map() | iodata(), patch_signals_opts()) -> iodata().
patch_signals(Signals, Opts) when is_map(Signals) ->
    patch_signals(json:encode(Signals), Opts);
patch_signals(Json, Opts) ->
    [
        event_line(?EVT_PATCH_SIGNALS),
        sse_meta_lines(Opts),
        patch_signals_option_lines(Opts),
        signals_data_line(Json),
        $\n
    ].

-doc #{equiv => execute_script(Script, #{})}.
-spec execute_script(iodata()) -> iodata().
execute_script(Script) ->
    execute_script(Script, #{}).

-doc """
Append a `<script>` to `<body>` and let the browser execute it.

Compiled down to `patch_elements/2` with `selector => ~"body"` and
`mode => append`, as mandated by the Datastar SDK spec.

Options:

- `auto_remove` — if `true` (default), adds `data-effect="el.remove()"` so
  the script element removes itself after running.
- `attributes` — extra `[{Name, Value}]` attributes appended to the tag.
  When present, `type="application/javascript"` is also added.
- `id`, `retry` — standard SSE fields.
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

Accepts any `patch_elements_opts()` (other than `selector`/`mode`, which
are fixed by this operation).
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

Compiles a JSON Merge Patch where each leaf is `null` (RFC 7386 removal
semantics) and sends it as a `datastar-patch-signals` event.

    remove_signals([~"user.name", ~"cart.items"]).
""".
-spec remove_signals([binary()], patch_signals_opts()) -> iodata().
remove_signals(Paths, Opts) ->
    patch_signals(build_null_merge(Paths), Opts).

%% -- internal -----------------------------------------------------------------

event_line(Name) ->
    [~"event: ", Name, $\n].

sse_meta_lines(Opts) ->
    [id_line(maps:get(id, Opts, undefined)), retry_line(maps:get(retry, Opts, undefined))].

id_line(undefined) -> [];
id_line(Id) -> [~"id: ", Id, $\n].

retry_line(undefined) -> [];
retry_line(Retry) -> [~"retry: ", integer_to_binary(Retry), $\n].

patch_elements_option_lines(Opts) ->
    [
        selector_line(maps:get(selector, Opts, undefined)),
        mode_line(maps:get(mode, Opts, outer)),
        use_view_transition_line(maps:get(use_view_transition, Opts, false)),
        namespace_line(maps:get(namespace, Opts, html))
    ].

selector_line(undefined) -> [];
selector_line(Sel) -> [~"data: selector ", Sel, $\n].

mode_line(outer) -> [];
mode_line(Mode) when is_atom(Mode) -> [~"data: mode ", atom_to_binary(Mode, utf8), $\n];
mode_line(Mode) when is_binary(Mode) -> [~"data: mode ", Mode, $\n].

use_view_transition_line(false) -> [];
use_view_transition_line(true) -> ~"data: useViewTransition true\n".

namespace_line(html) -> [];
namespace_line(Ns) when is_atom(Ns) -> [~"data: namespace ", atom_to_binary(Ns, utf8), $\n];
namespace_line(Ns) when is_binary(Ns) -> [~"data: namespace ", Ns, $\n].

patch_signals_option_lines(Opts) ->
    case maps:get(only_if_missing, Opts, false) of
        true -> ~"data: onlyIfMissing true\n";
        false -> []
    end.

signals_data_line(Json) ->
    [~"data: signals ", Json, $\n].

elements_data_lines(Html) ->
    case iolist_to_binary(Html) of
        <<>> -> [];
        Bin -> [[~"data: elements ", Line, $\n] || Line <- binary:split(Bin, ~"\n", [global])]
    end.

build_script_element(Script, AutoRemove, Attrs) ->
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
    CustomAttrs = [[$\s, K, ~"=\"", V, ~"\""] || {K, V} <- Attrs],
    [~"<script", TypeAttr, AutoAttr, CustomAttrs, $>, Script, ~"</script>"].

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
    Inner =
        case maps:get(Key, Acc, #{}) of
            M when is_map(M) -> M;
            _ -> #{}
        end,
    Acc#{Key => put_null(Rest, Inner)}.
