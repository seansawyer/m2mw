-module(m2mw_sup).

-behaviour(supervisor).

%% API
-export([configure_handlers/3, handler/1, socket/1, start_link/0, stop/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop() ->
    exit(whereis(?MODULE), shutdown).

configure_handlers(Sub, Push, BodyFun) ->
    Kids = supervisor:which_children(m2mw_sup),
    Handlers = [Pid || {_,Pid,_,[Mod]} <- Kids, Mod =:= m2mw_handler],
    lists:foreach(fun(HPid) ->
                      ok = m2mw_handler:configure(HPid, Sub, Push, BodyFun)
                  end, Handlers).

handler(Port) ->
    child(m2mw_handler, Port).

socket(Port) -> 
    child(m2mw_socket, Port).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, PortLo} = application:get_env(port_lo),
    {ok, PortHi} = application:get_env(port_hi),
    init(PortLo, PortHi).

%% ===================================================================
%% Support functions
%% ===================================================================

init(PortLo, PortHi) when is_integer(PortLo),
                          is_integer(PortHi),
                          PortLo =< PortHi ->
    (PortHi < PortLo) andalso erlang:error(badarg),
    {ok, {{one_for_one, 5, 10}, child_specs(PortLo, PortHi)}}.

-spec child(m2mw_handler|m2mw_socket, pos_integer()) -> pid() | nil.
child(Mod, Port) ->
    case lists:keyfind({Mod, Port}, 1, supervisor:which_children(m2mw_sup)) of
        {{Mod, Port}, Pid, _, _} ->
            Pid;
        _ ->
            nil 
    end.

child_specs(StartPort, EndPort) ->
    child_specs(StartPort, EndPort, []).

child_specs(StartPort, EndPort, Children) when StartPort > EndPort ->
    Children;
child_specs(StartPort, EndPort, Children) ->
    [child_spec(m2mw_handler, StartPort),
     child_spec(m2mw_socket, StartPort) |
     child_specs(StartPort+1, EndPort, Children)].

child_spec(m2mw_handler, Port) ->
    {{m2mw_handler, Port}, {m2mw_handler, start_link, [Port]},
        permanent, 1000, worker, [m2mw_handler]};
child_spec(m2mw_socket, Port) ->
    {{m2mw_socket, Port}, {m2mw_socket, start_link, [Port]},
        permanent, 1000, worker, [m2mw_socket]}.
