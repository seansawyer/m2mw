-module(m2mw_pair_sup).

-behaviour(supervisor).

%% API
-export([configure_handler/4,
         handler/1,
         socket/1,
         start_link/2,
         stop/1]).

%% Behaviour callbacks
-export([init/1]).

-define(CHILD(M, Args),
        {M, {M, start_link, Args}, permanent, 1000, worker, [M]}).

%% ===================================================================
%% API functions
%% ===================================================================

-spec configure_handler (pid(), nonempty_string(), nonempty_string(), fun())
                        -> ok.                                
%% @doc Configure the child `m2mw_handler' with the given `Pid' using the
%% supplied `Sub' and `Push' ZeroMQ endpoints and request handler fun `BodyFun'.
configure_handler(Pid, Sub, Push, BodyFun) ->
    ok = m2mw_handler:configure(handler(Pid), Sub, Push, BodyFun).

-spec handler (pid()) -> (pid()).
%% @doc Return the pid of the `m2mw_handler' child of the supervisor with
%% pid `Pid'.
handler(Pid) ->
    child(Pid, m2mw_handler).

-spec socket (pid()) -> (pid()).
%% @doc Return the pid of the `m2mw_socket' child of the supervisor with
%% pid `Pid'.
socket(Pid) -> 
    child(Pid, m2mw_socket).

-spec start_link (erlzmq:erlzmq_context(), pos_integer())
                 -> {ok, pid()} | {error, Reason::term()}.
start_link(Context, Port) ->
    supervisor:start_link(?MODULE, [Context, Port]).

-spec stop (pid()) -> true.
stop(Pid) ->
    exit(Pid, shutdown).

%% ===================================================================
%% Behaviour callbacks
%% ===================================================================

-spec init ([pos_integer()]) -> supervisor:child_spec().
init([Context, Port]) ->
    Specs = [?CHILD(m2mw_socket, [Port, self()]),
             ?CHILD(m2mw_handler, [Context, Port, self()])],
    {ok, {{one_for_all, 5, 10}, Specs}}.

%% ===================================================================
%% Support functions
%% ===================================================================

-spec child(pid(), m2mw_handler|m2mw_socket) -> pid() | nil.
child(Pid, Id) ->
    case lists:keyfind(Id, 1, supervisor:which_children(Pid)) of
        {Id, HandlerPid, _, _} ->
            HandlerPid;
        _ ->
            nil 
    end.
