# EnterpriseDB Foreignkey Constraintmanager Extension
## Synopsis
The function implements the four use cases described in the requirements documentation. This will be completely transparent as far as insert/update/delete operations. This will be implemented as a trigger-based solution that creates an access exclusive lock on update and delete when the parent is a partitioned table.

If cascade = true then delete and update will cascade from parent to child.

## Code Example

```
SELECT  edb_util.create_fk_constraint('parent',ARRAY['id'],'child',ARRAY['id'],true);
```

## Installation
A typical PostgreSQL extension is comprised of two files, an SQL file of new functionality, and a control file containing extension meta data. 

The makefile should be run on the EDB Postgres host as root, and should also be sure to have `pg_config` available in the path. E.g.

```
$ cd edb_foreignkeyconstraintmanager
$ sudo PATH=$PATH:/usr/ppas-9.5/bin make install
```

Now the extension can be created with a standard `CREATE EXTENSION edb_foreignkeyconstraintmanager;`, and dropped with `DROP EXTENSION edb_foreignkeyconstraintmanager;`.

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

## Tests

Test cases are stored in the test subdirectory.  They can be run using psql
```
$ psql database -f test4.sql 
```
The inialize_test.sql file will create the extension and build some sample tables used in the tests
