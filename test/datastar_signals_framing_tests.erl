-module(datastar_signals_framing_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SIGNALS, ~"datastar-patch-signals").

patch_signals_map_is_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [{?SIGNALS, #{Text => #{~"nested" => [Text, 1, true, null]}}}],
            decoded(datastar:patch_signals(#{Text => #{~"nested" => [Text, 1, true, null]}}))
        )
     || Text <- texts()
    ].

patch_signals_map_is_written_on_one_data_line_test_() ->
    [
        ?_assertMatch(
            [~"event: datastar-patch-signals", <<"data: signals ", _/binary>>, <<>>, <<>>],
            binary:split(
                iolist_to_binary(datastar:patch_signals(#{Text => Text})),
                [~"\r\n", ~"\r", ~"\n"],
                [global]
            )
        )
     || Text <- texts()
    ].

encoded_map_keeps_line_and_paragraph_separators_as_text_test() ->
    Separators = <<16#2028/utf8, 16#2029/utf8, 16#85/utf8, 16#7F>>,
    Out = iolist_to_binary(datastar:patch_signals(#{~"s" => Separators})),
    ?assertMatch({_, _}, binary:match(Out, Separators)),
    ?assertEqual([{?SIGNALS, #{~"s" => Separators}}], decoded(Out)).

encoded_map_escapes_every_control_character_test() ->
    Controls = <<<<Byte>> || Byte <- lists:seq(0, 31)>>,
    Out = iolist_to_binary(datastar:patch_signals(#{Controls => Controls})),
    ?assertEqual(
        [$\n, $\n, $\n],
        [Byte || <<Byte>> <= Out, Byte < 32]
    ),
    ?assertEqual([{?SIGNALS, #{Controls => Controls}}], decoded(Out)).

patch_signals_json_is_one_event_for_any_line_ending_between_tokens_test_() ->
    [
        ?_assertEqual(
            [{?SIGNALS, #{~"a" => [1, ~"b"]}}],
            decoded(
                datastar:patch_signals([
                    Break,
                    ~"{",
                    Break,
                    ~"\"a\":",
                    Break,
                    ~"[1,",
                    Break,
                    ~"\"b\"]",
                    Break,
                    ~"}",
                    Break
                ])
            )
        )
     || Break <- [~"\r", ~"\n", ~"\r\n", ~"\n\r", ~"\r\r\n", ~"\n\n", ~"\r\r", ~"\r\n\r\n"]
    ].

patch_signals_iodata_is_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [
                {?SIGNALS, #{
                    ~"onlyIfMissing" => ~"true",
                    ~"signals" => datastar_test_sse:as_received(Text)
                }}
            ],
            received(datastar:patch_signals(Text, #{only_if_missing => true}))
        )
     || Text <- datastar_test_sse:texts()
    ].

remove_signals_is_one_event_for_any_line_ending_test_() ->
    [
        ?_assertEqual(
            [{?SIGNALS, #{Text => null, ~"user" => #{Text => null}}}],
            decoded(datastar:remove_signals([Text, <<"user.", Text/binary>>]))
        )
     || Text <- texts()
    ].

texts() ->
    datastar_test_sse:texts() ++ [<<"a", 0, "b">>, <<0>>, <<"a", 16#2028/utf8, "b", 16#2029/utf8>>].

decoded(Stream) ->
    [
        {Type, json:decode(Signals)}
     || {Type, #{~"signals" := Signals} = Fields} <- received(Stream),
        map_size(Fields) =:= 1
    ].

received(Stream) ->
    [
        {Type, datastar_test_sse:fields(Data)}
     || #{type := Type, data := Data} <- datastar_test_sse:events(Stream)
    ].
