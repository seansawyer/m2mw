-module(m2mw_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, stop/0]).

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

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    ChildSpecs = [child(m2mw_handler, 6666),
                  child(m2mw_socket, 6666)],
    {ok, {{one_for_all, 5, 10}, ChildSpecs}}.

child(m2mw_handler, Port) ->
    {m2mw_handler, {m2mw_handler, start_link, [Port]},
        permanent, 5000, worker, [m2mw_handler]};
child(m2mw_socket, Port) ->
    {m2mw_socket, {m2mw_socket, start_link, [Port]},
        permanent, 5000, worker, [m2mw_socket]}.
