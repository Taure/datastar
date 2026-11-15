-module(datastar_unchanged_output_tests).

-include_lib("eunit/include/eunit.hrl").

elements_without_a_carriage_return_are_written_as_before_test() ->
    Cases = [{Html, Opts} || Html <- texts_without_a_carriage_return(), Opts <- elements_options()],
    ?assertEqual(127 * 13, length(Cases)),
    ?assertEqual(
        [],
        [
            Case
         || {Html, Opts} = Case <- Cases,
            iolist_to_binary(datastar:patch_elements(Html, Opts)) =/=
                datastar_test_model:unchanged_elements(Html, Opts)
        ]
    ).

scripts_without_a_carriage_return_are_written_as_before_test() ->
    Texts = texts_without_a_carriage_return(),
    ?assertEqual(
        [],
        [
            Script
         || Script <- Texts,
            {Opts, Open} <- [
                {#{}, ~"<script data-effect=\"el.remove()\">"},
                {#{auto_remove => false}, ~"<script>"},
                {
                    #{attributes => [{~"nonce", ~"n0"}, {~"data-x", ~"a b"}]},
                    ~"<script type=\"application/javascript\" data-effect=\"el.remove()\" nonce=\"n0\" data-x=\"a b\">"
                }
            ],
            iolist_to_binary(datastar:execute_script(Script, Opts#{id => ~"7"})) =/=
                datastar_test_model:unchanged_elements(
                    <<Open/binary, Script/binary, "</script>">>,
                    #{selector => ~"body", mode => append, id => ~"7"}
                )
        ]
    ).

removals_are_written_as_before_test() ->
    ?assertEqual(
        [],
        [
            Opts
         || Opts <- elements_options(),
            iolist_to_binary(datastar:remove_elements(~"#gone, .old", Opts)) =/=
                datastar_test_model:unchanged_elements(
                    ~"", Opts#{selector => ~"#gone, .old", mode => remove}
                )
        ]
    ).

signals_are_written_as_before_test() ->
    Maps = [
        #{},
        #{~"count" => 5},
        #{~"text" => ~"a\nb", ~"user" => #{~"name" => <<"J", 16#F8/utf8, "rn">>, ~"tags" => []}},
        #{count => 1.5, open => false, none => null}
    ],
    ?assertEqual(
        [],
        [
            {Map, Opts}
         || Map <- Maps,
            Opts <- signals_options(),
            Json <- [iolist_to_binary(json:encode(Map))],
            iolist_to_binary(datastar:patch_signals(Map, Opts)) =/=
                datastar_test_model:unchanged_signals(Json, Opts) orelse
                iolist_to_binary(datastar:patch_signals(Json, Opts)) =/=
                    datastar_test_model:unchanged_signals(Json, Opts)
        ]
    ).

signal_removals_are_written_as_before_test() ->
    ?assertEqual(
        [],
        [
            Opts
         || Opts <- signals_options(),
            iolist_to_binary(datastar:remove_signals([~"user.name", ~"cart"], Opts)) =/=
                datastar_test_model:unchanged_signals(
                    iolist_to_binary(
                        json:encode(#{~"user" => #{~"name" => null}, ~"cart" => null})
                    ),
                    Opts
                )
        ]
    ).

texts_without_a_carriage_return() ->
    [
        ~"",
        ~"<p>one line</p>",
        ~"<ul>\n  <li>a</li>\n  <li>b</li>\n</ul>\n",
        <<"<p>", 16#2028/utf8, 16#2029/utf8, 16#85/utf8, 0, 16#FF, "</p>">>,
        binary:copy(~"<tr><td>row</td></tr>\n", 2800)
        | [Text || Text <- datastar_test_sse:texts(), binary:match(Text, ~"\r") =:= nomatch]
    ].

elements_options() ->
    [
        #{},
        #{selector => ~"#list"},
        #{selector => ~"#list > li.done, [data-x=\"a b\"]", mode => append},
        #{mode => outer},
        #{mode => ~"outer"},
        #{mode => 'after', namespace => html},
        #{mode => ~"inner", namespace => ~"html"},
        #{namespace => mathml, use_view_transition => false},
        #{namespace => ~"svg", use_view_transition => true},
        #{id => ~"evt-7"},
        #{retry => 0},
        #{id => ~"", retry => 2500},
        #{
            selector => ~"#list",
            mode => prepend,
            namespace => svg,
            use_view_transition => true,
            id => ~" evt: 7 ",
            retry => 2147483647
        }
    ].

signals_options() ->
    [
        #{},
        #{only_if_missing => true},
        #{only_if_missing => false},
        #{id => ~"evt-7", retry => 2500},
        #{only_if_missing => true, id => ~"7", retry => 0}
    ].
