-module(geo_mind).

%% API
-export([lookup/1, lookup_many/1, to_code_country_city/1]).


lookup(IP) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup, IP}) end).

lookup_many(IPs) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup_many, IPs}) end).

to_code_country_city(Result) when is_map(Result) ->
  { geodata2_utils:country_code(Result),
    geodata2_utils:country_name(Result),
    geodata2_utils:city_name(Result)
  }.
