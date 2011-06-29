-module(m2mw_socket).

-behaviour(gen_fsm).

%% API
-export([listen/1,
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
-record(state, {listen=null, mwsock=null, port=null, send=null}).

%% ===================================================================
%% API functions
%% ===================================================================

start(Port) ->
    gen_fsm:start(?MODULE, [Port], []).

start_link(Port) ->
    gen_fsm:start_link(?MODULE, [Port], []).

listen(ZmqSend) ->
    gen_fsm:sync_send_event(?MODULE, {accept, ZmqSend}).

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

idle({accept, ZmqSend}, _From, StateData) ->
    {reply, ok, accept, StateData#state{send=ZmqSend}, 0}.

accept(timeout, StateData) ->
    {ok, Socket} = gen_tcp:accept(StateData#state.listen),
    {next_state, reply, StateData#state{mwsock=Socket}, 0}.

reply(timeout, StateData) ->
    #state{mwsock=MwSock, send=Send} = StateData,
    receive
        {tcp, MwSock, Bin} ->
            erlzmq:send(Send, Bin),
            {next_state, reply, StateData, 0};
        {tcp_closed, MwSock} ->
            ok = m2mw_handler:recv(),
            ok = gen_tcp:close(MwSock),
            StateData1 = StateData#state{mwsock=null, send=null},
            {next_state, idle, StateData1} 
    end.

%% ===================================================================
%% Support functions
%% ===================================================================
 
init_socket(Port) ->
    SockOpts = [binary, {packet, 4}, {reuseaddr, true}, {active, true} ],
    {ok, Listen} = gen_tcp:listen(Port, SockOpts),
    Listen.
