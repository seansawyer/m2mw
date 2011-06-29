-module(m2mw_handler).

-behaviour(gen_fsm).

%% API
-export([recv/0,
         start/3,
         start_link/3]).

%% Behaviour callbacks
-export([init/1,
         code_change/4,
         handle_event/3,
         handle_info/3,
         handle_sync_event/4,
         terminate/3]).

%% State callbacks
-export([recv/2,
         prox/2,
         idle/2]).

%% State data
-record(state, {msg=null, port, recv, send}).

%% ===================================================================
%% API functions
%% ===================================================================

start(SubEndpt, PushEndpt, Port) ->
    gen_fsm:start(?MODULE, [SubEndpt, PushEndpt, Port], []).

start_link(SubEndpt, PushEndpt, Port) ->
    gen_fsm:start_link(?MODULE, [SubEndpt, PushEndpt, Port], []).

recv() ->
    gen_fsm:send_event(?MODULE, recv).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([SubEndpt, PushEndpt, Port]) ->
    {Recv, Send} = init_zmq(SubEndpt, PushEndpt),
    State= #state{port=Port, recv=Recv, send=Send},
    {ok, recv, State}.

code_change(_OldVsn, State, StateData, _Extra) ->
    {ok, State, StateData}.

handle_event(_, State, StateData) ->
    {next_state, State, StateData}.

handle_info(_, State, StateData) ->
    {next_state, State, StateData}.

handle_sync_event(_, _, State, StateData) ->
    {reply, ok, State, StateData}.

terminate(_Reason, _State, _StateData) ->
    ok.

%% ===================================================================
%% State callbacks
%% ===================================================================

recv(timeout, StateData) ->
    {ok, Msg} = erlzmq:recv(StateData#state.recv),
    {next_state, prox, StateData#state{msg=Msg}};
recv(_, StateData) ->
    {next_state, recv, StateData}.

prox(timeout, StateData) ->
    #state{msg=Msg, port=Port, send=Send} = StateData,
    ok = m2mw_socket:listen(Send),
    {ok, MwSendSock} = gen_tcp:connect("localhost", Port, [binary, {packet, 4}]),
    Result = mochiweb_http:loop(MwSendSock, Msg),
    io:format("Result was:~n~p~n", [Result]),
    {next_state, idle, StateData};
prox(_, StateData) ->
    {next_state, prox, StateData, 0}.

idle(finished, StateData) ->
    {next_state, recv, StateData#state{msg=null}};
idle(_, StateData) ->
    {next_state, busy, StateData}.

%% ===================================================================
%% Support functions
%% ===================================================================

init_zmq(SubEndpt, PushEndpt) ->
    {ok, Context} = erlzmq:context(),
    {ok, Recv} = erlzmq:socket(Context, [sub, {active,true}]),
    ok = erlzmq:connect(Recv, SubEndpt),
    ok = erlzmq:setsockopt(Recv, subscribe, "10001"),
    {ok, Send} = erlzmq:socket(Context, push),
    ok = erlzmq:connect(Send, PushEndpt),
    {Recv, Send}.
