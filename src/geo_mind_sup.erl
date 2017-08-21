-module(geo_mind_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

start_link(Config) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, Config).

init(Config) ->
  Procs = [ loader_spec(Config), pool_spec(Config) ],
  {ok, {{one_for_one, 1, 5}, Procs}}.

loader_spec(Config) ->
  #{id => geo_mind_loader, start => {geo_mind_loader, start_link, [Config]}}.


pool_spec(Config) ->
  PoolSize = application:get_env(geo_ming_pool, pool_size, 5),

  poolboy:child_spec(
    geo_mind_pool,
    [{name, {local, geo_mind_pool}},
      {worker_module, geo_mind_worker},
      {size, PoolSize},
      {max_overflow, 0}
    ],
    Config
  ).