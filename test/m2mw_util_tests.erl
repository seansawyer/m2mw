-module(m2mw_util_tests).

-include_lib("m2mw.hrl").

-include_lib("eunit/include/eunit.hrl").

compose_netstring_test_() ->
    F = fun m2mw_util:compose_netstring/1,
    HelloRussianWorld = [1055,1088,1080,1074,1077,1090,32,1084,1080,1088,33],
    HelloRussianBinary = unicode:characters_to_binary(HelloRussianWorld),
    HelloRussianSize = size(HelloRussianBinary),
    [{"An empty string",
      ?_assertMatch(<<"0:,">>, F(""))},
     {"An empty binary",
      ?_assertMatch(<<"0:,">>, F(<<>>))},
     {"An ASCII string",
      ?_assertMatch(<<"12:Hello world!,">>, F("Hello world!"))},
     {"An ASCII binary",
      ?_assertMatch(<<"12:Hello world!,">>, F(<<"Hello world!">>))},
     {"A UTF-8 binary",
      fun() ->
          Expected = iolist_to_binary([integer_to_list(HelloRussianSize), ":",
                                       HelloRussianBinary, ","]),
          ?assertMatch(Expected, F(HelloRussianBinary))
      end}].
