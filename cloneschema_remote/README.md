# EnterpriseDB Clone Schema
## Remote Schema Copy for EDB Postgres Advanced Server

This package provides functionality to deep copy a complete schema, including: tables, table data, indexes, functions, packages, procedures, sequences, data types, and all other objects from a schema on a specified remote server to a target schema on the local server.

### Prerequisites

The following two extensions must already be installed on the local server:
* dblink
* postgres_fdw

```
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE EXTENSION IF NOT EXISTS dblink;
```

The remotecopyschema function expects a foreign server to be defined, with a user bound to the server.

In this example we create a foreign server, with a hypothetical db named targetdb and a local role (`target`) that is bound to a remote role (`ima_user`) on the remote server. The remote role must have read access to the source schema and system catalogs.

```
CREATE SERVER a_foreign_server FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (hostaddr '10.0.0.1', dbname 'targetdb')
;
CREATE ROLE target LOGIN PASSWORD 'target-pass'
;
CREATE USER MAPPING FOR target SERVER a_foreign_server
  OPTIONS (user 'ima_user', password 'some-password')
;
GRANT USAGE ON FOREIGN SERVER a_foreign_server TO target
;
```

### Usage

The function has the following definition:
```
CREATE OR REPLACE FUNCTION edb_util.remotecopyschema(
  foreign_server_name text
  , source_schema_name text, target_schema_name text
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
```

 `SELECT edb_util.remotecopyschema('a_foreign_server', 'source','target');`

Because the function raises nested NOTICE messages that provide additional CONTEXT messages to the screen, I strongly recommend setting the following option when running this from a psql prompt: `\set VERBOSITY terse`

There are two optional switches: `verbose_bool` tells the function to display DDL as well as function names when TRUE; `on_tblspace` tells the function to attempt creating objects on named tablespaces if these are used in the source schema. The function will exit without performing any action and return FALSE if any named tablespaces are not present on the local server. When set FALSE, all creates happen on the local default tablespace.
