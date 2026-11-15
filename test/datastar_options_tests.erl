-module(datastar_options_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEXTS, 488).

patch_elements_refuses_a_line_break_in_an_option_test() ->
    Cases = [
        {Option, Text}
     || Option <- [selector, mode, namespace, id], Text <- datastar_test_sse:texts()
    ],
    ?assertEqual(4 * ?TEXTS, length(Cases)),
    ?assertEqual(
        [],
        [
            Case
         || {Option, Text} = Case <- Cases,
            raised(patch_elements, [~"<p></p>", #{Option => Text}]) =/=
                {invalid_option, Option, line_break}
        ]
    ).

every_builder_refuses_a_line_break_in_id_test() ->
    Cases = [
        {Function, Args ++ [#{id => Text}]}
     || {Function, Args} <- [
            {patch_signals, [#{~"a" => 1}]},
            {execute_script, [~"x()"]},
            {remove_elements, [~"#gone"]},
            {remove_signals, [[~"a"]]}
        ],
        Text <- datastar_test_sse:texts()
    ],
    ?assertEqual(4 * ?TEXTS, length(Cases)),
    ?assertEqual(
        [],
        [
            Case
         || {Function, Args} = Case <- Cases,
            raised(Function, Args) =/= {invalid_option, id, line_break}
        ]
    ).

remove_elements_refuses_a_line_break_in_its_selector_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            raised(remove_elements, [Text]) =/= {invalid_option, selector, line_break}
        ]
    ).

nul_is_refused_in_an_option_test() ->
    Cases = [
        {Option, Text}
     || Option <- [selector, mode, namespace, id],
        Text <- [<<0>>, <<"a", 0>>, <<0, "a">>, <<"a", 0, "b">>]
    ],
    ?assertEqual(16, length(Cases)),
    ?assertEqual(
        [],
        [
            Case
         || {Option, Text} = Case <- Cases,
            raised(patch_elements, [~"<p></p>", #{Option => Text}]) =/=
                {invalid_option, Option, nul}
        ]
    ).

retry_is_a_non_negative_integer_test() ->
    Cases = [
        {Function, Args ++ [#{retry => Retry}]}
     || Retry <- [-1, 1.5, ~"1", ~"1\r\n", ~"1\ndata: elements x", [$1, $\r]],
        {Function, Args} <- builders()
    ],
    ?assertEqual(30, length(Cases)),
    ?assertEqual(
        [],
        [
            Case
         || {Function, Args} = Case <- Cases,
            raised(Function, Args) =/= {invalid_option, retry, not_a_non_negative_integer}
        ]
    ).

single_line_options_arrive_as_given_test() ->
    Opts = #{
        selector => ~"#list > li.done, [data-x=\"a b\"]",
        mode => ~"after",
        namespace => ~"svg",
        id => ~" evt: 7 ",
        retry => 0
    },
    ?assertEqual(
        [
            #{
                type => ~"datastar-patch-elements",
                id => ~" evt: 7 ",
                retry => 0,
                fields => #{
                    ~"selector" => ~"#list > li.done, [data-x=\"a b\"]",
                    ~"mode" => ~"after",
                    ~"namespace" => ~"svg",
                    ~"elements" => ~"<p></p>"
                }
            }
        ],
        [
            Event#{fields => datastar_test_sse:fields(Data)}
         || #{data := Data} = Event0 <- datastar_test_sse:events(
                datastar:patch_elements(~"<p></p>", Opts)
            ),
            Event <- [maps:remove(data, Event0)]
        ]
    ).

option_given_as_iodata_is_checked_too_test() ->
    ?assertError(
        {invalid_option, selector, line_break},
        datastar:patch_elements(~"<p></p>", #{selector => [~"#a", [$\r], ~"b"]})
    ),
    ?assertMatch(
        {_, _},
        binary:match(
            iolist_to_binary(datastar:patch_elements(~"<p></p>", #{selector => [~"#a", ~" b"]})),
            ~"data: selector #a b\n"
        )
    ).

builders() ->
    [
        {patch_elements, [~"<p></p>"]},
        {patch_signals, [#{~"a" => 1}]},
        {execute_script, [~"x()"]},
        {remove_elements, [~"#gone"]},
        {remove_signals, [[~"a"]]}
    ].

raised(Function, Args) ->
    try apply(datastar, Function, Args) of
        _Event -> nothing
    catch
        error:Reason -> Reason
    end.
