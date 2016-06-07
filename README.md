# EnterpriseDB Foreignkey Constraintmanager Extension

EDB Foreign Key Constraint Manager is an extension, which allows user to create foreign key relationship between tables for following use cases:

1. Parent table is partitioned and child table is non-partitioned
2. Parent and child tables both are partitioned
3. Parent table is non-partitioned and child table is partitioned
4. Parent and child tables are non partitioned.

For use cases, where parent table is partitioned, this module uses the trigger based approach. i.e it creates the trigger using refint module which comes with EDB Postgres.
If parent and child both are non-partitioned, then this module uses the standard ALTER TABLE command to add foreign key constraint between parent and child.

From naming convention perspective it uses following nomenclature to create constraint/triggers for implementation:
**EDB_partition_oid1_oid2_columnlist**

1. oid1 : oid1 is oid of table on which trigger will be created
2. oid2: oid2 is oid of table which will be part of FK constraint.
3. columnlist: all columns names of table on which trigger will be created.

## About Refint
Refint is a module comes with PostgreSQL and also available in EDB Postgres. This module has functions for Implementing Referential Integrity. For more detail, please refer to following link:

https://www.postgresql.org/docs/9.5/static/contrib-spi.html

## SQL APIs of EDB Foreign Key Constraint Manager

EDB Foreign Key Constraint Manager comes with a SQL function **edb_util.create_fk_constraint()**. This function implements the foreign key relationship between tables, which is completely transparent to insert/update/delete operations and doesn't keep heavy lock while implementing the Foreign key on table.
Function takes following arguments:

1. parent REGCLASS: Name of the parent table
2. parent_column_names TEXT[]: list of columns of parent table in array format
2. child REGCLASS: Name of the child table
3.  child_column_names TEXT[]: column list of child table in array format
4.  cascade TEXT: action for update/delete operation. cascade takes following arguments:
  1. If cascade = 'cascade' — then on delete, delete the referencing row
  2. If cascade = 'restrict' — then on delete abort transaction if referencing keys exist, 
  3. If cascade = 'setnull' —  then on delete set referencing key fields to null

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
