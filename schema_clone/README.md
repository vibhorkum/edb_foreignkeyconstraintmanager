Documentation:
----------------
clone_remote_schema is a module written in plpgsql function and specifically made for EPAS version 9.5(Enterprise Postgres Advanced Server).
Using this function user can clone the remote schema to target database. This module consists of following three functions:
1. clone_pre_data_ddl: function generate pre-data ddls using pg_dump command.
2. clone_post_data_ddl: function generate post-data ddls using pg_dump command.
3. remote_table_copy_data: function copies data from source table to target table using COPY command
4. clone_remote_schema: function is a wrapper function which takes user input and call above 3 functions

Module also utilizes user defined directory to create error log file.

Pre-requisite:
---------------
To use this module user has to install following extensions in database:
CREATE EXTENSION postgres_fdw;
CREATE EXTENSION dblink;
CREATE EXTENSION file_fdw;


Usage:

Following are the steps which user has to before using function provided by this module:
1. Create source and target servers using postgres_fdw:

CREATE SERVER src_postgres_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5444', dbname 'schema_rename');
CREATE SERVER tgt_postgres_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5444', dbname 'schema_rename');

2. Create user mapping for each server using CREATE USER MAPPING command:
CREATE USER MAPPING FOR enterprisedb SERVER src_postgres_server OPTIONS (user 'enterprisedb', password 'edb');
CREATE USER MAPPING FOR enterprisedb SERVER tgt_postgres_server OPTIONS (user 'enterprisedb', password 'edb');

3. Create a database directory using CREATE DIRECTORY command:
CREATE DIRECTORY empdir AS '/tmp/schemaclone';

3. Using file_fdw create a clone_error_serevr as given below:
CREATE SERVER clone_error_server FOREIGN DATA WRAPPER file_fdw;


Function clone_remote_schema takes following arguments in sequence:
1. src_fdw_server: source server name
2. remote_user: database user mapped to remote server
3. tgt_fdw_server: target server name
3. tgt_user: database user mapped to target server
4. pg_home: home directory of EPAS binaries
5. dir_name: name of directory created by user
6. src_schema: name of schema at source server side
7. tgt_schema: name of schema at target server side


Example of usages:
-------------------

CREATE SERVER src_postgres_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5444', dbname 'schema_rename');
CREATE SERVER tgt_postgres_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5444', dbname 'schema_rename');

CREATE USER MAPPING FOR enterprisedb SERVER src_postgres_server OPTIONS (user 'enterprisedb', password 'edb');
CREATE USER MAPPING FOR enterprisedb SERVER tgt_postgres_server OPTIONS (user 'enterprisedb', password 'edb');

CREATE DIRECTORY empdir AS '/tmp/schemaclone';

CREATE SERVER clone_error_server FOREIGN DATA WRAPPER file_fdw;


select clone_remote_schema('src_postgres_server',
                           'enterprisedb',
                           'tgt_postgres_server',
                           'enterprisedb',
                           '/usr/ppas-9.5',
                           'empdir',
                           'source',
                           'target');
NOTICE:  create pre data ddls
NOTICE:  verifying for any error
NOTICE:  changing schema name
NOTICE:  restoring ddls in schema
NOTICE:  verifying restore errors.
NOTICE:  restored of pre ddl successfully
NOTICE:  status pre data: t
NOTICE:  copying table: target.dept
NOTICE:  copying table: target.jobhist
NOTICE:  copying table: target.emp
NOTICE:  create post data ddls
NOTICE:  verifying for any error
NOTICE:  changing schema name
NOTICE:  restoring ddls in schema
NOTICE:  verifying restore errors.
NOTICE:  restored of post ddl successfully
NOTICE:  status post data: t
NOTICE:  disconnect
 clone_remote_schema 
---------------------
 t
(1 row)


