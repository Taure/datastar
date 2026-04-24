-module(datastar_sse_tests).

-include_lib("eunit/include/eunit.hrl").

-define(render(X), iolist_to_binary(X)).
-define(join(Lines), iolist_to_binary(Lines)).

%% -- headers ------------------------------------------------------------------

headers_test() ->
    ?assertEqual(
        [
            {~"content-type", ~"text/event-stream"},
            {~"cache-control", ~"no-cache"},
            {~"connection", ~"keep-alive"}
        ],
        datastar_sse:headers()
    ).

%% -- patch_elements -----------------------------------------------------------

patch_elements_minimal_test() ->
    ?assertEqual(
        ?join([
            ~"event: datastar-patch-elements\n",
            ~"data: elements <div id=\"x\">hi</div>\n",
            ~"\n"
        ]),
        ?render(datastar_sse:patch_elements(~"<div id=\"x\">hi</div>"))
    ).

patch_elements_with_selector_and_mode_test() ->
    ?assertEqual(
        ?join([
            ~"event: datastar-patch-elements\n",
            ~"data: selector #list\n",
            ~"data: mode append\n",
            ~"data: elements <li>a</li>\n",
            ~"data: elements <li>b</li>\n",
            ~"\n"
        ]),
        ?render(
            datastar_sse:patch_elements(
                ~"<li>a</li>\n<li>b</li>",
                #{selector => ~"#list", mode => append}
            )
        )
    ).

patch_elements_default_mode_omitted_test() ->
    %% outer is the default and must not appear on the wire
    Out = ?render(datastar_sse:patch_elements(~"<p/>", #{mode => outer})),
    ?assertEqual(nomatch, binary:match(Out, ~"data: mode")).

patch_elements_view_transition_and_namespace_test() ->
    Out = ?render(
        datastar_sse:patch_elements(
            ~"<circle/>",
            #{use_view_transition => true, namespace => svg}
        )
    ),
    ?assertMatch({_, _}, binary:match(Out, ~"data: useViewTransition true")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: namespace svg")).

patch_elements_accepts_binary_mode_test() ->
    Out = ?render(datastar_sse:patch_elements(~"<p/>", #{mode => ~"after"})),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode after")).

patch_elements_id_and_retry_test() ->
    Out = ?render(datastar_sse:patch_elements(~"<p/>", #{id => ~"evt-7", retry => 2500})),
    ?assertMatch({_, _}, binary:match(Out, ~"id: evt-7\n")),
    ?assertMatch({_, _}, binary:match(Out, ~"retry: 2500\n")).

%% -- patch_signals ------------------------------------------------------------

patch_signals_from_map_test() ->
    Out = ?render(datastar_sse:patch_signals(#{~"count" => 5})),
    ?assertEqual(
        ?join([
            ~"event: datastar-patch-signals\n",
            ~"data: signals {\"count\":5}\n",
            ~"\n"
        ]),
        Out
    ).

patch_signals_from_json_iodata_test() ->
    Out = ?render(datastar_sse:patch_signals(~"{\"a\":1}")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: signals {\"a\":1}")).

patch_signals_only_if_missing_test() ->
    Out = ?render(datastar_sse:patch_signals(#{x => 1}, #{only_if_missing => true})),
    ?assertMatch({_, _}, binary:match(Out, ~"data: onlyIfMissing true")).

patch_signals_only_if_missing_default_omitted_test() ->
    Out = ?render(datastar_sse:patch_signals(#{x => 1})),
    ?assertEqual(nomatch, binary:match(Out, ~"onlyIfMissing")).

%% -- execute_script -----------------------------------------------------------

execute_script_default_auto_removes_test() ->
    Out = ?render(datastar_sse:execute_script(~"alert(1)")),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-elements")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: selector body")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode append")),
    ?assertMatch({_, _}, binary:match(Out, ~"data-effect=\"el.remove()\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"alert(1)")).

execute_script_without_auto_remove_test() ->
    Out = ?render(datastar_sse:execute_script(~"x()", #{auto_remove => false})),
    ?assertEqual(nomatch, binary:match(Out, ~"data-effect")).

execute_script_with_custom_attributes_test() ->
    Out = ?render(
        datastar_sse:execute_script(
            ~"x()",
            #{attributes => [{~"id", ~"s1"}, {~"data-x", ~"y"}]}
        )
    ),
    ?assertMatch({_, _}, binary:match(Out, ~"type=\"application/javascript\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"id=\"s1\"")),
    ?assertMatch({_, _}, binary:match(Out, ~"data-x=\"y\"")).

%% -- remove_elements ----------------------------------------------------------

remove_elements_test() ->
    Out = ?render(datastar_sse:remove_elements(~"#banner")),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-elements")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: selector #banner")),
    ?assertMatch({_, _}, binary:match(Out, ~"data: mode remove")),
    ?assertEqual(nomatch, binary:match(Out, ~"data: elements")).

%% -- remove_signals -----------------------------------------------------------

remove_signals_flat_test() ->
    Out = ?render(datastar_sse:remove_signals([~"a", ~"b"])),
    ?assertMatch({_, _}, binary:match(Out, ~"event: datastar-patch-signals")),
    %% JSON key order is not guaranteed, so we check both keys are null.
    ?assertMatch({_, _}, binary:match(Out, ~"\"a\":null")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"b\":null")).

remove_signals_nested_test() ->
    Out = ?render(datastar_sse:remove_signals([~"user.name", ~"user.email"])),
    ?assertMatch({_, _}, binary:match(Out, ~"\"user\":")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"name\":null")),
    ?assertMatch({_, _}, binary:match(Out, ~"\"email\":null")).

%% -- framing sanity -----------------------------------------------------------

every_event_ends_with_blank_line_test() ->
    Events = [
        datastar_sse:patch_elements(~"<p/>"),
        datastar_sse:patch_signals(#{x => 1}),
        datastar_sse:execute_script(~"x()"),
        datastar_sse:remove_elements(~"#x"),
        datastar_sse:remove_signals([~"x"])
    ],
    [
        ?assert(binary:longest_common_suffix([iolist_to_binary(E), ~"\n\n"]) >= 2)
     || E <- Events
    ].
