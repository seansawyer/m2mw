This is a Mongrel2 handler for Mochiweb applications. It is a hack.

## A hack? ##

Yes. It receives messages from ZeroMQ, unpacks them, sends them to Mochiweb
using a local TCP socket, collects the response from Mochiweb, and forwards
whatever it receives to ZeroMQ.

Chunked encoding is not supported.

## How to use it ##

Install [ZeroMQ](http://www.zeromq.org/) and [Mongrel2](http://mongrel2.org/).

Add the following to the `deps` list in your Rebar config file:

    {'m2mw', ".*", {git, "git://github.com/vitrue/m2mw", "master"}}

Now you'll need to start Mongrel2. An example `mongrel2.conf` file that will
work with this example is included in this project. To start Mongrel2 using this
file, `cd` to the root of this project and issue the following commands:

    mkdir run
    m2sh load
    m2sh start -name main

Lets assume that you've started your Mochiweb application like so:

    mochiweb_http:start([{ip, "127.0.0.1"}, {port, 8080}, {loop, {mochiweb_http, default_body}}]),

All that remains is to tell the handler about your endpoints and the function
you passed to Mochiweb to handle requests (a fun, {M,F} or {M,F,A}), and then
tell it to start receiving:

    application:start(m2mw),
    m2mw_handler:configure("tcp://127.0.0.1:9998", "tcp://127.0.0.1:9999", {mochiweb_http, default_body}).

Obviously your endpoints and function will be different, but you get the idea.

The Mochiweb proxy socket runs on port 9716. Sorry, that's not configurable
at the moment.

You should now be able to make requests to your Mongrel2 instance and have them
serviced by Mochiweb over ZeroMQ. Try navigating to http://localhost:6767/ to
test.

## Using m2mw with Webmachine ##

All you need to do is supply the following {M,F} as your loop function in your
call to `m2mw_handler:configure/3`:

    {webmachine_mochiweb, loop}

## License ##

Copyright 2011 Vitrue, LLC. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY VITRUE "AS IS" AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL VITRUE OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of Vitrue.
