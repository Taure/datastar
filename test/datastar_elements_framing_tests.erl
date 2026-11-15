-module(datastar_elements_framing_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ELEMENTS, ~"datastar-patch-elements").
-define(TEXTS, 488).

patch_elements_is_one_event_for_any_line_ending_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            received(datastar:patch_elements(Text)) =/=
                [{?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}}]
        ]
    ).

patch_elements_keeps_its_options_for_any_line_ending_test() ->
    Opts = #{
        selector => ~"#list",
        mode => append,
        namespace => svg,
        use_view_transition => true,
        id => ~"evt-7",
        retry => 2500
    },
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            described(datastar:patch_elements(Text, Opts)) =/=
                [
                    #{
                        type => ?ELEMENTS,
                        id => ~"evt-7",
                        retry => 2500,
                        fields => #{
                            ~"selector" => ~"#list",
                            ~"mode" => ~"append",
                            ~"namespace" => ~"svg",
                            ~"useViewTransition" => ~"true",
                            ~"elements" => datastar_test_sse:as_received(Text)
                        }
                    }
                ]
        ]
    ).

execute_script_is_one_event_for_any_line_ending_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            received(datastar:execute_script(Text)) =/=
                [
                    {?ELEMENTS, #{
                        ~"selector" => ~"body",
                        ~"mode" => ~"append",
                        ~"elements" => datastar_test_sse:as_received([
                            ~"<script data-effect=\"el.remove()\">", Text, ~"</script>"
                        ])
                    }}
                ]
        ]
    ).

crlf_is_one_line_break_test() ->
    ?assertEqual(
        ~"event: datastar-patch-elements\ndata: elements a\ndata: elements b\n\n",
        iolist_to_binary(datastar:patch_elements(~"a\r\nb"))
    ).

lone_cr_is_a_line_break_test() ->
    ?assertEqual(
        ~"event: datastar-patch-elements\ndata: elements a\ndata: elements b\n\n",
        iolist_to_binary(datastar:patch_elements(~"a\rb"))
    ).

nul_in_elements_is_passed_through_test() ->
    ?assertEqual(
        [{?ELEMENTS, #{~"elements" => <<"a", 0, "b">>}}],
        received(datastar:patch_elements(<<"a", 0, "b">>))
    ).

events_in_one_stream_stay_separate_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            received([
                datastar:patch_elements(Text),
                datastar:remove_elements(~"#gone"),
                datastar:patch_elements(Text)
            ]) =/=
                [
                    {?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}},
                    {?ELEMENTS, #{~"selector" => ~"#gone", ~"mode" => ~"remove"}},
                    {?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}}
                ]
        ]
    ).

received(Stream) ->
    [
        {Type, datastar_test_sse:fields(Data)}
     || #{type := Type, data := Data} <- datastar_test_sse:events(Stream)
    ].

described(Stream) ->
    [
        #{type => Type, id => Id, retry => Retry, fields => datastar_test_sse:fields(Data)}
     || #{type := Type, id := Id, retry := Retry, data := Data} <-
            datastar_test_sse:events(Stream)
    ].
