EXTENSION = edb_foreignkeyconstraintmanager
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
               
DATA = $(filter-out $(wildcard sqlapis/*--*.sql),$(wildcard sqlapis/*.sql))
PG_CONFIG = pg_config

sqlapis/$(EXTENSION)--$(EXTVERSION).sql: sqlapis/*.sql 
	cat $^ > $@

DATA = $(wildcard updates/*--*.sql) sqlapis/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = sqlapis/$(EXTENSION)--$(EXTVERSION).sql

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
