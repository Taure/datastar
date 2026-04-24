-module(datastar_signals).
-moduledoc """
Reads Datastar signals from an incoming request.

Datastar sends the current signal store back to the server on every action:

- `GET` requests carry it as a URL-encoded JSON string in the `datastar`
  query parameter.
- Other methods carry it as a JSON body.

Web frameworks (Cowboy, etc.) already URL-decode query parameters, so by
the time the value reaches this SDK it is the raw JSON binary. `read/1`
therefore works uniformly for both cases — hand it the JSON binary.
""".

-export([read/1]).

-doc """
Decode a JSON signal payload into a map.

Returns `{ok, Signals}` on success, `{error, Reason}` if the input is not
a valid JSON object.

    case datastar_signals:read(Body) of
        {ok, #{~"count" := N}} -> ...;
        {error, _} -> ...
    end.
""".
-spec read(iodata()) -> {ok, map()} | {error, {invalid_json, term()} | not_an_object}.
read(Payload) ->
    try json:decode(iolist_to_binary(Payload)) of
        Map when is_map(Map) -> {ok, Map};
        _ -> {error, not_an_object}
    catch
        error:Reason -> {error, {invalid_json, Reason}}
    end.
