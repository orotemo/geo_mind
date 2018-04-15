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
  #{continent_code =>
      geodata2_utils:map_search([<<"continent">>, <<"code">>], Result),
    continent_name =>
      geodata2_utils:map_search([<<"continent">>, <<"names">>, <<"en">>],
                                Result),
    country_code => geodata2_utils:country_code(Result),
    country_name => geodata2_utils:country_name(Result),
    city_name => geodata2_utils:city_name(Result),
    location => geodata2_utils:map_search([<<"location">>], Result)
  }.
