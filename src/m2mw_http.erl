-module(m2mw_http).

-export([collect_resp/1,
         construct_req/1]).

-include_lib("m2mw.hrl").

-define(TIMEOUT_HEADERS, 300000).
-define(TIMEOUT_RESPONSE, 30000).

%% ===================================================================
%% API
%% ===================================================================

collect_resp(MwSock) ->
    unicode:characters_to_binary(lists:reverse(collect_resp(MwSock, []))).

construct_req(#req{headers=Headers, body=Body}) ->
    {struct, HeadersPl} = mochijson2:decode(Headers),
    Method = proplists:get_value(<<"METHOD">>, HeadersPl),
    Uri = proplists:get_value(<<"URI">>, HeadersPl),
    Vsn = proplists:get_value(<<"VERSION">>, HeadersPl),
    RequestLine = io_lib:format("~s ~s ~s\r\n", [Method, Uri, Vsn]),
    %% We assume that expect header is handled by Mongrel2, so we redact it here
    %% to prevent duplicate 100s, etc.
    HeadersPl1 = proplists:delete(<<"expect">>, HeadersPl),
    HeaderLines = [io_lib:format("~s: ~s\r\n", [K,V]) || {K,V} <- HeadersPl1],
    iolist_to_binary([RequestLine, HeaderLines, "\r\n", Body]).

%% ===================================================================
%% Support functions
%% ===================================================================

collect_resp(MwSock, Lines) ->
    case gen_tcp:recv(MwSock, 0, ?TIMEOUT_RESPONSE) of
        {ok, {http_response, {VsnMaj, VsnMin}, Code, Msg}} ->
            inet:setopts(MwSock, [{packet, httph}]),
            ResponseLine = io_lib:format("HTTP/~b.~b ~b ~s\r\n",
                                         [VsnMaj, VsnMin, Code, Msg]),
            collect_resp_headers(MwSock, [ResponseLine|Lines]);
        {ok, {http_error, "\r\n"}} ->
            collect_resp_headers(MwSock, Lines);
        {ok, {http_error, "\n"}} ->
            collect_resp_headers(MwSock, Lines);
        {error, closed} ->
            ok = gen_tcp:close(MwSock),
            Lines;
        {error, timeout} ->
            metal:error("Timed out waiting on response from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for response line:~n~p~n", [Other]),
            ok = gen_tcp:close(MwSock),
            Lines
    end.

collect_resp_headers(MwSock, Lines) ->
    collect_resp_headers(MwSock, Lines, undefined).

collect_resp_headers(MwSock, Lines, ContentLength) ->
    case gen_tcp:recv(MwSock, 0, ?TIMEOUT_HEADERS) of
        {ok, http_eoh} ->
            % body is next
            inet:setopts(MwSock, [{packet, raw}]),
            collect_resp_body(MwSock, ["Connection: close\r\n"|Lines], ContentLength);
        {ok, {http_header, _, 'Content-Length', _, Value}} ->
            HeaderLine = io_lib:format("Content-Length: ~s\r\n", [Value]),
            collect_resp_headers(MwSock, [HeaderLine|Lines], list_to_integer(Value));
        {ok, {http_header, _, Name, _, Value}} ->
            HeaderLine = io_lib:format("~s: ~s\r\n", [Name, Value]),
            collect_resp_headers(MwSock, [HeaderLine|Lines], ContentLength);
        {error, closed} ->
            ok = gen_tcp:close(MwSock),
            Lines;
        {error, timeout} ->
            metal:error("Timed out waiting on headers from Mochiweb"),
            ok = gen_tcp:close(MwSock),
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for header:~n~p~n", [Other]),
            ok = gen_tcp:close(MwSock),
            Lines
    end.

collect_resp_body(MwSock, Lines, ContentLength) ->
    collect_resp_body(MwSock, ["\r\n"|Lines], ContentLength, 0).

collect_resp_body(MwSock, Lines, undefined, _) ->
    metal:debug("No content length was specified; sending empty response."),
    ok = gen_tcp:close(MwSock),
    Lines;
collect_resp_body(MwSock, Lines, ContentLength, Read) when Read >= ContentLength ->
    ok = gen_tcp:close(MwSock),
    Lines; 
collect_resp_body(MwSock, Lines, ContentLength, NRead) ->
    Lines1 = case gen_tcp:recv(MwSock, 0, ?TIMEOUT_RESPONSE) of
        {ok, Data} ->
            NRead1 = NRead + erlang:size(Data),
            collect_resp_body(MwSock, [Data|Lines], ContentLength, NRead1);
        {error, closed}  ->
            Lines; 
        {error, timeout} ->
            Lines;
        Other ->
            % really should handle an invalid request here
            metal:error("Unexpected value recv'd for body:~n~p~n", [Other]),
            Lines
    end,
    ok = gen_tcp:close(MwSock),
    Lines1.
