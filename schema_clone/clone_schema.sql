CREATE OR REPLACE FUNCTION clone_remote_schema(src_fdw_server TEXT, 
                                              remote_user TEXT, 
                                              tgt_fdw_server TEXT,
                                              tgt_user   TEXT,
                                              pg_home TEXT,
                                              dir_name TEXT,
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
   dir_path TEXT;
   src_conn_info TEXT;
   src_user_name TEXT;
   src_passwd TEXT;
   tgt_conn_info TEXT;
   tgt_user_name TEXT;
   tgt_passwd TEXT;
   rec          RECORD;
   db_snapshot_id TEXT;
   name_tag       TEXT;
   status         boolean;
BEGIN
   SELECT dirpath INTO dir_path FROM pg_catalog.edb_dir WHERE dirname = dir_name;

   EXECUTE src_db_connection_sql INTO rec;
   src_conn_info := rec.CONNECTION;
   src_user_name := rec.USER;
   src_passwd    := rec.PASSWORD;

   EXECUTE tgt_db_connection_sql INTO rec;
   tgt_conn_info := rec.CONNECTION;
   tgt_user_name := rec.USER;
   tgt_passwd    := rec.PASSWORD;
   name_tag := to_char(now(),'YYYYDDMMHH24MISS');

   PERFORM dblink_connect( name_tag, src_conn_info ||' user='|| src_user_name||' password='|| src_passwd);

   SELECT snapshot_id INTO db_snapshot_id FROM dblink(name_tag,'BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ; SELECT pg_export_snapshot();') foo(snapshot_id TEXT);
   SELECT clone_pre_data_ddl(src_fdw_server, 
                             remote_user, 
                             db_snapshot_id,  
                             tgt_fdw_server,
                             tgt_user,
                             pg_home,
                             dir_path,
                             name_tag,
                             src_schema, 
                             tgt_schema ) INTO status;
  RAISE NOTICE 'status pre data: %',status;
   IF status = false THEN
     PERFORM dblink_disconnect(name_tag);
     RETURN false;
   END IF;

   FOR rec IN SELECT schemaname,tablename FROM pg_tables WHERE schemaname=src_schema
   LOOP
      SELECT remote_table_copy_data(src_fdw_server,
                                    remote_user,
                                    tgt_fdw_server,
                                    tgt_user,
                                    db_snapshot_id,
                                    pg_home,
                                    src_schema||'.'||rec.tablename,
                                    tgt_schema||'.'||rec.tablename) INTO status;
      IF status = false THEN
        PERFORM dblink_disconnect(name_tag);
        RETURN false;
      END IF;
   END LOOP;

   SELECT clone_post_data_ddl(src_fdw_server,  
                             remote_user,   
                             db_snapshot_id,    
                             tgt_fdw_server,
                             tgt_user,
                             pg_home,
                             dir_path,
                             name_tag,
                             src_schema,   
                             tgt_schema ) INTO status;
  RAISE NOTICE 'status post data: %',status;
  IF status = false THEN
     PERFORM dblink_disconnect(name_tag);
     RETURN false;
  END IF;
  RAISE NOTICE 'disconnect';
  PERFORM dblink_disconnect(name_tag);
  RETURN TRUE;
  EXCEPTION 
    WHEN OTHERS THEN
       EXECUTE 'DROP SCHEMA '||tgt_schema||' CASCADE';
       PERFORM dblink_disconnect(name_tag);
       RETURN false;
END;
$function$;

