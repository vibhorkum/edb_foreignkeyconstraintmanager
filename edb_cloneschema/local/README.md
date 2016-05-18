# EnterpriseDB Clone Schema Extension
## Local Schema Copy for EDB Postgres Advanced Server

This package provides functionality to deep copy a complete schema, including: tables, table data, indexes, functions, packages, procedures, sequences, data types, and all other objects from a specified source schema to a designated local target schema.

Because the function raises nested NOTICE messages that provide additional CONTEXT messages to the screen, I strongly recommend setting the following option when running this from a psql prompt: `\set VERBOSITY terse`

### Usage

The function has the following definition:
```
CREATE OR REPLACE FUNCTION edb_util.localcopyschema(
  source_schema_name text, target_schema_name text []
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
```

`SELECT edb_util.localcopyschema('source', ARRAY ['target']);`

There are two optional switches: `verbose_bool` tells the function to display DDL as well as function names when TRUE; `on_tblspace` tells the function to attempt creating objects on named tablespaces if these are used in the source schema. When set FALSE, all creates happen on the local default tablespace.
