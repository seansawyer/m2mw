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

is_disconnect_test_() ->
    DisconnectMsg = <<"54c6755b-9628-40a4-9a2d-cc82a816345e 3 @* 17:{\"METHOD\":\"JSON\"},21:{\"type\":\"disconnect\"},">>,
    NormalMsg = <<"54c6755b-9628-40a4-9a2d-cc82a816345e 80 / 555:{\"PATH\":\"/\",\"x-forwarded-for\":\"127.0.0.1\",\"cache-control\":\"max-age=0\",\"accept-language\":\"en-US,en;q=0.8\",\"accept-encoding\":\"gzip,deflate,sdch\",\"connection\":\"keep-alive\",\"accept-charset\":\"ISO-8859-1,utf-8;q=0.7,*;q=0.3\",\"accept\":\"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\",\"user-agent\":\"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.142 Safari/535.19\",\"host\":\"localhost:6767\",\"cookie\":\"mochiweb_http=test_cookie\",\"METHOD\":\"GET\",\"VERSION\":\"HTTP/1.1\",\"URI\":\"/\",\"PATTERN\":\"/test\"},0:,">>,
    DisconnectReq = m2mw_util:parse_request(DisconnectMsg),
    NormalReq = m2mw_util:parse_request(NormalMsg),
    [{"Detects a disconnect properly",
      ?_assertMatch(true,
                    m2mw_util:is_disconnect(DisconnectReq))},
     {"Doesn't give a false positive",
      ?_assertMatch(false,
                    m2mw_util:is_disconnect(NormalReq))}].
      
