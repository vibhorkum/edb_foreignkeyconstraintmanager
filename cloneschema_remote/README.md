# Remote Schema Clone API

This package provides functionality to deep copy a complete schema, including: tables, table data, indexes, functions, packages, procedures, sequences, data types, and all other objects from a schema on a specified remote server to a target schema on the local server.

In order to function this extension requires that the following two extensions already be installed on the local server:
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
CREATE USER MAPPING FOR enterprisedb SERVER a_foreign_server
  OPTIONS (user 'i_am_a_user', password 'some-password')
;
GRANT USAGE ON FOREIGN SERVER kronos_test TO enterprisedb
;
