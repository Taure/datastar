-module(datastar_errors_tests).

-include_lib("eunit/include/eunit.hrl").

-define(HTML, ~"<p>kept_private</p>").
-define(SCRIPT, ~"kept_private()").
-define(SIGNALS, #{~"token" => ~"kept_private"}).
-define(PATHS, [~"kept_private.token"]).

every_bad_option_raises_invalid_option_test() ->
    Cases = bad_options(),
    ?assertEqual(168, length(Cases)),
    ?assertEqual([], unexpected(Cases)).

every_bad_argument_raises_invalid_argument_test() ->
    Cases = bad_arguments(),
    ?assertEqual(30, length(Cases)),
    ?assertEqual([], unexpected(Cases)).

no_raised_error_carries_a_value_of_the_caller_test() ->
    Cases = bad_options() ++ bad_arguments(),
    ?assertEqual(
        [],
        [
            {Function, Args}
         || {Function, Args, _Expected} <- Cases, carries_the_secret(Function, Args)
        ]
    ).

an_option_set_to_undefined_is_not_an_absent_option_test() ->
    ?assertEqual(
        [],
        unexpected([
            {patch_elements, [?HTML, #{selector => undefined}],
                {invalid_option, selector, not_iodata}},
            {patch_elements, [?HTML, #{id => undefined}], {invalid_option, id, not_iodata}},
            {patch_elements, [?HTML, #{retry => undefined}],
                {invalid_option, retry, not_a_non_negative_integer}}
        ])
    ).

bad_options() ->
    lists:append([
        [
            {Function, Args ++ [#{Option => Value}], {invalid_option, Option, not_iodata}}
         || {Function, Args, Option} <- [
                {patch_elements, [?HTML], selector},
                {patch_elements, [?HTML], id},
                {patch_signals, [?SIGNALS], id},
                {execute_script, [?SCRIPT], id},
                {remove_elements, [~"#kept_private"], id},
                {remove_signals, [?PATHS], id}
            ],
            Value <- not_iodata()
        ],
        [
            {remove_elements, [Value], {invalid_option, selector, not_iodata}}
         || Value <- not_iodata()
        ],
        [
            {patch_elements, [?HTML, #{mode => Mode}], {invalid_option, mode, unknown_mode}}
         || Mode <- [
                kept_private,
                "kept_private",
                ~"kept_private",
                "inner",
                [~"inner"],
                ~"Inner",
                ~"",
                1,
                #{}
            ]
        ],
        [
            {patch_elements, [?HTML, #{namespace => Namespace}],
                {invalid_option, namespace, unknown_namespace}}
         || Namespace <- [
                kept_private, "kept_private", ~"kept_private", "svg", [~"svg"], ~"SVG", ~"", 1, #{}
            ]
        ],
        [
            {Function, Args ++ [#{Option => Flag}], {invalid_option, Option, not_a_boolean}}
         || {Function, Args, Option} <- [
                {patch_elements, [?HTML], use_view_transition},
                {remove_elements, [~"#kept_private"], use_view_transition},
                {patch_signals, [?SIGNALS], only_if_missing},
                {remove_signals, [?PATHS], only_if_missing},
                {execute_script, [?SCRIPT], auto_remove}
            ],
            Flag <- [kept_private, ~"kept_private", "true", ~"true", 1, 0, undefined]
        ],
        [
            {Function, Args ++ [#{retry => Retry}],
                {invalid_option, retry, not_a_non_negative_integer}}
         || {Function, Args} <- builders(),
            Retry <- [~"kept_private", "kept_private", kept_private, 1.0]
        ],
        [
            {execute_script, [?SCRIPT, #{attributes => Attributes}],
                {invalid_option, attributes, not_a_list_of_pairs}}
         || Attributes <- [
                kept_private,
                ~"kept_private",
                #{~"nonce" => ~"kept_private"},
                [~"kept_private"],
                [{~"kept_private"}],
                [{~"nonce", ~"kept_private", ~"more"}],
                [{~"nonce", ~"n"}, kept_private]
            ]
        ],
        [
            {execute_script, [?SCRIPT, #{attributes => [Attribute]}],
                {invalid_option, attributes, not_iodata}}
         || Attribute <- [
                {kept_private, ~"v"},
                {~"nonce", kept_private},
                {~"nonce", 42},
                {~"nonce", [~"kept_private", {x}]},
                {[~"kept_private", 256], ~"v"}
            ]
        ],
        [
            {Function, Args ++ [Opts#{~"kept_private" => ~"kept_private"}],
                {invalid_option, options, unknown_option}}
         || {Function, Args} <- builders(),
            Opts <- [#{}, #{id => ~"7"}]
        ],
        [
            {Function, Args ++ [#{Key => ~"kept_private"}], {invalid_option, Key, unknown_option}}
         || {Function, Args, Key} <- [
                {patch_elements, [?HTML], selecter},
                {patch_elements, [?HTML], only_if_missing},
                {patch_elements, [?HTML], auto_remove},
                {patch_elements, [?HTML], attributes},
                {patch_signals, [?SIGNALS], selector},
                {patch_signals, [?SIGNALS], mode},
                {patch_signals, [?SIGNALS], use_view_transition},
                {patch_signals, [?SIGNALS], onlyIfMissing},
                {execute_script, [?SCRIPT], selector},
                {execute_script, [?SCRIPT], mode},
                {execute_script, [?SCRIPT], namespace},
                {execute_script, [?SCRIPT], autoRemove},
                {remove_elements, [~"#kept_private"], only_if_missing},
                {remove_elements, [~"#kept_private"], retyr},
                {remove_signals, [?PATHS], selector},
                {remove_signals, [?PATHS], namespace}
            ]
        ],
        [
            {Function, Args ++ [Opts], {invalid_option, options, not_a_map}}
         || {Function, Args} <- builders(),
            Opts <- [[{id, ~"kept_private"}], ~"kept_private", kept_private]
        ]
    ]).

bad_arguments() ->
    lists:append([
        [{patch_elements, [Html], {invalid_argument, html, not_iodata}} || Html <- not_iodata()],
        [
            {execute_script, [Script], {invalid_argument, script, not_iodata}}
         || Script <- not_iodata()
        ],
        [
            {patch_signals, [Signals], {invalid_argument, signals, not_iodata}}
         || Signals <- not_iodata(), not is_map(Signals)
        ],
        [
            {patch_signals, [Signals], {invalid_argument, signals, not_encodable}}
         || Signals <- [
                #{~"token" => {~"kept_private"}},
                #{~"token" => <<"kept_private", 16#FF>>},
                #{{~"kept_private"} => 1},
                #{<<"kept_private", 16#C3>> => 1}
            ]
        ],
        [
            {remove_signals, [Paths], {invalid_argument, paths, not_a_list_of_binaries}}
         || Paths <- [
                kept_private,
                ~"kept_private.token",
                [kept_private],
                ["kept_private"],
                [[~"kept_private"]],
                [~"a", {~"kept_private"}]
            ]
        ],
        [
            {remove_signals, [[<<"kept_private.", 16#FF>>]],
                {invalid_argument, paths, not_encodable}},
            {execute_script, [~"kept_private('</script>')"],
                {invalid_argument, script, closing_tag}},
            {patch_signals, [~"{\"token\":kept_private}"], {invalid_argument, signals, not_json}}
        ]
    ]).

not_iodata() ->
    [
        kept_private,
        42,
        {~"kept_private"},
        [~"kept_private", {x}],
        [~"kept_private", 256],
        #{~"kept_private" => 1}
    ].

builders() ->
    [
        {patch_elements, [?HTML]},
        {patch_signals, [?SIGNALS]},
        {execute_script, [?SCRIPT]},
        {remove_elements, [~"#kept_private"]},
        {remove_signals, [?PATHS]}
    ].

unexpected(Cases) ->
    [
        {Function, Args, Raised}
     || {Function, Args, Expected} <- Cases,
        Raised <- [raised(Function, Args)],
        Raised =/= Expected
    ].

raised(Function, Args) ->
    try apply(datastar, Function, Args) of
        _Event -> nothing
    catch
        error:Reason -> Reason
    end.

carries_the_secret(Function, Args) ->
    try apply(datastar, Function, Args) of
        _Event -> false
    catch
        Class:Reason:Stacktrace ->
            case
                unicode:characters_to_binary(io_lib:format("~0tp", [{Class, Reason, Stacktrace}]))
            of
                Shown when is_binary(Shown) -> binary:match(Shown, ~"kept_private") =/= nomatch
            end
    end.
