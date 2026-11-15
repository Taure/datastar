-module(datastar_test_model).

%% What a call to a builder is meant to produce, worked out from the call
%% alone: the events a client reads, or the errors the call may raise.
%% Also random calls to hold against it, and what the builders wrote before
%% carriage returns were framed, for input they still accept.

-export([
    calls/1,
    built/1,
    expected/1,
    observed/1,
    agree/2,
    stray_lines/1,
    unchanged/1,
    unchanged_elements/2,
    unchanged_signals/2
]).

-define(ELEMENTS, ~"datastar-patch-elements").
-define(SIGNALS, ~"datastar-patch-signals").
-define(MAX_RETRY, 2147483647).
-define(MODES, [outer, inner, replace, prepend, append, before, 'after', remove]).
-define(NAMESPACES, [html, svg, mathml]).
-define(ELEMENTS_OPTIONS, [selector, mode, use_view_transition, namespace, id, retry]).
-define(SIGNALS_OPTIONS, [only_if_missing, id, retry]).
-define(SCRIPT_OPTIONS, [auto_remove, attributes, id, retry]).

%% -- random calls -------------------------------------------------------------

calls(Index) ->
    _ = rand:seed(exsss, {Index, 7919, 104729}),
    [
        {patch_elements, [shaped(text()), options(?ELEMENTS_OPTIONS)]},
        {patch_signals, [signals(), options(?SIGNALS_OPTIONS)]},
        {patch_signals, [shaped(json_text()), options(?SIGNALS_OPTIONS)]},
        {execute_script, [shaped(text()), options(?SCRIPT_OPTIONS)]},
        {remove_elements, [shaped(selector()), options(?ELEMENTS_OPTIONS)]},
        {remove_signals, [paths(), options(?SIGNALS_OPTIONS)]}
    ].

options(Known) ->
    Opts = #{Option => option(Option) || Option <- Known, chance(35)},
    case chance(3) of
        true -> Opts#{one_of([selecter, onlyIfMissing, ~"id", 7]) => text()};
        false -> Opts
    end.

option(selector) ->
    shaped(selector());
option(mode) ->
    one_of(
        ?MODES ++ [atom_to_binary(Mode) || Mode <- ?MODES] ++ [bogus, ~"bogus", "inner", text()]
    );
option(namespace) ->
    one_of(
        ?NAMESPACES ++ [atom_to_binary(Name) || Name <- ?NAMESPACES] ++ [bogus, ~"x", "svg", text()]
    );
option(id) ->
    case chance(70) of
        true -> shaped(one_of([~"evt-7", ~"", ~" a: b ", ~"0", ~"~!@#$%^&*()"]));
        false -> shaped(text())
    end;
option(retry) ->
    one_of([0, 1, 2500, ?MAX_RETRY, ?MAX_RETRY + 1, 1 bsl 64, -1, 1.5, ~"1"]);
option(attributes) ->
    [{attribute_name(), shaped(text())} || _ <- lists:seq(1, rand:uniform(3) - 1)];
option(_Flag) ->
    one_of([true, false, true, false, true, false, ~"true", 1]).

attribute_name() ->
    case chance(85) of
        true -> one_of([~"nonce", ~"data-x", ~"data-on:click", <<"caf", 16#E9/utf8>>, "id"]);
        false -> one_of([~"", ~"a b", ~"a=b", ~"x\">", ~"a/", <<16#85/utf8>>, text()])
    end.

selector() ->
    case chance(70) of
        true -> one_of([~"#list", ~"#a > .b, [data-x=\"y z\"]", ~"body", ~""]);
        false -> text()
    end.

text() ->
    iolist_to_binary([piece() || _ <- lists:seq(1, rand:uniform(6) - 1)]).

piece() ->
    case chance(40) of
        true ->
            one_of([~"\r", ~"\n", ~"\r\n", ~"\n\r"]);
        false ->
            one_of([
                ~"\0",
                <<16#2028/utf8>>,
                <<16#2029/utf8>>,
                <<16#85/utf8>>,
                <<16#85>>,
                ~"\v",
                ~"\f",
                <<16#FEFF/utf8>>,
                ~"\d",
                <<16#FF>>,
                <<16#C0>>,
                <<16#E2, 16#80>>,
                <<16#F0, 16#9F>>,
                ~" ",
                ~":",
                ~"a",
                ~"<p id=\"x\">text</p>",
                ~"event: datastar-patch-signals",
                ~"data: signals {\"x\":1}",
                ~"data: selector #x",
                ~"data: mode outer",
                ~"data: elements <i>",
                ~"id: 9",
                ~"retry: 1",
                ~"</script>",
                ~"</SCRIPT",
                ~"&\"'<>",
                <<(rand:uniform(256) - 1)>>
            ])
    end.

shaped(Text) ->
    case rand:uniform(4) of
        1 -> Text;
        2 -> binary_to_list(Text);
        3 -> chunks(Text);
        4 -> [[], [chunks(Text)], ~""]
    end.

chunks(~"") ->
    [];
chunks(Text) ->
    Cut = rand:uniform(byte_size(Text)),
    [binary:part(Text, 0, Cut) | chunks(binary:part(Text, Cut, byte_size(Text) - Cut))].

signals() ->
    #{json_string() => json_value(2) || _ <- lists:seq(1, rand:uniform(4) - 1)}.

json_value(Depth) ->
    case
        rand:uniform(
            case Depth of
                0 -> 7;
                _ -> 9
            end
        )
    of
        1 -> json_string();
        2 -> rand:uniform(2000001) - 1000001;
        3 -> 1.5;
        4 -> true;
        5 -> false;
        6 -> null;
        7 -> one_of([json_string(), json_string(), json_string(), <<"a", 16#FF>>]);
        8 -> [json_value(Depth - 1) || _ <- lists:seq(1, rand:uniform(3) - 1)];
        9 -> #{json_string() => json_value(Depth - 1)}
    end.

json_string() ->
    iolist_to_binary([
        one_of([
            ~"\r",
            ~"\n",
            ~"\r\n",
            ~"\0",
            ~"\"",
            ~"\x{5C}",
            ~"a",
            ~"data: signals {}",
            ~"</script>",
            <<16#2028/utf8>>,
            <<16#E9/utf8>>,
            <<16#1F600/utf8>>
        ])
     || _ <- lists:seq(1, rand:uniform(4) - 1)
    ]).

json_text() ->
    case chance(75) of
        true -> iolist_to_binary([gap(), spaced(json_without_invalid_text(json_value(2))), gap()]);
        false -> text()
    end.

json_without_invalid_text(Value) when is_binary(Value) ->
    case valid_utf8(Value) of
        true -> Value;
        false -> ~"a"
    end;
json_without_invalid_text(Value) when is_list(Value) ->
    [json_without_invalid_text(Item) || Item <- Value];
json_without_invalid_text(Value) when is_map(Value) ->
    #{Key => json_without_invalid_text(Item) || Key := Item <- Value};
json_without_invalid_text(Value) ->
    Value.

spaced(Value) when is_map(Value) ->
    Members = [
        [json:encode(Key), gap(), ~":", gap(), spaced(Member)]
     || Key := Member <- Value
    ],
    [~"{", gap(), lists:join([gap(), ~",", gap()], Members), gap(), ~"}"];
spaced(Value) when is_list(Value) ->
    Items = [spaced(Item) || Item <- Value],
    [~"[", gap(), lists:join([gap(), ~",", gap()], Items), gap(), ~"]"];
spaced(Value) ->
    json:encode(Value).

gap() ->
    one_of([~"", ~"", ~" ", ~"\n", ~"\r\n", ~"\r", ~"\t", ~"\n  ", ~"\r\r\n"]).

paths() ->
    [
        dotted([path_part() || _ <- lists:seq(1, rand:uniform(3))])
     || _ <- lists:seq(1, rand:uniform(4) - 1)
    ].

dotted([First | Rest]) ->
    iolist_to_binary([First | [[$., Part] || Part <- Rest]]).

path_part() ->
    one_of([~"a", ~"b", ~"user", ~"", ~"a\rb", ~"a\nb", ~"\"", <<16#2028/utf8>>, <<"x", 16#FF>>]).

one_of(Items) ->
    lists:nth(rand:uniform(length(Items)), Items).

chance(Percent) ->
    rand:uniform(100) =< Percent.

%% -- what a call is meant to produce ------------------------------------------

expected({Function, [Argument, Opts]}) ->
    case refusals(Function, Argument, Opts) of
        [] -> {events, events(Function, Argument, Opts)};
        Refusals -> {raises, lists:usort(Refusals)}
    end.

refusals(patch_elements, _Html, Opts) ->
    option_refusals(?ELEMENTS_OPTIONS, Opts);
refusals(patch_signals, Signals, Opts) when is_map(Signals) ->
    [{invalid_argument, signals, not_encodable} || not encodable(Signals)] ++
        option_refusals(?SIGNALS_OPTIONS, Opts);
refusals(patch_signals, Json, Opts) ->
    [{invalid_argument, signals, not_json} || not is_json(flat(Json))] ++
        option_refusals(?SIGNALS_OPTIONS, Opts);
refusals(execute_script, Script, Opts) ->
    Lowercase = <<<<(ascii_lowercase(Byte))>> || <<Byte>> <= flat(Script)>>,
    [
        {invalid_argument, script, closing_tag}
     || binary:match(Lowercase, ~"</script") =/= nomatch
    ] ++ option_refusals(?SCRIPT_OPTIONS, Opts);
refusals(remove_elements, Selector, Opts) ->
    option_refusals(?ELEMENTS_OPTIONS, Opts#{selector => Selector, mode => remove});
refusals(remove_signals, Paths, Opts) ->
    [{invalid_argument, paths, not_encodable} || not encodable(removed(Paths))] ++
        option_refusals(?SIGNALS_OPTIONS, Opts).

option_refusals(Known, Opts) ->
    lists:append([option_refusal(Known, Option, Value) || Option := Value <- Opts]).

option_refusal(Known, Option, Value) ->
    case lists:member(Option, Known) of
        true -> value_refusal(Option, Value);
        false when is_atom(Option) -> [{invalid_option, Option, unknown_option}];
        false -> [{invalid_option, options, unknown_option}]
    end.

value_refusal(selector, Selector) ->
    case [Byte || <<Byte>> <= flat(Selector), lists:member(Byte, [$\r, $\n, 0])] of
        [] -> [];
        [0 | _] -> [{invalid_option, selector, nul}];
        [_ | _] -> [{invalid_option, selector, line_break}]
    end;
value_refusal(id, Id) ->
    case [Byte || <<Byte>> <= flat(Id), Byte < 16#20 orelse Byte > 16#7E] of
        [] -> [];
        [0 | _] -> [{invalid_option, id, nul}];
        [Byte | _] when Byte =:= $\r; Byte =:= $\n -> [{invalid_option, id, line_break}];
        [_ | _] -> [{invalid_option, id, not_printable_ascii}]
    end;
value_refusal(mode, Mode) ->
    [{invalid_option, mode, unknown_mode} || not named(Mode, ?MODES)];
value_refusal(namespace, Namespace) ->
    [{invalid_option, namespace, unknown_namespace} || not named(Namespace, ?NAMESPACES)];
value_refusal(retry, Retry) when is_integer(Retry), Retry > ?MAX_RETRY ->
    [{invalid_option, retry, too_large}];
value_refusal(retry, Retry) ->
    [
        {invalid_option, retry, not_a_non_negative_integer}
     || not (is_integer(Retry) andalso Retry >= 0)
    ];
value_refusal(attributes, Attributes) ->
    [
        {invalid_option, attributes, invalid_name}
     || {Name, _Value} <- Attributes, not plain_attribute_name(flat(Name))
    ];
value_refusal(Flag, Value) ->
    [{invalid_option, Flag, not_a_boolean} || not is_boolean(Value)].

named(Name, Names) when is_atom(Name) -> lists:member(Name, Names);
named(Name, Names) when is_binary(Name) -> lists:member(Name, [atom_to_binary(N) || N <- Names]);
named(_Name, _Names) -> false.

plain_attribute_name(Name) ->
    case unicode:characters_to_list(Name, utf8) of
        [_ | _] = Characters ->
            [] =:=
                [
                    Character
                 || Character <- Characters,
                    Character =< 16#20 orelse
                        (Character >= 16#7F andalso Character =< 16#9F) orelse
                        lists:member(Character, "\"'>/=")
                ];
        _EmptyOrNotUtf8 ->
            false
    end.

encodable(Value) when is_binary(Value) -> valid_utf8(Value);
encodable(Value) when is_list(Value) -> lists:all(fun encodable/1, Value);
encodable(Value) when is_map(Value) ->
    lists:all(fun encodable/1, maps:keys(Value) ++ maps:values(Value));
encodable(_Value) ->
    true.

valid_utf8(Text) ->
    unicode:characters_to_binary(Text, utf8, utf8) =:= Text.

is_json(Text) ->
    try json:decode(Text) of
        _Value -> true
    catch
        error:_ -> false
    end.

ascii_lowercase(Byte) when Byte >= $A, Byte =< $Z -> Byte + 32;
ascii_lowercase(Byte) -> Byte.

events(Function, Argument, Opts) ->
    Fields = fields(Function, Argument, Opts),
    [
        #{
            type => type(Function),
            id => flat(maps:get(id, Opts, ~"")),
            retry => maps:get(retry, Opts, undefined),
            fields => Fields
        }
     || map_size(Fields) > 0
    ].

type(patch_signals) -> ?SIGNALS;
type(remove_signals) -> ?SIGNALS;
type(_Elements) -> ?ELEMENTS.

fields(patch_elements, Html, Opts) ->
    maps:from_list(
        [{~"selector", flat(Selector)} || #{selector := Selector} <- [Opts]] ++
            [{~"mode", name(Mode)} || #{mode := Mode} <- [Opts], Mode =/= outer] ++
            [{~"useViewTransition", ~"true"} || #{use_view_transition := true} <- [Opts]] ++
            [{~"namespace", name(Name)} || #{namespace := Name} <- [Opts], Name =/= html] ++
            [{~"elements", datastar_test_sse:as_received(Html)} || flat(Html) =/= ~""]
    );
fields(patch_signals, Signals, Opts) when is_map(Signals) ->
    signals_fields({json, Signals}, Opts);
fields(patch_signals, Json, Opts) ->
    signals_fields(datastar_test_sse:as_received(Json), Opts);
fields(execute_script, Script, Opts) ->
    Attributes = maps:get(attributes, Opts, []),
    Element = [
        ~"<script",
        [~" type=\"application/javascript\"" || Attributes =/= []],
        [~" data-effect=\"el.remove()\"" || maps:get(auto_remove, Opts, true)],
        [[~" ", Name, ~"=\"", escaped(flat(Value)), ~"\""] || {Name, Value} <- Attributes],
        ~">",
        Script,
        ~"</script>"
    ],
    #{
        ~"selector" => ~"body",
        ~"mode" => ~"append",
        ~"elements" => datastar_test_sse:as_received(Element)
    };
fields(remove_elements, Selector, Opts) ->
    fields(patch_elements, ~"", Opts#{selector => Selector, mode => remove});
fields(remove_signals, Paths, Opts) ->
    signals_fields({json, nulls(removed(Paths))}, Opts).

signals_fields(Signals, Opts) ->
    maps:from_list(
        [{~"onlyIfMissing", ~"true"} || #{only_if_missing := true} <- [Opts]] ++
            [{~"signals", Signals}]
    ).

removed(Paths) ->
    Parts = lists:usort([binary:split(Path, ~".", [global]) || Path <- Paths]),
    [Path || Path <- Parts, not under_another(Path, Parts)].

under_another(Path, Paths) ->
    [] =/= [Other || Other <- Paths, Other =/= Path, lists:prefix(Other, Path)].

nulls(Paths) ->
    maps:map(
        fun
            (_Key, [[]]) -> null;
            (_Key, Rests) -> nulls(Rests)
        end,
        maps:groups_from_list(fun([Key | _]) -> Key end, fun([_ | Rest]) -> Rest end, Paths)
    ).

escaped(Value) ->
    Entities = [
        {~"&", ~"&amp;"}, {~"\"", ~"&quot;"}, {~"'", ~"&#39;"}, {~"<", ~"&lt;"}, {~">", ~"&gt;"}
    ],
    escaped(Value, Entities).

escaped(Value, []) ->
    Value;
escaped(Value, [{Character, Entity} | Entities]) ->
    escaped(binary:replace(Value, Character, Entity, [global]), Entities).

name(Name) when is_atom(Name) -> atom_to_binary(Name);
name(Name) when is_binary(Name) -> Name.

flat(Text) ->
    iolist_to_binary(Text).

%% -- what a call did produce --------------------------------------------------

built({patch_elements, [Html, Opts]}) -> datastar:patch_elements(Html, Opts);
built({patch_signals, [Signals, Opts]}) -> datastar:patch_signals(Signals, Opts);
built({execute_script, [Script, Opts]}) -> datastar:execute_script(Script, Opts);
built({remove_elements, [Selector, Opts]}) -> datastar:remove_elements(Selector, Opts);
built({remove_signals, [Paths, Opts]}) -> datastar:remove_signals(Paths, Opts).

observed(Call) ->
    try built(Call) of
        Event ->
            {events, [
                #{type => Type, id => Id, retry => Retry, fields => datastar_test_sse:fields(Data)}
             || #{type := Type, id := Id, retry := Retry, data := Data} <-
                    datastar_test_sse:events(Event)
            ]}
    catch
        error:Reason -> {raises, Reason}
    end.

agree({events, Expected}, {events, Observed}) ->
    length(Expected) =:= length(Observed) andalso
        lists:all(fun same_event/1, lists:zip(Expected, Observed));
agree({raises, Reasons}, {raises, Reason}) ->
    lists:member(Reason, Reasons);
agree(_Expected, _Observed) ->
    false.

same_event({
    #{fields := #{~"signals" := {json, Signals}} = ExpectedFields} = Expected,
    #{fields := #{~"signals" := Json} = ObservedFields} = Observed
}) ->
    is_json(Json) andalso json:decode(Json) =:= Signals andalso
        Expected#{fields := maps:remove(~"signals", ExpectedFields)} =:=
            Observed#{fields := maps:remove(~"signals", ObservedFields)};
same_event({Expected, Observed}) ->
    Expected =:= Observed.

stray_lines(Call) ->
    try iolist_to_binary(built(Call)) of
        Event ->
            case binary:split(Event, ~"\n", [global]) of
                [<<"event: datastar-patch-", Kind/binary>> | Lines] when
                    Kind =:= ~"elements"; Kind =:= ~"signals"
                ->
                    [carriage_return || binary:match(Event, ~"\r") =/= nomatch] ++
                        stray(Lines);
                Lines ->
                    Lines
            end
    catch
        error:_ -> []
    end.

stray([~"", ~""]) ->
    [];
stray([Line | Lines]) ->
    case known_line(Line) of
        true -> stray(Lines);
        false -> [Line | stray(Lines)]
    end;
stray([]) ->
    [no_blank_line_at_the_end].

known_line(<<"id: ", _/binary>>) -> true;
known_line(<<"retry: ", Digits/binary>>) -> Digits =/= ~"" andalso digits(Digits);
known_line(<<"data: elements ", _/binary>>) -> true;
known_line(<<"data: signals ", _/binary>>) -> true;
known_line(<<"data: selector ", _/binary>>) -> true;
known_line(<<"data: mode ", _/binary>>) -> true;
known_line(<<"data: namespace ", _/binary>>) -> true;
known_line(~"data: useViewTransition true") -> true;
known_line(~"data: onlyIfMissing true") -> true;
known_line(_Line) -> false.

digits(Text) ->
    [] =:= [Byte || <<Byte>> <= Text, Byte < $0 orelse Byte > $9].

%% -- what the builders wrote before -------------------------------------------

unchanged({patch_elements, [Html, Opts]}) ->
    [unchanged_elements(flat(Html), flat_options(Opts)) || without_carriage_return(Html)];
unchanged({remove_elements, [Selector, Opts]}) ->
    [unchanged_elements(~"", flat_options(Opts#{selector => Selector, mode => remove}))];
unchanged({patch_signals, [Signals, Opts]}) when is_map(Signals) ->
    [unchanged_signals(flat(json:encode(Signals)), flat_options(Opts))];
unchanged({patch_signals, [Json, Opts]}) ->
    [
        unchanged_signals(flat(Json), flat_options(Opts))
     || binary:match(flat(Json), [~"\r", ~"\n"]) =:= nomatch
    ];
unchanged({_Function, _Args}) ->
    [].

without_carriage_return(Text) ->
    binary:match(flat(Text), ~"\r") =:= nomatch.

flat_options(Opts) ->
    #{
        Option =>
            case lists:member(Option, [selector, id]) of
                true -> flat(Value);
                false -> Value
            end
     || Option := Value <- Opts
    }.

unchanged_elements(Html, Opts) ->
    iolist_to_binary([
        ~"event: datastar-patch-elements\n",
        meta_lines(Opts),
        [[~"data: selector ", Selector, $\n] || #{selector := Selector} <- [Opts]],
        [[~"data: mode ", name(Mode), $\n] || #{mode := Mode} <- [Opts], Mode =/= outer],
        [~"data: useViewTransition true\n" || #{use_view_transition := true} <- [Opts]],
        [
            [~"data: namespace ", name(Namespace), $\n]
         || #{namespace := Namespace} <- [Opts], Namespace =/= html
        ],
        [
            [~"data: elements ", Line, $\n]
         || Html =/= ~"", Line <- binary:split(Html, ~"\n", [global])
        ],
        $\n
    ]).

unchanged_signals(Json, Opts) ->
    iolist_to_binary([
        ~"event: datastar-patch-signals\n",
        meta_lines(Opts),
        [~"data: onlyIfMissing true\n" || #{only_if_missing := true} <- [Opts]],
        [~"data: signals ", Json, $\n],
        $\n
    ]).

meta_lines(Opts) ->
    [
        [[~"id: ", Id, $\n] || #{id := Id} <- [Opts]],
        [[~"retry: ", integer_to_binary(Retry), $\n] || #{retry := Retry} <- [Opts]]
    ].
