-module(m2mw_handler).

-behaviour(gen_fsm).

-include_lib("m2mw.hrl").

%% API
-export([configure/4,
         crash/2,
         recv/1,
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
-export([idle/2, idle/3,
         prox/2, prox/3,
         recv/2, recv/3]).

-define(MW_SOCK_OPTS,
        [binary, {active, false}, {packet, http}]).

%% State data
-record(state, {body_fun=null,
                context,
                port=null,
                recv=null,
                req=null,
                send=null,
                sup_pid}).

%% ===================================================================
%% API functions
%% ===================================================================

configure(Ref, Sub, Push, BodyFun) ->
    application:set_env(m2mw, sub, Sub),
    application:set_env(m2mw, push, Push),
    application:set_env(m2mw, body_fun, BodyFun),
    gen_fsm:sync_send_event(Ref, {configure, Sub, Push, BodyFun}).

crash(Ref, Reason) ->
    gen_fsm:send_all_state_event(Ref, {crash, Reason}).

recv(Ref) ->
    gen_fsm:send_event(Ref, recv).

start(Context, Port, SupPid) ->
    gen_fsm:start(?MODULE, [Context, Port, SupPid], []).

start_link(Context, Port, SupPid) ->
    gen_fsm:start_link(?MODULE, [Context, Port, SupPid], []).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

init([Context, Port, SupPid]) ->
    process_flag(trap_exit, true),
    MaybeSub = application:get_env(m2mw, sub),
    MaybePush = application:get_env(m2mw, push),
    MaybeBodyFun = application:get_env(m2mw, body_fun),
    init(Context, Port, SupPid, MaybeSub, MaybePush, MaybeBodyFun).

code_change(_OldVsn, State, StateData, _Extra) ->
    {ok, State, StateData}.

handle_event({crash, Reason}, _State, _StateData) ->
    error(Reason);
handle_event(_M, State, StateData) ->
    {next_state, State, StateData}.

handle_info(_M, State, StateData) ->
    {next_state, State, StateData}.

handle_sync_event(_M, _, State, StateData) ->
    {reply, ok, State, StateData}.

terminate(_Reason, _State, #state{port=Port}=StateData) ->
    close_sockets(StateData),
    metal:warning("Handler ~p terminating, sockets closed", [Port]),
    ok.

%% ===================================================================
%% State callbacks
%% ===================================================================
    
idle(recv, StateData) when StateData#state.recv =:= null ->
    metal:warning("Unable to receive; 0MQ sockets not configured!"),
    {next_state, idle, StateData#state{req=null}};
idle(recv, StateData) ->
    {next_state, recv, StateData#state{req=null}, 0};
idle(timeout, StateData) ->
    {next_state, recv, StateData#state{req=null}, 0}.

idle({configure, SubEndpt, PushEndpt, BodyFun}, _From, StateData) ->
    #state{context=Context, port=Port} = StateData,
    close_sockets(StateData),
    {Recv, Send} = init_zmq(Context, SubEndpt, PushEndpt),
    metal:debug("Handler ~p configured (sub ~p, push ~p)",
                [Port, SubEndpt, PushEndpt]),
    StateData1 = StateData#state{body_fun=BodyFun, req=null, recv=Recv, send=Send},
    {reply, ok, recv, StateData1, 0}.

recv(timeout, #state{port=Port, recv=Recv}=StateData) ->
    StateData1 = StateData#state{req=null},
    metal:debug("Handler ~p polling Mongrel2 on 0MQ socket: ~p", [Port, Recv]),
    {ok, Msg} = erlzmq:recv(Recv),
    metal:debug("Handler ~p received ZeroMQ message:~n~p~n",
                [Port, Msg]),
    Req = m2mw_util:parse_request(Msg),
    case m2mw_util:is_disconnect(Req) of
        true ->
            {next_state, recv, StateData1, 0};
        _ ->
            {next_state, prox, StateData1#state{req=Req}, 0}
    end.

recv({configure, _, _, _}, _, StateData) ->
    {reply, already_configured, recv, StateData}.

prox(timeout, StateData) ->
    #state{body_fun=BodyFun,
           port=Port,
           req=Req,
           send=Send,
           sup_pid=SupPid} = StateData,
    ok = m2mw_socket:exchange(m2mw_pair_sup:socket(SupPid), Req, Send),
    {ok, MwSock} = gen_tcp:connect("localhost", Port, ?MW_SOCK_OPTS),
    put(mochiweb_request_force_close, true),
    try mochiweb_http:loop(MwSock, BodyFun)
    catch
        exit:normal -> {next_state, idle, StateData, 10000}
    end;
prox(_, StateData) ->
    {next_state, prox, StateData, 0}.

prox({configure, _, _, _}, _, StateData) ->
    {reply, already_configured, prox, StateData}.

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
    metal:debug("Handler ~p configuring from env (sub ~p, push ~p, fun ~p)",
               [Port, SubEndpt, PushEndpt, BodyFun]),
    {Recv, Send} = init_zmq(Context, SubEndpt, PushEndpt),
    StateData = #state{body_fun=BodyFun,
                       context=Context,
                       port=Port,
                       recv=Recv,
                       send=Send,
                       sup_pid=SupPid},
    {ok, recv, StateData, 0};
init(Context, Port, SupPid, _, _, _) ->
    metal:debug("Handler ~p can't configure from env; use m2mw_handler:configure/3",
               [Port]),
    StateData = #state{context=Context, port=Port, sup_pid=SupPid},
    {ok, idle, StateData}.

init_zmq(Context, SubEndpt, PushEndpt) ->
    {ok, Recv} = erlzmq:socket(Context, pull),
    ok = erlzmq:connect(Recv, PushEndpt),
    {ok, Send} = erlzmq:socket(Context, pub),
    ok = erlzmq:connect(Send, SubEndpt),
    {Recv, Send}.
