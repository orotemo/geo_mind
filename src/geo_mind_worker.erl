-module(geo_mind_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).

%% API
-export([start_link/1]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

%% API.

start_link(Config) -> gen_server:start_link(?MODULE, [Config], []).

%% gen_server.

init([#{worker_refresh_freq := WorkerRefreshFreqInHours} = Config]) ->
  State = Config#{
    timer_ref => erlang:send_after(1, self(), refresh),
    db => undefined
  },

  FreqInMillis = WorkerRefreshFreqInHours * 60 * 60 * 1000,
  {ok, maps:put(worker_refresh_freq, FreqInMillis, State)}.

%%%%%% GEN_SERVER HANDLERS %%%%%%%%%%%%%

handle_call({lookup, IPs}, _From, State) when is_list(IPs) ->
  case handle_call({lookup_many, IPs}, _From, State) of
    {_IP, Result} -> {reply, Result, State};
    Else -> {reply, Else, State}
  end;

handle_call({lookup, IP}, _From, State) when is_binary(IP) ->
  handle_call({lookup, [IP]}, _From, State);

handle_call({lookup_many, []}, _From, State) ->
  {reply, not_found, State};

handle_call({lookup_many, IPs}, _From, #{db := DB} = State) ->
  case DB of
    undefined -> {reply, undefined, State};
    DB -> {reply, do_lookup(not_found, DB, IPs), State}
  end.


handle_info(refresh, State) ->
  #{worker_refresh_freq := Freq, timer_ref := TimerRef} = State,
  erlang:cancel_timer(TimerRef),

  case geo_mind_loader:get_db() of
    {ok, DB} ->
      State1 = State#{
        timer_ref => erlang:send_after(Freq, self(), refresh),
        db => DB
      },

      {noreply, State1#{db => DB}};
    _ ->
      State1 = State#{
        timer_ref => erlang:send_after(1000, self(), refresh)
      },

      {noreply, State1}
  end;

handle_info(_Info, State) -> {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.


%% internal

do_lookup(Res, _Data, []) -> Res;
do_lookup(not_found, Data, [IP | IPs]) ->
  case geodata2_lib:lookup(Data, IP) of
    not_found -> do_lookup(not_found, Data, IPs);
    {ok, Res} -> {IP, Res};
    Else ->
      error_logger:warning_msg("Got ~p with IP ~p~n", [Else, IP]),
      do_lookup(not_found, Data, IPs)
  end.