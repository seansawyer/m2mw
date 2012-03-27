-module(m2mw_sup).

-behaviour(supervisor).

%% API
-export([configure_handlers/3,
         start_link/0,
         stop/0]).

%% Supervisor callbacks
-export([init/1]).

-define(CHILD(Mod, Port, Type),
        {{Mod, Port}, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    {ok, Context} = erlzmq:context(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Context]).

stop() ->
    exit(whereis(?MODULE), shutdown).

configure_handlers(Sub, Push, BodyFun) ->
    PairSups = supervisor:which_children(?MODULE),
    F = fun({_,Pid,_,_}) ->
                m2mw_pair_sup:configure_handler(Pid, Sub, Push, BodyFun)
        end,
    lists:foreach(F, PairSups).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([Context]) ->
    init(Context, application:get_env(port_lo), application:get_env(port_hi)).

%% ===================================================================
%% Support functions
%% ===================================================================

init(Context, {ok, PortLo}, {ok, PortHi})
  when is_integer(PortLo),
       is_integer(PortHi),
       PortLo =< PortHi ->
    {ok, {{one_for_one, 5, 10}, child_specs(Context, PortLo, PortHi)}};
init(Context, _, _) ->
    erlzmq:term(Context, 1000),
    {error, invalid_port_range}.

child_specs(Context, StartPort, EndPort) ->
    child_specs(Context, StartPort, EndPort, []).

child_specs(_, StartPort, EndPort, Children) when StartPort > EndPort ->
    Children;
child_specs(Context, StartPort, EndPort, Children) ->
    [child_spec(m2mw_pair_sup, Context, StartPort)|
     child_specs(Context, StartPort+1, EndPort, Children)].

child_spec(m2mw_pair_sup, Context, Port) ->
    {Port, {m2mw_pair_sup, start_link, [Context, Port]},
     permanent, 1000, supervisor, [m2mw_pair_sup]}.
