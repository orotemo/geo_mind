-module(geo_mind).

%% API
-export([lookup/1, lookup_many/1]).


lookup(IP) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup, IP}) end).

lookup_many(IPs) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup_many, IPs}) end).