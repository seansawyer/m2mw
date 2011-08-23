-module(m2mw_app_tests).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    m2mw:start(),
    Sub = "tcp://127.0.0.1:9998",
    Push = "tcp://127.0.0.1:9999",
    BodyFun = fun() -> "Hello" end,
    mochiweb_http:start([{ip, "127.0.0.1"}, {port, 8080}, {loop, BodyFun}]),
    application:start(m2mw),
    m2mw_sup:configure_handlers(Sub, Push, BodyFun).

cleanup(_Pid) ->
    application:stop(m2mw).

proxy_test_() ->
    { foreach,
      fun setup/0,
      fun cleanup/1,
      [
          fun proxy_test_1/0
      ] }.

proxy_test_1() ->
    ok.
