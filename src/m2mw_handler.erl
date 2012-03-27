-module(m2mw_handler).

-behaviour(gen_server).

-include_lib("m2mw.hrl").

%% API
-export([configure/4,
         crash/2,
         start/3,
         start_link/3]).

%% Behaviour callbacks
-export([init/1,
         code_change/3,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2]).

-define(MW_SOCK_OPTS,
        [binary, {active, false}, {packet, http}]).

%% State data
-record(state, {body_fun=null,
                context,
                port=null,
                recv=null,
                send=null,
                sup_pid}).

%% ===================================================================
%% API functions
%% ===================================================================

start(Context, Port, SupPid) ->
    gen_server:start(?MODULE, [Context, Port, SupPid], []).

start_link(Context, Port, SupPid) ->
    gen_server:start_link(?MODULE, [Context, Port, SupPid], []).

configure(Pid, Sub, Push, BodyFun) ->
    application:set_env(m2mw, sub, Sub),
    application:set_env(m2mw, push, Push),
    application:set_env(m2mw, body_fun, BodyFun),
    gen_server:call(Pid, {configure, Sub, Push, BodyFun}).

crash(Ref, Reason) ->
    gen_server:cast(Ref, {crash, Reason}).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([Context, Port, SupPid]) ->
    process_flag(trap_exit, true),
    MaybeSub = application:get_env(m2mw, sub),
    MaybePush = application:get_env(m2mw, push),
    MaybeBodyFun = application:get_env(m2mw, body_fun),
    init(Context, Port, SupPid, MaybeSub, MaybePush, MaybeBodyFun).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_call({configure, SubEndpt, PushEndpt, BodyFun}, _From, State) ->
    close_sockets(State),
    {Recv, Send} = init_zmq(State#state.context, SubEndpt, PushEndpt),
    State1 = State#state{body_fun=BodyFun, recv=Recv, send=Send},
    {reply, ok, State1};
handle_call(_Msg, _From, State) ->
    {noreply, State}.

handle_cast({crash, Reason}, _State) ->
    error(Reason);
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, Reason}, State)
  when Pid =:= self() ->
    metal:warning("Handler ~p exiting: ~p", [State#state.port, Reason]),
    {stop, Reason, State};
handle_info({zmq, _Socket, Msg, Flags}, State) ->
    message(Msg, Flags, State),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    close_sockets(State),
    ok.

%% ===================================================================
%% Support functions
%% ===================================================================

close_sockets(#state{recv=Recv, send=Send}) ->
    close_socket(Recv),
    close_socket(Send).

close_socket(null) ->
    ok;
close_socket(Socket) ->
    ok = erlzmq:setsockopt(Socket, linger, 0),
    ok = erlzmq:close(Socket, 1000).

init(Context, Port, SupPid, {ok, SubEndpt}, {ok, PushEndpt}, {ok, BodyFun})
  when is_list(SubEndpt),
       is_list(PushEndpt),
       BodyFun =/= undefined ->
    metal:debug("Configuring handler ~p from env (sub ~p, push ~p, fun ~p)",
               [Port, SubEndpt, PushEndpt, BodyFun]),
    {Recv, Send} = init_zmq(Context, SubEndpt, PushEndpt),
    State = #state{body_fun=BodyFun,
                   context=Context,
                   port=Port,
                   recv=Recv,
                   send=Send,
                   sup_pid=SupPid},
    {ok, State};
init(Context, Port, SupPid, _, _, _) ->
    metal:debug("Cannot configure handler ~p from env; use m2mw_handler:configure/3",
               [Port]),
    {ok, #state{context=Context, port=Port, sup_pid=SupPid}}.

init_zmq(Context, SubEndpt, PushEndpt) ->
    {ok, Recv} = erlzmq:socket(Context, [pull, {active, true}]),
    ok = erlzmq:connect(Recv, PushEndpt),
    {ok, Send} = erlzmq:socket(Context, pub),
    ok = erlzmq:connect(Send, SubEndpt),
    metal:debug("Handler sockets configured (context ~p, sub ~p, push ~p)",
                [Context, SubEndpt, PushEndpt]),
    {Recv, Send}.

message(Msg, Flags, #state{body_fun=BodyFun, port=Port,
                           send=Send, sup_pid=SupPid}) ->
    metal:debug("Handler ~p received ZeroMQ message (flags ~p):~n~p~n",
                [Port, Flags, Msg]),
    Req = m2mw_util:parse_request(Msg),
    ok = m2mw_socket:exchange(m2mw_pair_sup:socket(SupPid), Req, Send),
    {ok, MwSock} = gen_tcp:connect("localhost", Port, ?MW_SOCK_OPTS),
    put(mochiweb_request_force_close, true),
    try mochiweb_http:loop(MwSock, BodyFun)
    catch
        exit:normal -> ok
    end.
