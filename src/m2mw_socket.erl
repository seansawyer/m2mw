-module(m2mw_socket).

-behaviour(gen_fsm).

%% API
-export([exchange/2,
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

%% State data
-record(state, {listen=null, mw_sock=null, port=null, zmq_msg=null, zmq_send=null}).

-define(TIMEOUT_HEADERS, 300000).
-define(TIMEOUT_RESPONSE, 30000).

%% ===================================================================
%% API functions
%% ===================================================================

start(Port) ->
    gen_fsm:start({local, ?MODULE}, ?MODULE, [Port], []).

start_link(Port) ->
    gen_fsm:start_link({local, ?MODULE}, ?MODULE, [Port], []).

exchange(ZmqMsg, ZmqSend) ->
    gen_fsm:sync_send_event(?MODULE, {accept, ZmqMsg, ZmqSend}).

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

idle({accept, ZmqMsg, ZmqSend}, _From, StateData) ->
    {reply, ok, accept, StateData#state{zmq_msg=ZmqMsg, zmq_send=ZmqSend}, 0}.

accept(timeout, StateData) ->
    {ok, MwSock} = gen_tcp:accept(StateData#state.listen),
    {next_state, reply, StateData#state{mw_sock=MwSock}, 0}.

reply(timeout, StateData) ->
    #state{mw_sock=MwSock, zmq_msg=ZmqMsg, zmq_send=ZmqSend} = StateData,
    HttpReq = construct_http_req(ZmqMsg),
    error_logger:info_msg("Reformed HTTP request:~n~p~n", [HttpReq]),
    ok = gen_tcp:send(MwSock, HttpReq),
    MochiResp = collect_resp(MwSock),
    error_logger:info_msg("Collected Mochiweb response:~n~p~n", [MochiResp]),
    ZmqResp = construct_zmq_resp(ZmqMsg, MochiResp),
    error_logger:info_msg("Constructed ZeroMQ response:~n~p~n", [ZmqResp]),
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
            error_logger:error_msg("Timed out waiting on response from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            error_logger:error_msg("Unexpected value recv'd for response line:~n~p~n", [Other]),
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
            error_logger:error_msg("Timed out waiting on headers from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            error_logger:error_msg("Unexpected value recv'd for header:~n~p~n", [Other]),
            ok = gen_tcp:close(MwSock),
            Lines
    end.

collect_resp_body(MwSock, Lines, ContentLength) ->
    collect_resp_body(MwSock, ["\r\n"|Lines], ContentLength, 0).

collect_resp_body(MwSock, Lines, undefined, _) ->
    error_logger:info_msg("No content length was specified; sending empty response."),
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
            error_logger:error_msg("Unexpected value recv'd for body:~n~p~n", [Other]),
            Lines
    end,
    ok = gen_tcp:close(MwSock),
    Lines1.

construct_http_req({_Uuid, _Id, Path, _HeadersSize, Headers, _BodySize, Body}) ->
    {struct, HeadersPl} = mochijson2:decode(Headers),
    Method = proplists:get_value(<<"METHOD">>, HeadersPl),
    Vsn = proplists:get_value(<<"VERSION">>, HeadersPl),
    RequestLine = io_lib:format("~s ~s ~s\r\n", [Method, Path, Vsn]),
    HeaderLines = [io_lib:format("~s: ~s\r\n", [K,V]) || {K,V} <- HeadersPl],
    unicode:characters_to_binary(RequestLine ++ HeaderLines ++ "\r\n" ++ Body).

construct_zmq_resp({Uuid, Id, _, _, _, _, _}, MochiResp) ->
    IoList = io_lib:format("~s ~w:~s, ~s", [Uuid, length(Id), Id, MochiResp]),
    unicode:characters_to_binary(IoList).
 
init_socket(Port) ->
    SockOpts = [binary, {active, false}, {backlog, 30}, {packet, http}, {reuseaddr, true} ],
    {ok, Listen} = gen_tcp:listen(Port, SockOpts),
    Listen.

reset(StateData) ->
    ok = m2mw_handler:recv(),
    % ok = gen_tcp:close(StateData#state.mw_sock),
    StateData#state{mw_sock=null, zmq_msg=null, zmq_send=null}.
