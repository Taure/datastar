-module(datastar_script_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TEXTS, 488).

attribute_value_is_escaped_for_an_html_attribute_test() ->
    ?assertEqual(
        ~"<script type=\"application/javascript\" data-x=\"a&amp;b&quot;c&#39;d&lt;e&gt;f\">x()</script>",
        element(
            datastar:execute_script(~"x()", #{
                auto_remove => false, attributes => [{~"data-x", ~"a&b\"c'd<e>f"}]
            })
        )
    ).

attribute_value_given_as_iodata_is_escaped_test() ->
    ?assertEqual(
        ~"<script type=\"application/javascript\" nonce=\"a&quot;b\">x()</script>",
        element(
            datastar:execute_script(~"x()", #{
                auto_remove => false, attributes => [{[~"non", "ce"], [~"a", [$" | ~"b"]]}]
            })
        )
    ).

attribute_value_arrives_whole_for_any_line_ending_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            attribute_value(
                element(
                    datastar:execute_script(~"x()", #{
                        auto_remove => false, attributes => [{~"data-x", Text}]
                    })
                )
            ) =/= datastar_test_sse:as_received(Text)
        ]
    ).

plain_attribute_names_are_written_as_given_test() ->
    Names = [
        ~"nonce",
        ~"data-x",
        ~"data-on:click",
        ~"xlink:href",
        ~"x.y_z",
        ~"A1",
        <<"caf", 16#E9/utf8>>,
        ~"<",
        ~"&"
    ],
    ?assertEqual(
        [],
        [
            Name
         || Name <- Names,
            element(
                datastar:execute_script(~"x()", #{
                    auto_remove => false, attributes => [{Name, ~"v"}]
                })
            ) =/=
                <<"<script type=\"application/javascript\" ", Name/binary, "=\"v\">x()</script>">>
        ]
    ).

attribute_name_that_is_not_a_plain_name_is_refused_test() ->
    Names = [
        ~"",
        ~" ",
        ~"a b",
        ~"a\tb",
        ~"a\nb",
        ~"a\rb",
        ~"a\fb",
        ~"a\0b",
        ~"a\eb",
        ~"a\db",
        <<"a", 16#85/utf8, "b">>,
        <<"a", 16#9F/utf8>>,
        ~"a\"b",
        ~"a'b",
        ~"a>b",
        ~"a/b",
        ~"a=b",
        ~"x onload",
        ~"x=\"\" y",
        <<"a", 16#FF>>,
        <<16#C3>>
    ],
    ?assertEqual(
        [],
        [
            Name
         || Name <- Names,
            raised(~"x()", #{attributes => [{Name, ~"v"}]}) =/=
                {invalid_option, attributes, invalid_name}
        ]
    ).

attribute_name_with_a_line_break_is_refused_test() ->
    Texts = datastar_test_sse:texts(),
    ?assertEqual(?TEXTS, length(Texts)),
    ?assertEqual(
        [],
        [
            Text
         || Text <- Texts,
            raised(~"x()", #{attributes => [{Text, ~"v"}]}) =/=
                {invalid_option, attributes, invalid_name}
        ]
    ).

element(Event) ->
    [#{data := Data}] = datastar_test_sse:events(Event),
    #{~"elements" := Element} = datastar_test_sse:fields(Data),
    Element.

attribute_value(Element) ->
    Prefix = ~"<script type=\"application/javascript\" data-x=\"",
    Suffix = ~"\">x()</script>",
    Size = byte_size(Element) - byte_size(Prefix) - byte_size(Suffix),
    <<Prefix:(byte_size(Prefix))/binary, Escaped:Size/binary, Suffix/binary>> = Element,
    nomatch = binary:match(Escaped, [~"\"", ~"'", ~"<", ~">"]),
    Entities = [
        {~"&quot;", ~"\""},
        {~"&#39;", ~"'"},
        {~"&lt;", ~"<"},
        {~"&gt;", ~">"},
        {~"&amp;", ~"&"}
    ],
    unescaped(Escaped, Entities).

unescaped(Text, []) ->
    Text;
unescaped(Text, [{Entity, Character} | Entities]) ->
    unescaped(binary:replace(Text, Entity, Character, [global]), Entities).

raised(Script, Opts) ->
    try datastar:execute_script(Script, Opts) of
        _Event -> nothing
    catch
        error:Reason -> Reason
    end.
