-module(datastar_property_tests).

-include_lib("eunit/include/eunit.hrl").

%% Each case is one seeded set of random arguments and options sent through
%% every builder. DATASTAR_PROPERTY_CASES sets how many cases run.
-define(DEFAULT_CASES, "2000").

random_calls_arrive_as_intended_test_() ->
    {timeout, 3600, fun() ->
        Calls = calls(),
        ?assertEqual(
            [],
            lists:sublist(
                [
                    {Call, Expected, Observed}
                 || Call <- Calls,
                    Expected <- [datastar_test_model:expected(Call)],
                    Observed <- [datastar_test_model:observed(Call)],
                    not datastar_test_model:agree(Expected, Observed)
                ],
                3
            )
        )
    end}.

random_calls_write_no_stray_line_test_() ->
    {timeout, 3600, fun() ->
        ?assertEqual(
            [],
            lists:sublist(
                [
                    {Call, Stray}
                 || Call <- calls(),
                    Stray <- [datastar_test_model:stray_lines(Call)],
                    Stray =/= []
                ],
                3
            )
        )
    end}.

random_calls_without_a_carriage_return_are_written_as_before_test_() ->
    {timeout, 3600, fun() ->
        ?assertEqual(
            [],
            lists:sublist(
                [
                    {Call, Before}
                 || Call <- calls(),
                    {events, _Events} <- [datastar_test_model:expected(Call)],
                    Before <- datastar_test_model:unchanged(Call),
                    Before =/= iolist_to_binary(datastar_test_model:built(Call))
                ],
                3
            )
        )
    end}.

random_calls_are_both_accepted_and_refused_test() ->
    Outcomes = [Outcome || Call <- calls(), {Outcome, _} <- [datastar_test_model:expected(Call)]],
    Accepted = length([accepted || events <- Outcomes]),
    Refused = length([refused || raises <- Outcomes]),
    case os:getenv("DATASTAR_PROPERTY_CASES") of
        false ->
            ok;
        _Set ->
            io:format(user, "~n~b calls: ~b accepted, ~b refused~n", [
                length(Outcomes), Accepted, Refused
            ])
    end,
    ?assert(Accepted * 4 > length(Outcomes)),
    ?assert(Refused * 4 > length(Outcomes)).

calls() ->
    Cases = list_to_integer(os:getenv("DATASTAR_PROPERTY_CASES", ?DEFAULT_CASES)),
    lists:append([datastar_test_model:calls(Index) || Index <- lists:seq(1, Cases)]).
