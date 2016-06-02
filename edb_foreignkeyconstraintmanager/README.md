# EnterpriseDB Foreignkey Constraintmanager Extension
## Synopsis
The function implements the four use cases described in the requirements documentation. This will be completely transparent as far as insert/update/delete operations. This will be implemented as a trigger-based solution that creates an access exclusive lock on update and delete when the parent is a partitioned table.

If cascade = 'cascade' — then on delete, delete the referencing row, 

If cascade = 'restrict' — then on delete abort transaction if referencing keys exist, 

if cascade = 'setnull' —  then on delete set referencing key fields to null

### Prerequisites
For installation to proceed, the following extension must be installed on the  server:
* refint

```
CREATE EXTENSION IF NOT EXISTS refint;
```

## Code Example

```
SELECT  edb_util.create_fk_constraint('parent',ARRAY['id'],'child',ARRAY['id'],'cascade');
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
  parent regclass, 
  parent_column_names text[], 
  child regclass, 
  child_column_names text[], 
  cascade TEXT
)
RETURNS boolean
```
 
## Limitations
Following are the recommendations while using this extension:

1. Whenever user adds any new partition in partitioned table, It is highly recommended to use **edb_util.create_fk_constraint** function to rebuild the FK for newly added partition.
2. Droping any partition, will not remove the refernced key from referencing table. This is a manual activity with this implementation.
3. If user wants to drop the constraint triger, then they have to perform this operation manually i.e DROP "EDB_partition_" triggers/ Foreign Key constraint manually.

## Tests

Test cases are stored in the test subdirectory.  They can be run using psql
```
$ psql database -f test4.sql 
```
The inialize_test.sql file will create the extension and build some sample tables used in the tests
