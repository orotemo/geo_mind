-module(geo_mind).

%% API
-export([lookup/1, lookup_many/1, to_details/1]).


lookup(IP) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup, IP}) end).

lookup_many(IPs) ->
  poolboy:transaction(geo_mind_pool,
    fun(Worker) -> gen_server:call(Worker, {lookup_many, IPs}) end).

to_details(Result) when is_map(Result) ->
  #{geodata_continent =>
      geodata2_utils:map_search([<<"continent">>, <<"code">>], Result),
    geodata_counry => geodata2_utils:country_code(Result),
    geodata_code => geodata2_utils:country_name(Result),
    geodata_city => geodata2_utils:city_name(Result),
    location => geodata2_utils:map_search([<<"location">>], Result)
  }.
