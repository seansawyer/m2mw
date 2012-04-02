-module(m2mw_util).

-export([compose_netstring/1,
         compose_netstrings/1,
         compose_response/2,
         compose_response/3,
         crash_handler/2,
         crash_handlers/1,
         is_disconnect/1,
         parse_netstrings/1,
         parse_request/1,
         test_mochiweb/0,
         test_mochiweb/5]).

-include_lib("m2mw.hrl").

-define(DC_BODY,
        <<"{\"type\":\"disconnect\"}">>).
-define(DC_HEADERS,
        <<"{\"METHOD\":\"JSON\"}">>).

%% ===================================================================
%% API
%% ===================================================================

-spec compose_netstring (BinOrStr::binary()|string()) -> binary().
%% @doc Compose a `binary()' containing the netstring representation of the
%% supplied `binary()' or ASCII `string()'. You may not supply a list of
%% Unicode codepoints to this method!
compose_netstring(Data) when is_list(Data) ->
    compose_netstring(list_to_binary(Data));
compose_netstring(Data) ->
    NsList = [integer_to_list(size(Data)), $:, Data, $,],
    iolist_to_binary(NsList).

-spec compose_netstrings (list(binary() | string())) -> binary().
%% @doc Compose a `binary()' containing a netstring series representation of a
%% to a list of one or more `binary()' or `string()' elements.
compose_netstrings(Data) ->
    NssList = [compose_netstring(D) || D <- Data],
    iolist_to_binary(NssList).

-spec compose_response (#req{}, binary()) -> binary().
%% @doc Compose a Mongrel2 response to a `Request' using the `RespBin' as the
%% response.
compose_response(Req, RespBin) ->
    compose_response(Req#req.uuid, Req#req.id, RespBin).

-spec compose_response (binary(), binary(), binary())
                       -> binary().
%% @doc Compose a Mongrel2 response to a request with `Uuid' and `Id' and using
%% `RespBin' as the response.
compose_response(Uuid, Id, RespBin) ->
    Metadata = io_lib:format("~s ~w:~s, ", [Uuid, size(Id), Id]),
    iolist_to_binary([Metadata, RespBin]).

-spec crash_handlers (term()) -> none().
crash_handlers(Reason) ->
    PairSups = supervisor:which_children(m2mw_sup),
    F = fun({_,Pid,_,_}) ->
                m2mw_handler:crash(m2mw_pair_sup:handler(Pid), Reason)
        end,
    lists:foreach(F, PairSups).

-spec crash_handler (pos_integer(), term()) -> none().
crash_handler(Port, Reason) ->
    PairSups = supervisor:which_children(m2mw_sup),
    F = fun({_Port,Pid,_,_}) when _Port =:= Port ->
                m2mw_handler:crash(m2mw_pair_sup:handler(Pid), Reason);
           (_) ->
                ok
        end,
    lists:foreach(F, PairSups).

-spec parse_netstrings (binary())
                       -> list(tuple(NBytes::pos_integer(), Bytes::binary())).
%% @doc Parse a binary containing one or more netstrings into a list of 2-tuples
%% representing each netstring's size and content, in the order in which they
%% appear in `Netstrings'.
parse_netstrings(Netstrings) ->
    parse_netstrings(Netstrings, []).
     
-spec parse_request (binary())
                    -> tuple(Uuid::binary(), Id::binary(),
                             Path::binary(), Headers::binary(),
                             Body::binary()).
%% @doc Parse a ZeroMQ message from Mongrel2 into a tuple. Note that `Headers'
%% are returned as a `binary()' since according to the spec
%% (http://www.w3.org/Protocols/rfc2616/rfc2616.html) they must be ASCII,
%% while `Body' is returned as a `binary()' since it may use a different
%% encoding.
parse_request(ZmqMsg) ->
    {[Uuid, Id, Path], Netstrs} = split(ZmqMsg, <<" ">>, 3),
    [{HdrsSz,Hdrs}, {BodySz,Body}] = parse_netstrings(Netstrs),
    #req{uuid=Uuid, id=Id, path=Path,
         headers_size=HdrsSz, headers=Hdrs,
         body_size=BodySz, body=Body}.
    
-spec is_disconnect (#req{}) -> boolean().
is_disconnect(#req{headers=?DC_HEADERS, body=?DC_BODY}) ->
    true;
is_disconnect(_) ->
    false.

test_mochiweb() ->
    Loop = {mochiweb_http, default_body},
    Sub = "tcp://127.0.0.1:9998",
    Push = "tcp://127.0.0.1:9999",
    test_mochiweb("127.0.0.1", 8080, Loop, Sub, Push).

test_mochiweb(Ip, Port, Loop, Sub, Push) ->
    application:set_env(metal, log_backend, metal_error_logger),
    mochiweb_http:start([{ip, Ip}, {port, Port}, {loop, Loop}]),
    application:start(m2mw),
    m2mw_sup:configure_handlers(Sub, Push, Loop).

%% ===================================================================
%% Support functions
%% ===================================================================

parse_netstrings(<<>>, Acc) ->
    lists:reverse(Acc);
parse_netstrings(Netstrings, Acc) ->
    [NBytes, Rest] = binary:split(Netstrings, <<":">>),
    NBytesInt = list_to_integer(binary_to_list(NBytes)),
    <<Bytes:NBytesInt/binary, $,, Netstrings1/binary>> = Rest,
    parse_netstrings(Netstrings1, [{NBytesInt, Bytes}|Acc]).

split(Subject, Pattern, NParts) ->
    split(Subject, Pattern, NParts, []).

split(Subject, _, 0, Acc) ->
    {lists:reverse(Acc), Subject};
split(Subject, Pattern, NParts, Acc) ->
    [Part, Rest] = binary:split(Subject, Pattern),
    split(Rest, Pattern, NParts-1, [Part|Acc]).
