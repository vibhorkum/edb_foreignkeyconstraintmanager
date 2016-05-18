# EnterpriseDB Foreignkey Constraintmanager Extension

## Installation
A typical PostgreSQL extension is comprised of two files, an SQL file of new functionality, and a control file containing extension meta data. 

The makefile should be run on the EDB Postgres host as root, and should also be sure to have `pg_config` available in the path. E.g.

```
$ cd edb_foreignkeyconstraintmanager
$ sudo PATH=$PATH:/usr/ppas-9.5/bin make install
```

Now the extension can be created with a standard `CREATE EXTENSION foreignkeyconstraintmanager;`, and dropped with `DROP EXTENSION foreignkeyconstraintmanager;`.

## Usage
This extension provides a single function.  Installation creates this object in the schema `edb_util`, which itself is created if it does not exist.

```
CREATE OR REPLACE FUNCTION edb_util.create_fk_constraint(
  parent_table_name regclass, 
  parent_table_column_names text[], 
  child_table_name regclass, 
  child_table_column_names text[], 
  cascade boolean
)
RETURNS boolean
```
 
### Prerequisites
For installation to proceed, the following extension must be installed on the  server:
* refint

```
CREATE EXTENSION IF NOT EXISTS refint;
```

