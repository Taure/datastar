-module(datastar_signals_framing_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SIGNALS, ~"datastar-patch-signals").
-define(TEXTS, 488).
-define(TEXTS_FOR_A_MAP, 491).

patch_signals_map_is_one_event_for_any_line_ending_test() ->
    Texts = texts(),
    ?assertEqual(?TEXTS_FOR_A_MAP, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            Signals <- [#{Text => #{~"nested" => [Text, 1, true, null]}}],
            decoded(datastar:patch_signals(Signals)) =/= [{?SIGNALS, Signals}]
        ]
    ).

patch_signals_map_is_written_on_one_data_line_test() ->
    Texts = texts(),
    ?assertEqual(?TEXTS_FOR_A_MAP, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            not on_one_data_line(iolist_to_binary(datastar:patch_signals(#{Text => Text})))
        ]
    ).

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

patch_signals_json_is_one_event_for_any_line_ending_between_tokens_test() ->
    Breaks = [~"\r", ~"\n", ~"\r\n", ~"\n\r", ~"\r\r\n", ~"\n\n", ~"\r\r", ~"\r\n\r\n"],
    ?assertEqual(
        [],
        [
            Break
         || Break <- Breaks,
            Json <- [
                [
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
                ]
            ],
            Event <- [datastar:patch_signals(Json, #{only_if_missing => true})],
            decoded(datastar:patch_signals(Json)) =/= [{?SIGNALS, #{~"a" => [1, ~"b"]}}] orelse
                received(Event) =/=
                    [
                        {?SIGNALS, #{
                            ~"onlyIfMissing" => ~"true",
                            ~"signals" => datastar_test_sse:as_received(Json)
                        }}
                    ]
        ]
    ).

pre_encoded_signals_that_are_json_are_written_as_given_test() ->
    Values = [
        ~"{}",
        ~"{\"a\":1}",
        ~" {\"a\" : [1, 2.5e3, true, false, null, \"b\\n\"]} ",
        [~"{\"a\":", ~"1}"],
        ~"null",
        ~"[1]",
        ~"5",
        ~"\"text\"",
        <<"{\"a\":\"", 16#2028/utf8, "\"}">>
    ],
    ?assertEqual(
        [],
        [
            Json
         || Json <- Values,
            received(datastar:patch_signals(Json)) =/=
                [{?SIGNALS, #{~"signals" => iolist_to_binary(Json)}}]
        ]
    ).

pre_encoded_signals_that_are_not_json_are_refused_test() ->
    Values = [
        ~"",
        ~" ",
        ~"{bad",
        ~"{\"a\":1} x",
        ~"{\"a\":1}{\"b\":2}",
        ~"{\"a\":1},",
        ~"(1,{})",
        ~"{a:1}",
        ~"{'a':1}",
        ~"{\"a\":1,}",
        ~"{\"a\":\"x\ny\"}",
        ~"{\"a\":\"x\ry\"}",
        ~"{\"a\":\"x\0y\"}",
        <<"{\"a\":\"", 16#FF, "\"}">>,
        ~"{\"a\":\"\\ud800\"}",
        ~"01",
        ~"undefined",
        ~"NaN",
        ~"new Date()",
        [~"{\"a\":", ~"}"]
    ],
    ?assertEqual(
        [],
        [
            Json
         || Json <- Values,
            Opts <- [#{}, #{only_if_missing => true}],
            raised(Json, Opts) =/= {invalid_argument, signals, not_json}
        ]
    ).

pre_encoded_signals_from_the_line_ending_corpus_are_refused_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            raised(Text, #{only_if_missing => true}) =/= {invalid_argument, signals, not_json}
        ]
    ).

remove_signals_is_one_event_for_any_line_ending_test() ->
    Texts = texts(),
    ?assertEqual(?TEXTS_FOR_A_MAP, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            decoded(datastar:remove_signals([Text, <<"user.", Text/binary>>])) =/=
                [{?SIGNALS, #{Text => null, ~"user" => #{Text => null}}}]
        ]
    ).

texts() ->
    datastar_test_sse:texts() ++ [<<"a", 0, "b">>, <<0>>, <<"a", 16#2028/utf8, "b", 16#2029/utf8>>].

raised(Signals, Opts) ->
    try datastar:patch_signals(Signals, Opts) of
        _Event -> nothing
    catch
        error:Reason -> Reason
    end.

on_one_data_line(Out) ->
    case binary:split(Out, [~"\r\n", ~"\r", ~"\n"], [global]) of
        [~"event: datastar-patch-signals", <<"data: signals ", _/binary>>, <<>>, <<>>] -> true;
        _ -> false
    end.

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
