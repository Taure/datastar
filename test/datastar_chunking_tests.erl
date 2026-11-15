-module(datastar_chunking_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ELEMENTS, ~"datastar-patch-elements").
-define(SIGNALS, ~"datastar-patch-signals").

crlf_split_across_iodata_chunks_is_one_line_break_test_() ->
    [
        ?_assertEqual(
            [{?ELEMENTS, #{~"elements" => ~"a\nb"}}],
            received(datastar:patch_elements(Chunks))
        )
     || Chunks <- [
            [~"a\r", ~"\nb"],
            [~"a", ~"\r", ~"\n", ~"b"],
            [[~"a\r"], [[~"\n"], ~"b"]],
            [~"a\r", $\n, ~"b"],
            [~"a\r", ~"", ~"\nb"],
            [~"a\r" | ~"\nb"]
        ]
    ].

pre_encoded_signals_split_at_a_chunk_boundary_test() ->
    ?assertEqual(
        [{?SIGNALS, #{~"signals" => ~"{\n\"a\":1}"}}],
        received(datastar:patch_signals([~"{\r", ~"\n\"a\":1}"]))
    ).

script_split_at_a_chunk_boundary_test() ->
    ?assertEqual(
        [
            {?ELEMENTS, #{
                ~"selector" => ~"body",
                ~"mode" => ~"append",
                ~"elements" => ~"<script data-effect=\"el.remove()\">a()\nb()</script>"
            }}
        ],
        received(datastar:execute_script([~"a()\r", ~"\nb()"]))
    ).

every_short_text_in_every_chunking_test() ->
    Cases = [
        {Text, Chunks}
     || Text <- words([~"a", ~"\r", ~"\n"], 6), Chunks <- chunkings(Text)
    ],
    ?assertEqual(27994, length(Cases)),
    ?assertEqual(
        [],
        [
            Chunks
         || {Text, Chunks} <- Cases,
            received(datastar:patch_elements(Chunks)) =/= expected(Text)
        ]
    ).

expected(~"") -> [];
expected(Text) -> [{?ELEMENTS, #{~"elements" => datastar_test_sse:as_received(Text)}}].

words(_Alphabet, 0) ->
    [~""];
words(Alphabet, Length) ->
    Shorter = words(Alphabet, Length - 1),
    Shorter ++
        [
            <<Letter/binary, Word/binary>>
         || Letter <- Alphabet, Word <- Shorter, byte_size(Word) =:= Length - 1
        ].

chunkings(~"") ->
    [[]];
chunkings(Text) ->
    [
        [binary:part(Text, 0, Cut) | Rest]
     || Cut <- lists:seq(1, byte_size(Text)),
        Rest <- chunkings(binary:part(Text, Cut, byte_size(Text) - Cut))
    ].

received(Stream) ->
    [
        {Type, datastar_test_sse:fields(Data)}
     || #{type := Type, data := Data} <- datastar_test_sse:events(Stream)
    ].
