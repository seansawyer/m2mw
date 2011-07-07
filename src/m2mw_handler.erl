-module(m2mw_handler).

-behaviour(gen_fsm).

%% API
-export([configure/3,
         recv/0,
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
-export([idle/2, idle/3,
         prox/2, prox/3,
         recv/2, recv/3]).
         

%% State data
-record(state, {body_fun=null, msg=null, port=null, recv=null, send=null}).

%% ===================================================================
%% API functions
%% ===================================================================

start(Port) ->
    gen_fsm:start({local, ?MODULE}, ?MODULE, [Port], []).

start_link(Port) ->
    gen_fsm:start_link({local, ?MODULE}, ?MODULE, [Port], []).

configure(SubEndpt, PushEndpt, BodyFun) ->
    gen_fsm:sync_send_event(?MODULE, {configure, SubEndpt, PushEndpt, BodyFun}).

recv() ->
    gen_fsm:send_event(?MODULE, recv).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([Port]) ->
    {ok, idle, #state{port=Port}}.

code_change(_OldVsn, State, StateData, _Extra) ->
    {ok, State, StateData}.

handle_event(_M, State, StateData) ->
    {next_state, State, StateData}.

handle_info(_M, State, StateData) ->
    {next_state, State, StateData}.

handle_sync_event(_M, _, State, StateData) ->
    {reply, ok, State, StateData}.

terminate(_Reason, _State, _StateData) ->
    ok.

%% ===================================================================
%% State callbacks
%% ===================================================================

recv(timeout, StateData) ->
    StateData1 = StateData#state{msg=null},
    {ok, Msg} = erlzmq:recv(StateData1#state.recv),
    {next_state, prox, StateData1#state{msg=deconstruct(Msg)}, 0}.

recv({configure, _, _, _}, _, StateData) ->
    {reply, already_configured, recv, StateData}.

prox(timeout, StateData) ->
    #state{msg=Msg, port=Port, send=Send} = StateData,
    ok = m2mw_socket:exchange(Msg, Send),
    {ok, MwSock} = gen_tcp:connect("localhost", Port, [binary,
                                                       {active, false},
                                                       {packet, http}]),
    put(mochiweb_request_force_close, true),
    try mochiweb_http:loop(MwSock, StateData#state.body_fun)
    catch
        exit:normal -> {next_state, idle, StateData, 10000}
    end;
prox(_, StateData) ->
    {next_state, prox, StateData, 0}.

prox({configure, _, _, _}, _, StateData) ->
    {reply, already_configured, prox, StateData}.
    
idle(recv, StateData) when StateData#state.recv =:= null ->
    error_logger:warn_msg("Unable to receive; ZeroMQ sockets not configured!"),
    {next_state, idle, StateData#state{msg=null}};
idle(recv, StateData) ->
    {next_state, recv, StateData#state{msg=null}, 0};
idle(timeout, StateData) ->
    {next_state, recv, StateData#state{msg=null}, 0}.

idle({configure, SubEndpt, PushEndpt, BodyFun}, _From, StateData) ->
    {Recv, Send} = init_zmq(SubEndpt, PushEndpt),
    StateData1 = StateData#state{body_fun=BodyFun, msg=null, recv=Recv, send=Send},
    {reply, ok, recv, StateData1, 0}.

%% ===================================================================
%% Support functions
%% ===================================================================

init_zmq(SubEndpt, PushEndpt) ->
    SubEndpt =  "tcp://127.0.0.1:9998",
    PushEndpt =  "tcp://127.0.0.1:9999",
    {ok, Context} = erlzmq:context(),
    {ok, Recv} = erlzmq:socket(Context, pull),
    ok = erlzmq:connect(Recv, PushEndpt),
    {ok, Send} = erlzmq:socket(Context, pub),
    ok = erlzmq:connect(Send, SubEndpt),
    {Recv, Send}.

-spec deconstruct (binary()) -> tuple(Uuid::string(), Id::string(), Path::string(),
                                      Headers::string(), Body::string()).
%% @doc Incoming ZeroMQ requests are of the following form:
%%     <<"UUID CLIENT_ID PATH HDRS_SIZE:HDRS,BODY_SIZE:BODY,">>
%% Here we deconstruct them into a tuple:
%%     `{Uuid, Id, Path, HeadersSize, Headers, BodySize, Body}'
deconstruct(ZmqMsg) ->
    MsgRe = "^([-0-9a-z]+) (\\d+) (.+) (\\d+):(.*),(\\d+):(.*),$",
    MsgStr = unicode:characters_to_list(ZmqMsg),
    {match, Captured} = re:run(ZmqMsg, MsgRe),
    [_|Parts] = [ string:substr(MsgStr, Start+1, Length) || {Start, Length} <- Captured ],
    list_to_tuple(Parts).
    
