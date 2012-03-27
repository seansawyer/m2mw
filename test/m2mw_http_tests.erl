-module(m2mw_http_tests).

-include_lib("eunit/include/eunit.hrl").

construct_http_req_test_() ->
    F = fun m2mw_http:construct_req/1,
    ZmqMsgExpect = <<"HSALSelohcnysHSALS-elohcnys-redrawrof 140 /foo/4f4ce03d8a1dc75c580000a6 340:{\"PATH\":\"\/foo\/4f4ce03d8a1dc75c580000a6\",\"x-forwarded-for\":\"10.68.21.199\",\"content-type\":\"application\/json\",\"expect\":\"100-continue\",\"connection\":\"close\",\"accept-encoding\":\"deflate, gzip\",\"content-length\":\"15\",\"accept\":\"*\/*\",\"host\":\"somehost.com\",\"METHOD\":\"PUT\",\"VERSION\":\"HTTP\/1.1\",\"URI\":\"\/foo\/f4ce03d8a1dc75c580000a6\",\"PATTERN\":\"\/pattern\/\"},15:{\"name\":\"m2mw\"},">>,
    ZmqMsgNoExpect = <<"HSALSelohcnysHSALS-elohcnys-redrawrof 140 /foo/4f4ce03d8a1dc75c580000a6 316:{\"PATH\":\"\/foo\/4f4ce03d8a1dc75c580000a6\",\"x-forwarded-for\":\"10.68.21.199\",\"content-type\":\"application\/json\",\"connection\":\"close\",\"accept-encoding\":\"deflate, gzip\",\"content-length\":\"15\",\"accept\":\"*\/*\",\"host\":\"somehost.com\",\"METHOD\":\"PUT\",\"VERSION\":\"HTTP\/1.1\",\"URI\":\"\/foo\/f4ce03d8a1dc75c580000a6\",\"PATTERN\":\"\/pattern\/\"},15:{\"name\":\"m2mw\"},">>,
    HttpReq = <<"PUT /foo/f4ce03d8a1dc75c580000a6 HTTP/1.1\r\nPATH: /foo/4f4ce03d8a1dc75c580000a6\r\nx-forwarded-for: 10.68.21.199\r\ncontent-type: application/json\r\nconnection: close\r\naccept-encoding: deflate, gzip\r\ncontent-length: 15\r\naccept: */*\r\nhost: somehost.com\r\nMETHOD: PUT\r\nVERSION: HTTP/1.1\r\nURI: /foo/f4ce03d8a1dc75c580000a6\r\nPATTERN: /pattern/\r\n\r\n{\"name\":\"m2mw\"}">>,
    [{"constructs a request with the Expect header redacted when present",
      ?_assertMatch(HttpReq, F(m2mw_util:parse_request(ZmqMsgExpect)))},
     {"constructs the same request when the Expect header is not present",
      ?_assertMatch(HttpReq, F(m2mw_util:parse_request(ZmqMsgNoExpect)))}].
