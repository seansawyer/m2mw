-module(m2mw_socket).

-behaviour(gen_fsm).

-include_lib("m2mw.hrl").

%% API
-export([exchange/3,
         start/2,
         start_link/2]).

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
-record(state, {listen=null,
                mw_sock=null,
                port=null,
                req=null,
                sup_pid,
                zmq_send=null}).

-define(SOCK_OPTS,
        [binary, {active, false}, {backlog, 30}, {packet, http}, {reuseaddr, true}]).
-define(TIMEOUT_HEADERS, 300000).
-define(TIMEOUT_RESPONSE, 30000).

%% ===================================================================
%% API functions
%% ===================================================================

start(Port, SupPid) ->
    gen_fsm:start(?MODULE, [Port, SupPid], []).

start_link(Port, SupPid) ->
    gen_fsm:start_link(?MODULE, [Port, SupPid], []).

exchange(Pid, Req, ZmqSend) ->
    gen_fsm:sync_send_event(Pid, {accept, Req, ZmqSend}).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([Port, SupPid]) ->
    {ok, Listen} = gen_tcp:listen(Port, ?SOCK_OPTS),
    State = #state{listen=Listen, port=Port, sup_pid=SupPid},
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
    #state{mw_sock=MwSock,
           port=Port,
           req=Req,
           sup_pid=SupPid,
           zmq_send=ZmqSend} = StateData,
    HttpReq = m2mw_http:construct_req(Req),
    ok = gen_tcp:send(MwSock, HttpReq),
    MwResp = m2mw_http:collect_resp(MwSock),
    ZmqResp = m2mw_util:compose_response(Req, MwResp),
    metal:debug("Socket ~p sending ZeroMQ response:~n~p~n", [Port, ZmqResp]),
    erlzmq:send(ZmqSend, ZmqResp),
    ok = m2mw_handler:recv(m2mw_pair_sup:handler(SupPid)),
    StateData1 = StateData#state{mw_sock=null, req=null, zmq_send=null},
    {next_state, idle, StateData1}.
