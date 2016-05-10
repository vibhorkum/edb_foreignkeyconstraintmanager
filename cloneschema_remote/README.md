# Remote Schema Clone API

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

```
CREATE SERVER a_foreign_server FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (hostaddr '10.0.0.1', dbname 'targetdb')
;
CREATE ROLE target LOGIN PASSWORD 'target-pass'
;
CREATE USER MAPPING FOR target SERVER a_foreign_server
  OPTIONS (user 'i_am_a_user', password 'some-password')
;
GRANT USAGE ON FOREIGN SERVER a_foreign_server TO target
;
```

### Usage

The function has the following definition: ```
CREATE OR REPLACE FUNCTION edb_util.remotecopyschema(
  foreign_server_name text
  , source_schema_name text, target_schema_name text
  , verbose_bool boolean DEFAULT FALSE
  , on_tblspace boolean DEFAULT FALSE
)
RETURNS boolean
```

And can be run `SELECT edb_util.remotecopyschema('a_foreign_server', 'source','target');`

The optional boolean parameters are: verbose_bool which displays the full object declarations to the screen, and on_tblspace which creates objects in the same tablespaces they appear on at the remote server. If on_tblspace is TRUE, and the local server does not have matching tablespace names created, the function will exit without performing any action, and return FALSE.

It is strongly recommended to set the following option at the psql prompt to prevent CONTEXT messages from overwhelming the user.
`\set VERBOSITY terse`
