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

## Example
---------
```sql
test=# CREATE EXTENSION IF NOT EXISTS refint;
CREATE EXTENSION
test=# DROP EXTENSION edb_foreignkeyconstraintmanager;
ERROR:  extension "edb_foreignkeyconstraintmanager" does not exist
test=# CREATE EXTENSION edb_foreignkeyconstraintmanager;
CREATE EXTENSION
test=# -- (1) Non partitioned table referencing non partitioned table
test=# create table teachers(tid int primary key, tname varchar(255));
CREATE TABLE
test=# create table students(sid int primary key, sname varchar(255), tid int);
CREATE TABLE
test=# 
test=# SELECT  edb_util.create_fk_constraint('teachers',ARRAY['tid'],'students',ARRAY['tid'],'cascade');
 create_fk_constraint 
----------------------
 t
(1 row)

test=# 
test=# insert into teachers values(1, 't1');
INSERT 0 1
test=# insert into teachers values(2, 't2');
INSERT 0 1
test=# insert into teachers values(3, 't3');
INSERT 0 1
test=# 
test=# insert into students values(1, 's1', 1);
INSERT 0 1
test=# insert into students values(2, 's2', 2);
INSERT 0 1
test=# insert into students values(3, 's3', 3);
INSERT 0 1
test=# 
test=# -- Should Report Error
test=# insert into students values(4, 's4', 4);
ERROR:  insert or update on table "students" violates foreign key constraint "EDB_partition_35570_35565_tid_fkey"
DETAIL:  Key (tid)=(4) is not present in table "teachers".
test=# 
test=# 
test=# 
test=# 
test=# -- (2) Partitioned table referencing non partitioned table
test=# create table blood_group(bid int primary key, bname varchar(255));
CREATE TABLE
test=# insert into blood_group values(1, 'O+');
INSERT 0 1
test=# insert into blood_group values(2, 'O-');
INSERT 0 1
test=# insert into blood_group values(3, 'A+');
INSERT 0 1
test=# insert into blood_group values(4, 'A-');
INSERT 0 1
test=# insert into blood_group values(5, 'B+');
INSERT 0 1
test=# insert into blood_group values(6, 'B-');
INSERT 0 1
test=# insert into blood_group values(7, 'AB+');
INSERT 0 1
test=# insert into blood_group values(8, 'AB-');
INSERT 0 1
test=# 
test=# create table patients(pid int primary key, pname varchar(255), bid int)
test-# PARTITION BY LIST(bid)
test-# (
test(#   PARTITION pO_pos VALUES (1),
test(#   PARTITION pO_neg VALUES (2),
test(#   PARTITION pA_pos VALUES (3),
test(#   PARTITION pA_neg VALUES (4),
test(#   PARTITION pB_pos VALUES (5),
test(#   PARTITION pB_neg VALUES (6),
test(#   PARTITION pAB_pos VALUES (7),
test(#   PARTITION pAB_neg VALUES (8),
test(#   PARTITION pxx VALUES (DEFAULT)
test(# ); 
CREATE TABLE
test=# 
test=# SELECT  edb_util.create_fk_constraint('blood_group',ARRAY['bid'],'patients',ARRAY['bid'],'cascade');
INFO: creating constraint on patients_po_pos
INFO: creating constraint on patients_po_neg
INFO: creating constraint on patients_pa_pos
INFO: creating constraint on patients_pa_neg
INFO: creating constraint on patients_pb_pos
INFO: creating constraint on patients_pb_neg
INFO: creating constraint on patients_pab_pos
INFO: creating constraint on patients_pab_neg
INFO: creating constraint on patients_pxx
 create_fk_constraint 
----------------------
 t
(1 row)

test=# 
test=# insert into patients values(1,'p1',1);
INSERT 0 1
test=# insert into patients values(2,'p2',2);
INSERT 0 1
test=# insert into patients values(3,'p3',3);
INSERT 0 1
test=# 
test=# -- Should Report Error
test=# insert into patients values(4,'p4',9);
ERROR:  insert or update on table "patients_pxx" violates foreign key constraint "EDB_partition_35585_35657_35580_bid_fkey"
DETAIL:  Key (bid)=(9) is not present in table "blood_group".
test=# 
test=# 
test=# 
test=# 
test=# -- (3) Partitoned table referencing partitioned table
test=# create table manufacturers(mid int primary key, mname varchar(255))
test-# PARTITION BY HASH(mname)
test-# (
test(#   PARTITION p1,
test(#   PARTITION p2,
test(#   PARTITION p3,
test(#   PARTITION p4
test(# );
CREATE TABLE
test=# 
test=# insert into manufacturers values(1, 'm1');
INSERT 0 1
test=# insert into manufacturers values(2, 'm2');
INSERT 0 1
test=# insert into manufacturers values(3, 'm3');
INSERT 0 1
test=# 
test=# 
test=# create table products(pid int primary key, pname varchar(255), mid int)
test-# PARTITION BY HASH(pname)
test-# (
test(#   PARTITION p1,
test(#   PARTITION p2,
test(#   PARTITION p3,
test(#   PARTITION p4
test(# ); 
CREATE TABLE
test=# 
test=# SELECT edb_util.create_fk_constraint('manufacturers',ARRAY['mid'],'products',ARRAY['mid'],'cascade');
INFO: creating constraint on manufacturers_p1
INFO: creating constraint on manufacturers_p2
INFO: creating constraint on manufacturers_p3
INFO: creating constraint on manufacturers_p4
 create_fk_constraint 
----------------------
 t
(1 row)

test=# 
test=# insert into products values(1, 'p1', 1);
INSERT 0 1
test=# insert into products values(2, 'p2', 2);
INSERT 0 1
test=# insert into products values(3, 'p3', 3);
INSERT 0 1
test=# 
test=# -- Should Report Error
test=# insert into products values(4, 'p4', 4);
ERROR:  tuple references non-existent key
DETAIL:  Trigger "EDB_partition_35750_35710_mid_fkey" found tuple referencing non-existent key in "manufacturers".
test=# 
test=# 
test=# 
test=# 
test=# -- (4) Non partitioned table referencing partitioned table
test=# create table countries(cid int primary key, cname varchar(255))
test-# PARTITION BY HASH(cid)
test-# (
test(#   PARTITION p1,
test(#   PARTITION p2,
test(#   PARTITION p3,
test(#   PARTITION p4
test(# ); 
CREATE TABLE
test=# 
test=# insert into countries values(1, 'pakistan');
INSERT 0 1
test=# insert into countries values(2, 'iran');
INSERT 0 1
test=# insert into countries values(3, 'turkey');
INSERT 0 1
test=# 
test=# create table travellers(tid int primary key, tname varchar(255), cid int);
CREATE TABLE
test=# 
test=# SELECT edb_util.create_fk_constraint('countries',ARRAY['cid'],'travellers',ARRAY['cid'],'cascade');
INFO: creating constraint on countries_p1
INFO: creating constraint on countries_p2
INFO: creating constraint on countries_p3
INFO: creating constraint on countries_p4
 create_fk_constraint 
----------------------
 t
(1 row)

test=# 
test=# insert into travellers values(1, 'r1', 1);
INSERT 0 1
test=# insert into travellers values(2, 'r2', 2);
INSERT 0 1
test=# insert into travellers values(3, 'r3', 3);
INSERT 0 1
test=# 
test=# -- Should Report Error
test=# insert into travellers values(4, 'r4', 4);
ERROR:  tuple references non-existent key
DETAIL:  Trigger "EDB_partition_35835_35795_cid_fkey" found tuple referencing non-existent key in "countries".
test=# 

```