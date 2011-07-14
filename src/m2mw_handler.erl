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
    error_logger:info_msg("Waiting for ZeroMQ messages..."),
    {ok, Msg} = erlzmq:recv(StateData1#state.recv),
    error_logger:info_msg("Incoming ZeroMQ message:~n~p~n", [Msg]),
    {next_state, prox, StateData1#state{msg=deconstruct(Msg)}, 0}.

recv({configure, _, _, _}, _, StateData) ->
    {reply, already_configured, recv, StateData}.

prox(timeout, StateData) ->
    #state{msg=Msg, port=Port, send=Send} = StateData,
    error_logger:info_msg("Proxying to Mochiweb on ~p~n", [Port]),
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
    error_logger:info_msg("m2mw configured - sub endpoint ~p, push endpoint ~p~n", [SubEndpt, PushEndpt]),
    {reply, ok, recv, StateData1, 0}.

%% ===================================================================
%% Support functions
%% ===================================================================

init_zmq(SubEndpt, PushEndpt) ->
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
% <<"HSALSelohcnysHSALS-elohcnys-redrawrof 60 / 718:{\"PATH\":\"\\/\",\"x-forwarded-for\":\"10.194.213.220\",\"cache-control\":\"max-age=0\",\"accept-language\":\"en-US,en;q=0.8\",\"connection\":\"close\",\"accept-encoding\":\"gzip,deflate, sdch\",\"accept-charset\":\"ISO-8859-1,utf-8;q=0.7,*;q=0.3\",\"accept\":\"text\\/html,application\\/xhtml+xml,application\\/xml;q=0.9,*\\/*;q=0.8\",\"user-agent\":\"Mozilla\\/5.0 (Macintosh; Intel Mac OS X 10_6_7) AppleWebKit\\/534.30 (KH TML, like Gecko) Chrome\\/12.0.742.112 Safari\\/534.30\",\"host\":\"api.cloud.vitrue.com\",\"cookie\":\"__utma=115479937.1544716122.1299637033.1309269870.1310316619.7; __utmz=115479937.1310317280.7.3.utmccn=(organic)|utmcsr=google|utmctr= vitrue+publisher|utmcmd=organic\",\"METHOD\":\"GET\",\"VERSION\":\"HTTP\\/1.1\",\"URI\":\"\\/\",\"PATTERN\":\"\\/synchole\\/\"},0:,">>
deconstruct(ZmqMsg) ->
    MsgRe = "^([-0-9A-Za-z]+) (\\d+) (.+) (\\d+):(.*),(\\d+):(.*),$",
    MsgStr = unicode:characters_to_list(ZmqMsg),
    {match, Captured} = re:run(ZmqMsg, MsgRe),
    [_|Parts] = [ string:substr(MsgStr, Start+1, Length) || {Start, Length} <- Captured ],
    list_to_tuple(Parts).
    
