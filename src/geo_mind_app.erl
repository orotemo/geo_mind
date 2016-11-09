-module(geo_mind_app).
-behaviour(application).

-define(DB_DOWNLOAD_URL, <<"http://geolite.maxmind.com/download/geoip/database"
                           "/GeoLite2-City.mmdb.gz">>).
-export([start/2]).
-export([stop/1]).

start(_Type, _Args) ->
  RefreshFreq = application:get_env(geo_mind, refresh_freq, 10), %in days
  DownloadsDir = application:get_env(geo_mind,
                                     downloads_dir,
                                     <<"/tmp/geo_mind">>),
  DbDownloadUrl = application:get_env(geo_mind, db_url, ?DB_DOWNLOAD_URL),

  ok = filelib:ensure_dir(DownloadsDir),

  geo_mind_sup:start_link(#{ refresh_freq => RefreshFreq,
                             downloads_dir => DownloadsDir,
                             db_download_url => DbDownloadUrl
                           }).

stop(_State) -> ok.

