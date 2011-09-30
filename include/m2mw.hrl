
-compile([{parse_transform, metal_transform}]).

-record(req, {uuid         :: binary(),
              id           :: binary(),
              path         :: binary(),
              headers_size :: integer(),
              headers      :: binary(),
              body_size    :: integer(),
              body         :: binary()}).
