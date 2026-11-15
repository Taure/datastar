-module(datastar_test_sse).

%% A reader for the wire format of
%% https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
%% plus the way a Datastar client groups the `data` lines of one event.

-export([events/1, fields/1, texts/0, as_received/1]).

-export_type([event/0]).

-type event() :: #{
    type := binary(),
    data := binary(),
    id := binary(),
    retry := non_neg_integer() | undefined
}.

-record(reader, {
    type = ~"" :: binary(),
    data = none :: none | binary(),
    id = ~"" :: binary(),
    retry = undefined :: non_neg_integer() | undefined
}).

-spec events(iodata()) -> [event()].
events(Stream) ->
    read(lines(without_bom(iolist_to_binary(Stream))), #reader{}, []).

-spec fields(binary()) -> #{binary() => binary()}.
fields(Data) ->
    Pairs = [key_value(Line) || Line <- binary:split(Data, ~"\n", [global])],
    maps:map(
        fun(_Key, Values) -> joined(Values) end,
        maps:groups_from_list(
            fun({Key, _Value}) -> Key end,
            fun({_Key, Value}) -> Value end,
            Pairs
        )
    ).

-spec texts() -> [binary()].
texts() ->
    Breaks = [~"\r", ~"\n", ~"\r\n", ~"\n\r", ~"\r\r\n", ~"\n\n", ~"\r\r", ~"\r\n\r\n"],
    Lines = [
        ~"x",
        ~" x ",
        ~"event: datastar-patch-signals",
        ~"event: datastar-patch-elements",
        ~"data: signals {\"other\":true}",
        ~"data: elements <p id=\"other\"></p>",
        ~"data: selector #other",
        ~"id: 99",
        ~"retry: 1",
        ~": note"
    ],
    Breaks ++ [Text || Break <- Breaks, Line <- Lines, Text <- shapes(Break, Line)].

-spec shapes(binary(), binary()) -> [binary()].
shapes(Break, Line) ->
    [
        <<Break/binary, Line/binary>>,
        <<Line/binary, Break/binary>>,
        <<$a, Break/binary, Line/binary>>,
        <<$a, Break/binary, Line/binary, Break/binary, $b>>,
        <<Break/binary, Line/binary, Break/binary>>,
        <<
            $a,
            Break/binary,
            "event: datastar-patch-signals",
            Break/binary,
            Line/binary,
            Break/binary,
            Break/binary,
            $b
        >>
    ].

-spec as_received(iodata()) -> binary().
as_received(Text) ->
    lf_only(iolist_to_binary(Text), ~"").

lf_only(~"", Acc) -> Acc;
lf_only(<<$\r, $\n, Rest/binary>>, Acc) -> lf_only(Rest, <<Acc/binary, $\n>>);
lf_only(<<$\r, Rest/binary>>, Acc) -> lf_only(Rest, <<Acc/binary, $\n>>);
lf_only(<<Byte, Rest/binary>>, Acc) -> lf_only(Rest, <<Acc/binary, Byte>>).

without_bom(<<16#FEFF/utf8, Rest/binary>>) -> Rest;
without_bom(Stream) -> Stream.

lines(Stream) ->
    lines(Stream, ~"", []).

lines(~"", _Unterminated, Acc) ->
    lists:reverse(Acc);
lines(<<$\r, $\n, Rest/binary>>, Line, Acc) ->
    lines(Rest, ~"", [Line | Acc]);
lines(<<$\r, Rest/binary>>, Line, Acc) ->
    lines(Rest, ~"", [Line | Acc]);
lines(<<$\n, Rest/binary>>, Line, Acc) ->
    lines(Rest, ~"", [Line | Acc]);
lines(<<Byte, Rest/binary>>, Line, Acc) ->
    lines(Rest, <<Line/binary, Byte>>, Acc).

read([], _Reader, Events) ->
    lists:reverse(Events);
read([~"" | Lines], #reader{data = none} = Reader, Events) ->
    read(Lines, Reader#reader{type = ~""}, Events);
read([~"" | Lines], #reader{data = Data} = Reader, Events) ->
    Event = #{
        type => type(Reader#reader.type),
        data => Data,
        id => Reader#reader.id,
        retry => Reader#reader.retry
    },
    read(Lines, Reader#reader{type = ~"", data = none}, [Event | Events]);
read([<<$:, _Comment/binary>> | Lines], Reader, Events) ->
    read(Lines, Reader, Events);
read([Line | Lines], Reader, Events) ->
    read(Lines, field(name_value(Line), Reader), Events).

-spec joined([binary()]) -> binary().
joined([]) -> ~"";
joined([First | Rest]) -> iolist_to_binary([First | [[$\n, Line] || Line <- Rest]]).

type(~"") -> ~"message";
type(Type) -> Type.

name_value(Line) ->
    case binary:split(Line, ~":") of
        [Name, <<$\s, Value/binary>>] -> {Name, Value};
        [Name, Value] -> {Name, Value};
        [Name] -> {Name, ~""}
    end.

field({~"event", Value}, Reader) ->
    Reader#reader{type = Value};
field({~"data", Value}, #reader{data = none} = Reader) ->
    Reader#reader{data = Value};
field({~"data", Value}, #reader{data = Data} = Reader) ->
    Reader#reader{data = <<Data/binary, $\n, Value/binary>>};
field({~"id", Value}, Reader) ->
    case binary:match(Value, ~"\0") of
        nomatch -> Reader#reader{id = Value};
        _ -> Reader
    end;
field({~"retry", Value}, Reader) ->
    case Value =/= ~"" andalso [] =:= [Byte || <<Byte>> <= Value, Byte < $0 orelse Byte > $9] of
        true -> Reader#reader{retry = binary_to_integer(Value)};
        false -> Reader
    end;
field({_Name, _Value}, Reader) ->
    Reader.

key_value(Line) ->
    case binary:split(Line, ~" ") of
        [Key, Value] -> {Key, Value};
        [Key] -> {Key, ~""}
    end.
