-module(datastar_tests).

-include_lib("eunit/include/eunit.hrl").

protocol_version_test() ->
    ?assertEqual(~"1.0", datastar:protocol_version()).

sse_headers_delegate_test() ->
    ?assertEqual(datastar_sse:headers(), datastar:sse_headers()).

facade_delegates_patch_elements_test() ->
    ?assertEqual(
        iolist_to_binary(datastar_sse:patch_elements(~"<p/>")),
        iolist_to_binary(datastar:patch_elements(~"<p/>"))
    ).

facade_delegates_read_signals_test() ->
    ?assertEqual({ok, #{~"a" => 1}}, datastar:read_signals(~"{\"a\":1}")).
