-module(m2mw_socket).

-behaviour(gen_fsm).

-include_lib("m2mw.hrl").

%% API
-export([exchange/3,
         start/1,
         start_link/1]).

%% Behaviour callbacks
-export([init/1,
         code_change/4,
         handle_event/3,
         handle_info/3,
         handle_sync_event/4,
         terminate/3]).

%% State callbacks
-export([idle/3,
         accept/2,
         reply/2]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% State data
-record(state, {listen=null, mw_sock=null, port=null, req=null, zmq_send=null}).

-define(TIMEOUT_HEADERS, 300000).
-define(TIMEOUT_RESPONSE, 30000).

%% ===================================================================
%% API functions
%% ===================================================================

start(Port) ->
    gen_fsm:start(?MODULE, [Port], []).

start_link(Port) ->
    gen_fsm:start_link(?MODULE, [Port], []).

exchange(Pid, Req, ZmqSend) ->
    gen_fsm:sync_send_event(Pid, {accept, Req, ZmqSend}).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([Port]) ->
    Listen = init_socket(Port),
    State = #state{listen=Listen, port=Port},
    {ok, idle, State}.

code_change(_OldVsn, State, StateData, _Extra) ->
    {ok, State, StateData}.

handle_event(_, State, StateData) ->
    {next_state, State, StateData}.

handle_info(_, State, StateData) ->
    {next_state, State, StateData}.

handle_sync_event(_, _, State, StateData) ->
    {reply, ok, State, StateData}.

terminate(_Reason, _State, StateData) ->
    gen_tcp:close(StateData#state.listen),
    ok.

%% ===================================================================
%% State callbacks
%% ===================================================================

idle({accept, Req, ZmqSend}, _From, StateData) ->
    {reply, ok, accept, StateData#state{req=Req, zmq_send=ZmqSend}, 0}.

accept(timeout, StateData) ->
    {ok, MwSock} = gen_tcp:accept(StateData#state.listen),
    {next_state, reply, StateData#state{mw_sock=MwSock}, 0}.

reply(timeout, StateData) ->
    #state{mw_sock=MwSock, req=Req, zmq_send=ZmqSend} = StateData,
    HttpReq = construct_http_req(Req),
    ok = gen_tcp:send(MwSock, HttpReq),
    MochiResp = collect_resp(MwSock),
    ZmqResp = m2mw_util:compose_response(Req, MochiResp),
    metal:debug("Constructed ZeroMQ response:~n~p~n", [ZmqResp]),
    erlzmq:send(ZmqSend, ZmqResp),
    {next_state, idle, reset(StateData)}. 

%% ===================================================================
%% Support functions
%% ===================================================================

collect_resp(MwSock) ->
    unicode:characters_to_binary(lists:reverse(collect_resp(MwSock, []))).

collect_resp(MwSock, Lines) ->
    case gen_tcp:recv(MwSock, 0, ?TIMEOUT_RESPONSE) of
        {ok, {http_response, {VsnMaj, VsnMin}, Code, Msg}} ->
            inet:setopts(MwSock, [{packet, httph}]),
            ResponseLine = io_lib:format("HTTP/~b.~b ~b ~s\r\n",
                                         [VsnMaj, VsnMin, Code, Msg]),
            collect_resp_headers(MwSock, [ResponseLine|Lines]);
        {ok, {http_error, "\r\n"}} ->
            collect_resp_headers(MwSock, Lines);
        {ok, {http_error, "\n"}} ->
            collect_resp_headers(MwSock, Lines);
        {error, closed} ->
            ok = gen_tcp:close(MwSock),
            Lines;
        {error, timeout} ->
            metal:error("Timed out waiting on response from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for response line:~n~p~n", [Other]),
            ok = gen_tcp:close(MwSock),
            Lines
    end.

collect_resp_headers(MwSock, Lines) ->
    collect_resp_headers(MwSock, Lines, undefined).

collect_resp_headers(MwSock, Lines, ContentLength) ->
    case gen_tcp:recv(MwSock, 0, ?TIMEOUT_HEADERS) of
        {ok, http_eoh} ->
            % body is next
            inet:setopts(MwSock, [{packet, raw}]),
            collect_resp_body(MwSock, ["Connection: close\r\n"|Lines], ContentLength);
        {ok, {http_header, _, 'Content-Length', _, Value}} ->
            HeaderLine = io_lib:format("Content-Length: ~s\r\n", [Value]),
            collect_resp_headers(MwSock, [HeaderLine|Lines], list_to_integer(Value));
        {ok, {http_header, _, Name, _, Value}} ->
            HeaderLine = io_lib:format("~s: ~s\r\n", [Name, Value]),
            collect_resp_headers(MwSock, [HeaderLine|Lines], ContentLength);
        {error, closed} ->
            ok = gen_tcp:close(MwSock),
            Lines;
        {error, timeout} ->
            metal:error("Timed out waiting on headers from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for header:~n~p~n", [Other]),
            ok = gen_tcp:close(MwSock),
            Lines
    end.

collect_resp_body(MwSock, Lines, ContentLength) ->
    collect_resp_body(MwSock, ["\r\n"|Lines], ContentLength, 0).

collect_resp_body(MwSock, Lines, undefined, _) ->
    metal:debug("No content length was specified; sending empty response."),
    ok = gen_tcp:close(MwSock),
    Lines;
collect_resp_body(MwSock, Lines, ContentLength, Read) when Read >= ContentLength ->
    ok = gen_tcp:close(MwSock),
    Lines; 
collect_resp_body(MwSock, Lines, ContentLength, NRead) ->
    Lines1 = case gen_tcp:recv(MwSock, 0, ?TIMEOUT_RESPONSE) of
        {ok, Data} ->
            NRead1 = NRead + erlang:size(Data),
            collect_resp_body(MwSock, [Data|Lines], ContentLength, NRead1);
        {error, closed}  ->
            Lines; 
        {error, timeout} ->
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for body:~n~p~n", [Other]),
            Lines
    end,
    ok = gen_tcp:close(MwSock),
    Lines1.

construct_http_req(#req{headers=Headers, body=Body}) ->
    {struct, HeadersPl} = mochijson2:decode(Headers),
    Method = proplists:get_value(<<"METHOD">>, HeadersPl),
    Uri = proplists:get_value(<<"URI">>, HeadersPl),
    Vsn = proplists:get_value(<<"VERSION">>, HeadersPl),
    RequestLine = io_lib:format("~s ~s ~s\r\n", [Method, Uri, Vsn]),
    %% We assume that expect header is handled by Mongrel2, so we redact it here
    %% to prevent duplicate 100s, etc.
    HeadersPl1 = proplists:delete(<<"expect">>, HeadersPl),
    HeaderLines = [io_lib:format("~s: ~s\r\n", [K,V]) || {K,V} <- HeadersPl1],
    iolist_to_binary([RequestLine, HeaderLines, "\r\n", Body]).
 
init_socket(Port) ->
    SockOpts = [binary, {active, false}, {backlog, 30}, {packet, http}, {reuseaddr, true} ],
    {ok, Listen} = gen_tcp:listen(Port, SockOpts),
    Listen.

reset(StateData) ->
    HandlerPid = m2mw_sup:handler(StateData#state.port),
    ok = m2mw_handler:recv(HandlerPid),
    % ok = gen_tcp:close(StateData#state.mw_sock),
    StateData#state{mw_sock=null, req=null, zmq_send=null}.

-ifdef(TEST).
%% ===================================================================
%% Support function tests
%% ===================================================================

construct_http_req_test_() ->
    F = fun construct_http_req/1,
    ZmqMsgExpect = <<"HSALSelohcnysHSALS-elohcnys-redrawrof 140 /foo/4f4ce03d8a1dc75c580000a6 340:{\"PATH\":\"\/foo\/4f4ce03d8a1dc75c580000a6\",\"x-forwarded-for\":\"10.68.21.199\",\"content-type\":\"application\/json\",\"expect\":\"100-continue\",\"connection\":\"close\",\"accept-encoding\":\"deflate, gzip\",\"content-length\":\"15\",\"accept\":\"*\/*\",\"host\":\"somehost.com\",\"METHOD\":\"PUT\",\"VERSION\":\"HTTP\/1.1\",\"URI\":\"\/foo\/f4ce03d8a1dc75c580000a6\",\"PATTERN\":\"\/pattern\/\"},15:{\"name\":\"m2mw\"},">>,
    ZmqMsgNoExpect = <<"HSALSelohcnysHSALS-elohcnys-redrawrof 140 /foo/4f4ce03d8a1dc75c580000a6 316:{\"PATH\":\"\/foo\/4f4ce03d8a1dc75c580000a6\",\"x-forwarded-for\":\"10.68.21.199\",\"content-type\":\"application\/json\",\"connection\":\"close\",\"accept-encoding\":\"deflate, gzip\",\"content-length\":\"15\",\"accept\":\"*\/*\",\"host\":\"somehost.com\",\"METHOD\":\"PUT\",\"VERSION\":\"HTTP\/1.1\",\"URI\":\"\/foo\/f4ce03d8a1dc75c580000a6\",\"PATTERN\":\"\/pattern\/\"},15:{\"name\":\"m2mw\"},">>,
    HttpReq = <<"PUT /foo/f4ce03d8a1dc75c580000a6 HTTP/1.1\r\nPATH: /foo/4f4ce03d8a1dc75c580000a6\r\nx-forwarded-for: 10.68.21.199\r\ncontent-type: application/json\r\nconnection: close\r\naccept-encoding: deflate, gzip\r\ncontent-length: 15\r\naccept: */*\r\nhost: somehost.com\r\nMETHOD: PUT\r\nVERSION: HTTP/1.1\r\nURI: /foo/f4ce03d8a1dc75c580000a6\r\nPATTERN: /pattern/\r\n\r\n{\"name\":\"m2mw\"}">>,
    [{"constructs a request with the Expect header redacted when present",
      ?_assertMatch(HttpReq, F(m2mw_util:parse_request(ZmqMsgExpect)))},
     {"constructs the same request when the Expect header is not present",
      ?_assertMatch(HttpReq, F(m2mw_util:parse_request(ZmqMsgNoExpect)))}].
-endif.
