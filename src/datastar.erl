-module(datastar).
-moduledoc """
Datastar SDK for Erlang — the first Erlang SDK for the
[Datastar](https://data-star.dev) hypermedia framework.

Builds `iodata()` for Datastar v1 SSE events. Zero runtime dependencies.
Framework-agnostic: pipe the output into any chunked HTTP response
(Cowboy `stream_body/3`, Mochiweb, inets, whatever).

## Quickstart

    %% 1. When handling a request that returns an SSE stream, send the headers:
    Headers = datastar:sse_headers(),

    %% 2. Build events and write them as chunks:
    Event1 = datastar:patch_elements(~"<div id=\"status\">ready</div>"),
    Event2 = datastar:patch_signals(#{count => 1}),

    %% 3. Read signals sent from the browser:
    {ok, #{~"count" := N}} = datastar:read_signals(Body).

See `datastar_sse` for event builders and `datastar_signals` for parsing.
""".

-export([
    sse_headers/0,
    patch_elements/1, patch_elements/2,
    patch_signals/1, patch_signals/2,
    execute_script/1, execute_script/2,
    remove_elements/1, remove_elements/2,
    remove_signals/1, remove_signals/2,
    read_signals/1,
    protocol_version/0
]).

-doc "Datastar protocol version this SDK targets.".
-spec protocol_version() -> binary().
protocol_version() -> ~"1.0".

-doc "See `datastar_sse:headers/0`.".
-spec sse_headers() -> [{binary(), binary()}].
sse_headers() -> datastar_sse:headers().

-doc "See `datastar_sse:patch_elements/1`.".
-spec patch_elements(iodata()) -> iodata().
patch_elements(Html) -> datastar_sse:patch_elements(Html).

-doc "See `datastar_sse:patch_elements/2`.".
-spec patch_elements(iodata(), datastar_sse:patch_elements_opts()) -> iodata().
patch_elements(Html, Opts) -> datastar_sse:patch_elements(Html, Opts).

-doc "See `datastar_sse:patch_signals/1`.".
-spec patch_signals(map() | iodata()) -> iodata().
patch_signals(Signals) -> datastar_sse:patch_signals(Signals).

-doc "See `datastar_sse:patch_signals/2`.".
-spec patch_signals(map() | iodata(), datastar_sse:patch_signals_opts()) -> iodata().
patch_signals(Signals, Opts) -> datastar_sse:patch_signals(Signals, Opts).

-doc "See `datastar_sse:execute_script/1`.".
-spec execute_script(iodata()) -> iodata().
execute_script(Script) -> datastar_sse:execute_script(Script).

-doc "See `datastar_sse:execute_script/2`.".
-spec execute_script(iodata(), datastar_sse:execute_script_opts()) -> iodata().
execute_script(Script, Opts) -> datastar_sse:execute_script(Script, Opts).

-doc "See `datastar_sse:remove_elements/1`.".
-spec remove_elements(binary()) -> iodata().
remove_elements(Selector) -> datastar_sse:remove_elements(Selector).

-doc "See `datastar_sse:remove_elements/2`.".
-spec remove_elements(binary(), datastar_sse:patch_elements_opts()) -> iodata().
remove_elements(Selector, Opts) -> datastar_sse:remove_elements(Selector, Opts).

-doc "See `datastar_sse:remove_signals/1`.".
-spec remove_signals([binary()]) -> iodata().
remove_signals(Paths) -> datastar_sse:remove_signals(Paths).

-doc "See `datastar_sse:remove_signals/2`.".
-spec remove_signals([binary()], datastar_sse:patch_signals_opts()) -> iodata().
remove_signals(Paths, Opts) -> datastar_sse:remove_signals(Paths, Opts).

-doc "See `datastar_signals:read/1`.".
-spec read_signals(iodata()) ->
    {ok, map()} | {error, {invalid_json, term()} | not_an_object}.
read_signals(Payload) -> datastar_signals:read(Payload).
