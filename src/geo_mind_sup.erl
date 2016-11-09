-module(geo_mind_sup).
-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

start_link(Config) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, Config).

init(Config) ->

  Procs = [ geo_mind_spec(Config) ],
  {ok, {{one_for_one, 1, 5}, Procs}}.

geo_mind_spec(Config) ->
  #{id => geo_mind_loader, start => {geo_mind, start_link, [Config]}}.
