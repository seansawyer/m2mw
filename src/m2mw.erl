-module(m2mw).

-export([start/0]).

-define(DEPS, [inets, crypto, public_key, ssl, mochiweb]).

start() ->
    lists:foreach(fun ensure_started/1, ?DEPS),
    ensure_started(m2mw).

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.
