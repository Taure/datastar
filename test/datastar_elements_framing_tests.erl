-module(datastar_elements_framing_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ELEMENTS, ~"datastar-patch-elements").

patch_elements_is_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [{?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}}],
            received(datastar:patch_elements(Text))
        )
     || Text <- datastar_test_sse:texts()
    ].

patch_elements_keeps_its_options_for_any_line_ending_test_() ->
    Opts = #{
        selector => ~"#list",
        mode => append,
        namespace => svg,
        use_view_transition => true,
        id => ~"evt-7",
        retry => 2500
    },
    [
        ?_assertEqual(
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
            ],
            [
                #{type => Type, id => Id, retry => Retry, fields => datastar_test_sse:fields(Data)}
             || #{type := Type, id := Id, retry := Retry, data := Data} <-
                    datastar_test_sse:events(datastar:patch_elements(Text, Opts))
            ]
        )
     || Text <- datastar_test_sse:texts()
    ].

execute_script_is_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [
                {?ELEMENTS, #{
                    ~"selector" => ~"body",
                    ~"mode" => ~"append",
                    ~"elements" => datastar_test_sse:as_received([
                        ~"<script data-effect=\"el.remove()\">", Text, ~"</script>"
                    ])
                }}
            ],
            received(datastar:execute_script(Text))
        )
     || Text <- datastar_test_sse:texts()
    ].

execute_script_attributes_are_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [
                {?ELEMENTS, #{
                    ~"selector" => ~"body",
                    ~"mode" => ~"append",
                    ~"elements" => datastar_test_sse:as_received([
                        ~"<script type=\"application/javascript\" ",
                        Text,
                        ~"=\"",
                        Text,
                        ~"\">x()</script>"
                    ])
                }}
            ],
            received(
                datastar:execute_script(~"x()", #{
                    auto_remove => false, attributes => [{Text, Text}]
                })
            )
        )
     || Text <- datastar_test_sse:texts()
    ].

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

events_in_one_stream_stay_separate_test_() ->
    [
        ?_assertEqual(
            [
                {?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}},
                {?ELEMENTS, #{~"selector" => ~"#gone", ~"mode" => ~"remove"}},
                {?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}}
            ],
            received([
                datastar:patch_elements(Text),
                datastar:remove_elements(~"#gone"),
                datastar:patch_elements(Text)
            ])
        )
     || Text <- datastar_test_sse:texts()
    ].

received(Stream) ->
    [
        {Type, datastar_test_sse:fields(Data)}
     || #{type := Type, data := Data} <- datastar_test_sse:events(Stream)
    ].
