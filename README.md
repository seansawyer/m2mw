This is a Mongrel2 handler for Mochiweb applications. It is a hack.

## A hack? ##

Yes. It receives messages from ZeroMQ, unpacks them, sends them to Mochiweb
using a local TCP socket, collects the response from Mochiweb, and forwards
whatever it receives to ZeroMQ.

Chunked encoding is not supported.

## How to use it ##

Install [ZeroMQ](http://www.zeromq.org/) and [Mongrel2](http://mongrel2.org/).

Add the following to the `deps` list in your Rebar config file:

    {'m2mw', ".*", {git, "git://github.com/seansawyer/m2mw", "master"}}

Now you'll need to start Mongrel2. An example `mongrel2.conf` file that will
work with this example is included in this project. To start Mongrel2 using this
file, `cd` to the root of this project and issue the following commands:

    mkdir run
    m2sh load
    m2sh start -name main

First, if you want to see some logging, enable a log backend for
[Metal](/seansawyer/metal). I use `metal_error_logger` in this
example to avoid any additional dependencies, but I suggest you use
[Lager](/basho/lager):

    application:set_env(metal, log_backend, metal_error_logger).

Then start your Mochiweb application - something like:

    mochiweb_http:start([{ip, "127.0.0.1"}, {port, 8080}, {loop, {mochiweb_http, default_body}}]),

All that remains is to tell the handler about your endpoints and the function
you passed to Mochiweb to handle requests (a fun, {M,F} or {M,F,A}), and then
tell it to start receiving:

    application:start(m2mw),
    m2mw_sup:configure_handlers("tcp://127.0.0.1:9998", "tcp://127.0.0.1:9999", {mochiweb_http, default_body}).

Obviously your endpoints and function will be different IRL, but you get the
idea. If you just want a quick demo, start Mongrel2 and take a look at
`m2mw_util:test_mochiweb/0` or `m2mw_util:test_mochiweb/1`.

The Mochiweb proxy socket runs on port 9716. Sorry, that's not configurable
at the moment.

You should now be able to make requests to your Mongrel2 instance and have them
serviced by Mochiweb over ZeroMQ. Try navigating to http://localhost:6767/ to
test.

## Using m2mw with Webmachine ##

All you need to do is supply the following {M,F} as your loop function in your
call to `m2mw_sup:configure_handlers/3`:

    {webmachine_mochiweb, loop}
