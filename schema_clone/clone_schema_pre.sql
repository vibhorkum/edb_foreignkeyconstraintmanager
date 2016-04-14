CREATE OR REPLACE FUNCTION clone_pre_data_ddl(src_fdw_server TEXT, 
                                              remote_user TEXT, 
                                              db_snapshot_id TEXT,  
                                              tgt_fdw_server TEXT,
                                              tgt_user   TEXT,
                                              pg_home TEXT,
                                              directory_path TEXT,
                                              dmp_file_name  TEXT,
                                              src_schema TEXT, 
                                              tgt_schema TEXT)
RETURNS boolean
LANGUAGE plpgsql
AS
$function$
DECLARE
   src_db_connection_sql TEXT := 'SELECT array_to_string (srvoptions,'' '' ) AS CONNECTION,
                                     (string_to_array(umoptions[1],''='' ))[2] AS USER,
                                     (string_to_array (umoptions[2],''=''))[2] AS PASSWORD
                              FROM pg_foreign_server s JOIN pg_user_mappings u ON 
                                   (s.srvname = u.srvname AND s.srvowner = u.umuser)
                              WHERE s.srvname = '||quote_literal(src_fdw_server)||' AND u.usename ='|| quote_literal(remote_user) ;
   tgt_db_connection_sql TEXT := 'SELECT array_to_string (srvoptions,'' '' ) AS CONNECTION,
                                     (string_to_array(umoptions[1],''='' ))[2] AS USER,
                                     (string_to_array (umoptions[2],''=''))[2] AS PASSWORD
                              FROM pg_foreign_server s JOIN pg_user_mappings u ON 
                                   (s.srvname = u.srvname AND s.srvowner = u.umuser)
                              WHERE s.srvname = '||quote_literal(tgt_fdw_server)||' AND u.usename ='|| quote_literal(tgt_user) ;
   src_conn_info TEXT;
   src_user_name TEXT;
   src_passwd TEXT;
   tgt_conn_info TEXT;
   tgt_user_name TEXT;
   tgt_passwd TEXT;
   pg_dump TEXT := pg_home||'/bin/pg_dump';
   psql    TEXT := pg_home||'/bin/psql';
   rec          RECORD;
   pg_dump_command TEXT;
   copy_pg_dump TEXT;
   psql_command TEXT;
   rename_sed TEXT;
   delete_dump    TEXT;
   error_count bigint;
BEGIN
   CREATE TEMP TABLE pre_log_table(log text);
   EXECUTE src_db_connection_sql INTO rec;
   src_conn_info := rec.CONNECTION;
   src_user_name := rec.USER;
   src_passwd    := rec.PASSWORD;

   EXECUTE tgt_db_connection_sql INTO rec;
   tgt_conn_info := rec.CONNECTION;
   tgt_user_name := rec.USER;
   tgt_passwd    := rec.PASSWORD;

   RAISE NOTICE 'create pre data ddls';
   delete_dump := format('rm -f %s/%s.dmp',directory_path, dmp_file_name);
   copy_delete_dump := 'COPY pre_log_table FROM program '||quote_literal(delete_dump);
 
   pg_dump_command := format('PGUSER="%s" PGPASSWORD="%s" %s -O --section=pre-data -n %s --snapshot=%s "%s" 2>%s/%s_pre.error',
                              src_user_name, src_passwd, pg_dump, src_schema, db_snapshot_id, 
                              src_conn_info, directory_path, dmp_file_name);
   rename_sed := format('sed -e "s/^SET search_path = %s/SET search_path = %s/g" -e "s/ %s\./ %s\./g" -e "/^REVOKE ALL ON SCHEMA/d" -e "/^GRANT ALL ON SCHEMA/d" -e "s/^CREATE SCHEMA %s/CREATE SCHEMA %s/g"',
                         src_schema,tgt_schema, src_schema, tgt_schema, src_schema, tgt_schema);
   psql_command := format('PGUSER="%s" PGPASSWORD="%s" %s -X -q --pset pager=off -v ON_ERROR_STOP=1  "%s" 2>%s/%s_psql.error',
                          tgt_user_name, tgt_passwd,psql, tgt_conn_info, directory_path, dmp_file_name);
                         
   copy_pg_dump := $SQL$ COPY pre_log_table FROM program '$SQL$|| pg_dump_command ||$SQL$ | $SQL$|| rename_sed || $SQL$ | $SQL$ ||
                  psql_command ||$SQL$ ' $SQL$;
   
   EXECUTE copy_pg_dump;
   
   RAISE NOTICE 'verifying for any error';
   EXECUTE 'CREATE FOREIGN TABLE IF NOT EXISTS dump_error_pre (log TEXT) SERVER clone_error_server OPTIONS(filename '|| 
              quote_literal(directory_path|| '/'||dmp_file_name||'_pre.error')||')';
   SELECT COUNT(1) INTO error_count  FROM dump_error_pre WHERE log ~ 'ERROR:';
   IF error_count > 0 THEN
     RAISE NOTICE 'error occurred during pre ddl stage';
     FOR rec IN SELECT log FROM dump_error_pre
     LOOP
       RAISE NOTICE '%',rec.log;
     END LOOP;
     EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_pre';
     DROP TABLE pre_log_table;
     RAISE EXCEPTION 'failed to clone copy % schema. For more detail please see log file %/%_pre.error',
                      src_schema, directory_path, dmp_file_name;
     EXECUTE copy_delete_dump;
     RETURN false;
   END IF;

   RAISE NOTICE 'verifying restore errors.';
   EXECUTE 'CREATE FOREIGN TABLE IF NOT EXISTS dump_error_psql (log TEXT) SERVER clone_error_server OPTIONS(filename '|| 
              quote_literal(directory_path||'/'||dmp_file_name||'_psql.error')||')';
   SELECT COUNT(1) INTO error_count  FROM dump_error_psql WHERE log ~ 'ERROR:';

   IF error_count > 0 THEN
     RAISE NOTICE 'error occurred during pre ddl restore stage';
     FOR rec IN SELECT log FROM dump_error_psql
     LOOP
       RAISE NOTICE '%',rec.log;
     END LOOP;
     EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_pre';
     EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_psql';
     EXECUTE copy_delete_dump;
     DROP TABLE pre_log_table;
     RAISE EXCEPTION 'failed to restoe copy % schema. For more detail please see log file %/%_psql.error',
                      src_schema, directory_path, dmp_file_name;
     RETURN false;
   END IF;

   RAISE NOTICE 'restored of pre ddl successfully'; 
   EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_psql';
   EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_pre';
   EXECUTE copy_delete_dump;
   DROP TABLE pre_log_table;
   RETURN TRUE;
   EXCEPTION 
        WHEN others THEN  
          EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_psql';
          EXECUTE 'DROP FOREIGN TABLE IF EXISTS dump_error_pre';
          DROP TABLE pre_log_table;
          EXECUTE copy_delete_dump;
          RAISE NOTICE 'failed to restoe copy % schema. For more detail please see log file %/%_psql/pre.error',
                      src_schema, directory_path, dmp_file_name;
          RETURN false;     
END;
$function$;

