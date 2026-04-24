-module(datastar_signals_tests).

-include_lib("eunit/include/eunit.hrl").

read_valid_object_test() ->
    ?assertEqual(
        {ok, #{~"count" => 5, ~"name" => ~"jo"}},
        datastar_signals:read(~"{\"count\":5,\"name\":\"jo\"}")
    ).

read_empty_object_test() ->
    ?assertEqual({ok, #{}}, datastar_signals:read(~"{}")).

read_accepts_iodata_test() ->
    ?assertEqual({ok, #{~"a" => 1}}, datastar_signals:read([~"{\"a\":", ~"1}"])).

read_rejects_non_object_test() ->
    ?assertEqual({error, not_an_object}, datastar_signals:read(~"[1,2,3]")),
    ?assertEqual({error, not_an_object}, datastar_signals:read(~"42")),
    ?assertEqual({error, not_an_object}, datastar_signals:read(~"\"hi\"")).

read_rejects_invalid_json_test() ->
    ?assertMatch({error, {invalid_json, _}}, datastar_signals:read(~"{bad")).

read_nested_test() ->
    ?assertEqual(
        {ok, #{~"user" => #{~"name" => ~"jo", ~"age" => 42}}},
        datastar_signals:read(~"{\"user\":{\"name\":\"jo\",\"age\":42}}")
    ).
