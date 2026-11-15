-module(datastar_options_tests).

-include_lib("eunit/include/eunit.hrl").

patch_elements_refuses_a_line_break_in_an_option_test_() ->
    [
        ?_assertError(
            {invalid_option, Option, line_break},
            datastar:patch_elements(~"<p></p>", #{Option => Text})
        )
     || Option <- [selector, mode, namespace, id],
        Text <- datastar_test_sse:texts()
    ].

patch_signals_refuses_a_line_break_in_id_test_() ->
    [
        ?_assertError(
            {invalid_option, id, line_break},
            datastar:patch_signals(#{~"a" => 1}, #{id => Text})
        )
     || Text <- datastar_test_sse:texts()
    ].

execute_script_refuses_a_line_break_in_id_test_() ->
    [
        ?_assertError(
            {invalid_option, id, line_break},
            datastar:execute_script(~"x()", #{id => Text})
        )
     || Text <- datastar_test_sse:texts()
    ].

remove_elements_refuses_a_line_break_in_its_selector_test_() ->
    [
        [
            ?_assertError({invalid_option, selector, line_break}, datastar:remove_elements(Text)),
            ?_assertError(
                {invalid_option, id, line_break},
                datastar:remove_elements(~"#gone", #{id => Text})
            )
        ]
     || Text <- datastar_test_sse:texts()
    ].

remove_signals_refuses_a_line_break_in_id_test_() ->
    [
        ?_assertError(
            {invalid_option, id, line_break},
            datastar:remove_signals([~"a"], #{id => Text})
        )
     || Text <- datastar_test_sse:texts()
    ].

nul_is_refused_in_an_option_test_() ->
    [
        ?_assertError(
            {invalid_option, Option, nul},
            datastar:patch_elements(~"<p></p>", #{Option => Text})
        )
     || Option <- [selector, mode, namespace, id],
        Text <- [<<0>>, <<"a", 0>>, <<0, "a">>, <<"a", 0, "b">>]
    ].

retry_is_a_non_negative_integer_test_() ->
    [
        ?_assertError(
            {invalid_option, retry, not_a_non_negative_integer},
            Build(#{retry => Retry})
        )
     || Retry <- [-1, 1.5, ~"1", ~"1\r\n", ~"1\ndata: elements x", [$1, $\r]],
        Build <- [
            fun(Opts) -> datastar:patch_elements(~"<p></p>", Opts) end,
            fun(Opts) -> datastar:patch_signals(#{~"a" => 1}, Opts) end,
            fun(Opts) -> datastar:execute_script(~"x()", Opts) end,
            fun(Opts) -> datastar:remove_elements(~"#gone", Opts) end,
            fun(Opts) -> datastar:remove_signals([~"a"], Opts) end
        ]
    ].

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
