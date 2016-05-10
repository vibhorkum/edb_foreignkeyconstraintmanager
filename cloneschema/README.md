# EnterpriseDB Clone Schema

Perform copy of all objects and data in a designated local or remote schema into a local schema.

## Local Copy
###Usage:
#####Instructions:

1. Execute clonelocalschema.sql - 
    Above SQL will create a schema named edb_util that holds all functions.
2. While there are several helper functions, only one is needed to perform schema copy on a local server. 
    Set source & target schema names. There are two optional switches (both default to FALSE): verbose_bool tells the proc to display DDL as well as function names when TRUE; on_tblspace tells the function to attempt to create new objects on named tablespaces if these are used in the source schema. When FALSE, all objects are created on the local default schema.

FUNCTION edb_util.localcopyschema(
  source_schema_name text, target_schema_name text []
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean

I strongly recommend setting the following option if this is run from a psql prompt:
\set VERBOSITY terse

## Remote Copy

The remote copy runs against a foreign server defined with the postgres_fdw extension.
`CREATE EXTENSION postgres_fdw;`
