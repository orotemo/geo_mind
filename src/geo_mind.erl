-module(geo_mind).
-behaviour(gen_server).

-export([start_link/1,
         lookup/1,
         lookup_many/1,
         refresh_db/0,
         to_code_country_city/1]).

-define(TIMEOUT, 300).
-define(DB_FILENAME, <<"GeoLite2-City.mmdb.gz">>).
-define(ETAG_FILENAME, <<"etag.txt">>).
-define(SECONDS_A_DAY, 86400).
-define(MILLION, 1000000).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).


%%%%%%%%%%%  API  %%%%%%%%%%%
%%%
start_link(Config) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE,[Config], []).

lookup(IPs) when is_list(IPs) ->
  case lookup_many(IPs) of
    {_IP, Result} -> Result;
    not_found -> not_found
  end;

lookup(IP) when is_binary(IP) ->  lookup([IP]).

lookup_many([]) -> not_found;
lookup_many(IPs) when is_list(IPs) ->
  case ets:lookup(?MODULE, maxmind_data) of
    [{maxmind_data, undefined}] -> undefined;
    [{maxmind_data, Data}] -> do_lookup(not_found, Data, IPs)
  end.

to_code_country_city(Result) when is_map(Result) ->
  { geodata2_utils:country_code(Result),
    geodata2_utils:country_name(Result),
    geodata2_utils:city_name(Result)
  }.

refresh_db() -> gen_server:cast(?MODULE, refresh_db).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================


init([#{refresh_freq := RefreshFreqInDays, downloads_dir := DbDir} = Config]) ->
  ets:new(?MODULE, [set, named_table, public]),
  ets:insert(?MODULE, [ {maxmind_data, undefined} ]),

  refresh_db(),

  ETagPath = filename:join(DbDir, ?ETAG_FILENAME),

  Config1 = case file:read_file(ETagPath) of
              {ok, ETag} -> Config#{etag => ETag};
              _ -> Config
            end,

  {ok, Config1#{refresh_freq => RefreshFreqInDays * ?SECONDS_A_DAY,
                database_path => db_location(DbDir),
                etag_path => ETagPath
               }}.


handle_call({lookup, Data, IP}, _From, State) ->
  Result = geodata2_lib:lookup(Data, IP),
  {reply, Result, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(refresh_db, State) ->
  {noreply, handle_refresh_db(State)};

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(refresh_db, State) ->
  {noreply, handle_refresh_db(State)};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%%%%%%%%% PRIVATE %%%%%%%%%%%%

db_location(BaseDir) -> filename:join(BaseDir, ?DB_FILENAME).

do_lookup(Res, _Data, []) -> Res;
do_lookup(not_found, Data, [IP | IPs]) ->
  case geodata2_lib:lookup(Data, IP) of
    not_found -> do_lookup(not_found, Data, IPs);
    {ok, Res} -> {IP, Res}
  end.

handle_refresh_db(#{ database_path := DbPath,
                     refresh_freq := RefreshFreqInSec} = State) ->
  error_logger:info_msg("Refreshing db with state: ~p~n", [State]),

  State1 = cancel_and_new_timer(State, RefreshFreqInSec * 1000),
  do_db_refresh(geodata2_lib:load(DbPath), State1).

cancel_and_new_timer(#{timer_ref := TimerRef} = State, Timeout) ->
  erlang:cancel_timer(TimerRef),
  State#{ timer_ref => erlang:send_after(Timeout, self(), refresh_db) };

cancel_and_new_timer(State, Timeout) ->
  State#{ timer_ref => erlang:send_after(Timeout, self(), refresh_db) }.

do_db_refresh({ok, Data},
              #{refresh_freq := RefreshFreq,
                database_path := DbPath } = State) ->
  case maybe_refresh(Data, RefreshFreq) of
    true ->
      Res = fetch_db(DbPath, State),
      handle_fetch_result(has_file, DbPath, State, Res);
    {false, NextCheck} ->
      save_to_ets(Data),
      cancel_and_new_timer(State, NextCheck * 1000)
  end;

do_db_refresh({error, _}, #{ database_path := DbPath } = State) ->
  Res = fetch_db(DbPath, State),
  handle_fetch_result(no_file, DbPath, State, Res).

fetch_db(DbPath,
         #{etag := ETag, etag_path := ETagPath, db_download_url := DbURL}) ->
  Headers = [{<<"If-None-Match">>, ETag}],
  on_db_fetch(DbPath, ETagPath, DbURL, hackney:get(DbURL, Headers));

fetch_db(DbPath, #{etag_path := ETagPath, db_download_url := DbURL}) ->
  on_db_fetch(DbPath, ETagPath, DbURL, hackney:get(DbURL)).

on_db_fetch(DbPath, ETagPath, _DbURL, {ok, 200, HeadersList, Response}) ->
  Headers = maps:from_list(HeadersList),

  case hackney:body(Response) of
    {ok, Body} ->
      file:write_file(DbPath, Body),

      case maps:get(<<"ETag">>, Headers, undefined) of
        undefined -> ok;
        ETag -> file:write_file(ETagPath, ETag)
      end,

      error_logger:info_msg("New maxmind db written to: ~p~n."
                            "DB size is ~pMB~n",
                            [ DbPath, round( byte_size(Body)/?MILLION ) ]),
      {ok, cache_instructions(Headers)};
    {error, Err} ->
      error_logger:error_msg("Failed to get body: ~p~n."
                             "fetch succeeded with headers ~p~n",
                             [Err, Headers]),
      error
  end;

on_db_fetch(_DbPath, _ETagPath, DbURL, {ok, 304, _HeadersList, Response}) ->
  hackney:body(Response), % to release the hackney handle
  error_logger:info_msg("fetching ~p returned 304.~n", [DbURL]),
  {ok, #{}};

on_db_fetch(_DbPath, _, DbURL, {error, Err}) ->
  error_logger:error_msg("An error occurred getting ~p using hackney: ~p~n",
                         [DbURL, Err]),
  error;

on_db_fetch(_DbPath, _, DbURL, Err) ->
  error_logger:error_msg("An unknown error occurred getting"
                         " ~p using hackney: ~p~n",
                         [DbURL, Err]),
  error.

save_to_ets(Data) -> ets:insert(?MODULE, [ {maxmind_data, Data} ]).

maybe_refresh(Data, RefreshFreq) ->
  AgeInSeconds = geodata2_lib:db_age(Data),
  error_logger:info_msg("Database age in seconds: ~p~n", [AgeInSeconds]),

  case AgeInSeconds > RefreshFreq of
    true -> true;
    false ->
      NextCheck = RefreshFreq - AgeInSeconds,
      { false, NextCheck }
  end.

cache_instructions(#{<<"Cache-Control">> := CacheControl,
                     <<"ETag">> := ETag
                    }) ->

  case parse_max_age(CacheControl) of
    undefined -> #{ etag => ETag };
    MaxAge -> #{ max_age => MaxAge, etag => ETag }
  end;

cache_instructions(Headers) ->
  error_logger:error_msg("Headers from maxmind don't match expected. got: ~p~n",
                        [Headers]),
  #{}.

handle_fetch_result(has_file, DbPath, State, FetchResult) ->
  {ok, Data} = geodata2_lib:load(DbPath),
  save_to_ets(Data),

  case FetchResult of
    {ok, CacheHeaders} -> maps:merge(State, CacheHeaders);
    _ -> State
  end;

handle_fetch_result(no_file, DbPath, State, {ok, CacheHeaders}) ->
  {ok, Data} = geodata2_lib:load(DbPath),
  save_to_ets(Data),
  maps:merge(State, CacheHeaders);

handle_fetch_result(no_file, _, State, error) ->
  cancel_and_new_timer(State, 60000).

parse_max_age(CacheControl) when is_binary(CacheControl)->
  case re:split(CacheControl,
                <<".*max-age=([1-9][0-9]*).*">>,
                [{return, binary}, trim]) of
    [<<>>, MaxAgeStr] -> list_to_integer(binary_to_list(MaxAgeStr));
    _ -> undefined
  end;
parse_max_age(_CacheControl) -> undefined.
