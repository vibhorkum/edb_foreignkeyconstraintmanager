#!/bin/bash
PGDATABASE=clone_schema
psql -f data_type_test.sql
psql -c "CREATE SCHEMA datatype_clone;"
psql -c "select edb_util.localcopyschema('datatype_test',ARRAY['datatype_clone'])"
pg_dump -n datatype_test |grep -v -e "^CREATE SCHEMA" -e "^ALTER SCHEMA datatype_clone" -e "^SET search_path = " -e "^\-\-" >datatype_test.dmp
pg_dump -n datatype_clone |grep -v -e "^CREATE SCHEMA" -e "^ALTER SCHEMA datatype_clone" -e "^SET search_path = " -e "^\-\-" > datatype_clone.dmp
psql -c "DROP SCHEMA datatype_clone CASCADE;"
psql -c "DROP SCHEMA datatype_test CASCADE;"
diff datatype_test.dmp datatype_clone.dmp
