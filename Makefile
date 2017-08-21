PROJECT = geo_mind
PROJECT_DESCRIPTION = App for maintaining valid maxmind db, in memory (ets).
PROJECT_VERSION = 0.1.0

DEPS += geodata2_lib hackney poolboy lager

dep_geodata2_lib = git https://github.com/orotemo/geodata2_lib master

include erlang.mk
