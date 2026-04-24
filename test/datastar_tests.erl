-module(datastar_tests).

-include_lib("eunit/include/eunit.hrl").

%% -- headers / protocol -------------------------------------------------------

headers_test() ->
    ?assertEqual(
        [
            {~"content-type", ~"text/event-stream"},
            {~"cache-control", ~"no-cache"},
            {~"connection", ~"keep-alive"}
        ],
        datastar:sse_headers()
    ).

protocol_version_test() ->
    ?assertEqual(~"1.0", datastar:protocol_version()).

%% -- patch_elements -----------------------------------------------------------

patch_elements_minimal_test() ->
    ?assertEqual(
        iolist_to_binary([
            ~"event: datastar-patch-elements\n",
            ~"data: elements <div id=\"x\">hi</div>\n",
            ~"\n"
        ]),
        iolist_to_binary(datastar:patch_elements(~"<div id=\"x\">hi</div>"))
    ).

patch_elements_with_selector_and_mode_test() ->
    ?assertEqual(
        iolist_to_binary([
            ~"event: datastar-patch-elements\n",
            ~"data: selector #list\n",
            ~"data: mode append\n",
            ~"data: elements <li>a</li>\n",
            ~"data: elements <li>b</li>\n",
            ~"\n"
        ]),
        iolist_to_binary(
            datastar:patch_elements(
                ~"<li>a</li>\n<li>b</li>",
                #{selector => ~"#list", mode => append}
            )
        )
    ).

patch_elements_default_mode_omitted_test() ->
    Out = iolist_to_binary(datastar:patch_elements(~"<p/>", #{mode => outer})),
    ?assertEqual(nomatch, binary:match(Out, ~"data: mode")).

patch_elements_view_transition_and_namespace_test() ->
    Out = iolist_to_binary(
        datastar:patch_elements(
            ~"<circle/>",
            #{use_view_transition => true, namespace => svg}
        )
    ),
    ?assertMatch({_, _}, binary:match(Out, ~"data: useViewTransition true")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: namespace svg")).

patch_elements_accepts_binary_mode_test() ->
    Out = iolist_to_binary(datastar:patch_elements(~"<p/>", #{mode => ~"after"})),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode after")).

patch_elements_id_and_retry_test() ->
    Out = iolist_to_binary(datastar:patch_elements(~"<p/>", #{id => ~"evt-7", retry => 2500})),
    ?assertMatch({_, _}, binary:match(Out, ~"id: evt-7\n")),
    ?assertMatch({_, _}, binary:match(Out, ~"retry: 2500\n")).

%% -- patch_signals ------------------------------------------------------------

patch_signals_from_map_test() ->
    ?assertEqual(
        iolist_to_binary([
            ~"event: datastar-patch-signals\n",
            ~"data: signals {\"count\":5}\n",
            ~"\n"
        ]),
        iolist_to_binary(datastar:patch_signals(#{~"count" => 5}))
    ).

patch_signals_from_json_iodata_test() ->
    Out = iolist_to_binary(datastar:patch_signals(~"{\"a\":1}")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: signals {\"a\":1}")).

patch_signals_only_if_missing_test() ->
    Out = iolist_to_binary(datastar:patch_signals(#{x => 1}, #{only_if_missing => true})),
    ?assertMatch({_, _}, binary:match(Out, ~"data: onlyIfMissing true")).

patch_signals_only_if_missing_default_omitted_test() ->
    Out = iolist_to_binary(datastar:patch_signals(#{x => 1})),
    ?assertEqual(nomatch, binary:match(Out, ~"onlyIfMissing")).

%% -- execute_script -----------------------------------------------------------

execute_script_default_auto_removes_test() ->
    Out = iolist_to_binary(datastar:execute_script(~"alert(1)")),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-elements")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: selector body")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode append")),
    ?assertMatch({_, _}, binary:match(Out, ~"data-effect=\"el.remove()\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"alert(1)")).

execute_script_without_auto_remove_test() ->
    Out = iolist_to_binary(datastar:execute_script(~"x()", #{auto_remove => false})),
    ?assertEqual(nomatch, binary:match(Out, ~"data-effect")).

execute_script_with_custom_attributes_test() ->
    Out = iolist_to_binary(
        datastar:execute_script(
            ~"x()",
            #{attributes => [{~"id", ~"s1"}, {~"data-x", ~"y"}]}
        )
    ),
    ?assertMatch({_, _}, binary:match(Out, ~"type=\"application/javascript\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"id=\"s1\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"data-x=\"y\"")).

%% -- remove_elements ----------------------------------------------------------

remove_elements_test() ->
    Out = iolist_to_binary(datastar:remove_elements(~"#banner")),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-elements")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: selector #banner")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode remove")),
    ?assertEqual(nomatch, binary:match(Out, ~"data: elements")).

%% -- remove_signals -----------------------------------------------------------

remove_signals_flat_test() ->
    Out = iolist_to_binary(datastar:remove_signals([~"a", ~"b"])),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-signals")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"a\":null")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"b\":null")).

remove_signals_nested_test() ->
    Out = iolist_to_binary(datastar:remove_signals([~"user.name", ~"user.email"])),
    ?assertMatch({_, _}, binary:match(Out, ~"\"user\":")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"name\":null")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"email\":null")).

%% -- framing sanity -----------------------------------------------------------

every_event_ends_with_blank_line_test() ->
    Events = [
        datastar:patch_elements(~"<p/>"),
        datastar:patch_signals(#{x => 1}),
        datastar:execute_script(~"x()"),
        datastar:remove_elements(~"#x"),
        datastar:remove_signals([~"x"])
    ],
    [
        begin
            Bin = iolist_to_binary(E),
            Size = byte_size(Bin),
            ?assertEqual(~"\n\n", binary:part(Bin, Size - 2, 2))
        end
     || E <- Events
    ].

%% -- read_signals -------------------------------------------------------------

read_signals_valid_object_test() ->
    ?assertEqual(
        {ok, #{~"count" => 5, ~"name" => ~"jo"}},
        datastar:read_signals(~"{\"count\":5,\"name\":\"jo\"}")
    ).

read_signals_empty_object_test() ->
    ?assertEqual({ok, #{}}, datastar:read_signals(~"{}")).

read_signals_accepts_iodata_test() ->
    ?assertEqual({ok, #{~"a" => 1}}, datastar:read_signals([~"{\"a\":", ~"1}"])).

read_signals_rejects_non_object_test() ->
    ?assertEqual({error, not_an_object}, datastar:read_signals(~"[1,2,3]")),
    ?assertEqual({error, not_an_object}, datastar:read_signals(~"42")),
    ?assertEqual({error, not_an_object}, datastar:read_signals(~"\"hi\"")).

read_signals_rejects_invalid_json_test() ->
    ?assertMatch({error, {invalid_json, _}}, datastar:read_signals(~"{bad")).

read_signals_nested_test() ->
    ?assertEqual(
        {ok, #{~"user" => #{~"name" => ~"jo", ~"age" => 42}}},
        datastar:read_signals(~"{\"user\":{\"name\":\"jo\",\"age\":42}}")
    ).
