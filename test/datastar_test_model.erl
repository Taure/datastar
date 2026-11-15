-module(datastar_test_model).

%% What the builders wrote before carriage returns were framed, for input
%% they still accept. Text is split at `\n` only.

-export([unchanged_elements/2, unchanged_signals/2]).

-spec unchanged_elements(binary(), map()) -> binary().
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

-spec unchanged_signals(binary(), map()) -> binary().
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

name(Name) when is_atom(Name) -> atom_to_binary(Name);
name(Name) when is_binary(Name) -> Name.
