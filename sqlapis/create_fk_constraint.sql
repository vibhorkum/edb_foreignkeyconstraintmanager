CREATE OR REPLACE FUNCTION edb_util.create_fk_constraint(parent regclass, 
                                                         parent_column_names text[], 
child regclass, child_column_names text[], cascade TEXT)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$

DECLARE
	trigger_name TEXT;
	table_oid OID;
        name_prefix TEXT;
        child_col_list TEXT;
        parent_col_list TEXT;
        name_suffix TEXT;
        query TEXT;
BEGIN
   name_suffix := 'EDB_partition_';
   child_col_list := array_to_string(child_column_names, ',');
   parent_col_list := array_to_string(parent_column_names, ',');

-- test for PPAS table part view
IF substring(version(),'EnterpriseDB') != 'EnterpriseDB' 
     AND current_setting('db_dialect') != 'redwood' THEN
  RAISE EXCEPTION 'EnterpriseDB version and redwood mode not found'
      USING HINT = 'PPAS in oracle compatiblity mode is required for this extension';
END IF;  

--  Parent is not partition
IF NOT edb_util.is_partition(parent) THEN
  -- parent is not partitioned and child is partitioned, then alter table on each partition table
  IF edb_util.is_partition(child) THEN
    FOR table_oid in SELECT edb_util.get_partition_list(child)
    LOOP
       trigger_name = name_suffix||child::OID|| '_' || table_oid || '_' || parent::OID||'_'||child_col_list || '_fkey';

      -- if constraint exists, raise notice
      IF NOT edb_util.has_fk_constraint(table_oid::regclass, child_col_list,parent, parent_col_list) THEN
        PERFORM DBMS_OUTPUT.PUT_LINE('INFO: creating constraint on '||table_oid::REGCLASS::TEXT);
        query := format('ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s)',
                        table_oid::REGCLASS::TEXT, quote_ident(trigger_name), child_col_list, parent::TEXT, parent_col_list);
        EXECUTE query;
      ELSE 
        PERFORM DBMS_OUTPUT.PUT_LINE('INFO: '||table_oid::REGCLASS::TEXT||' already has Fkey');
      END IF;
    END LOOP;
  
  -- parent is not partition and child is not partitioned
  ELSE
    IF NOT edb_util.has_fk_constraint(child, child_col_list,parent, parent_col_list) THEN
       trigger_name := name_suffix||child::OID||'_'||parent::OID||'_'||child_col_list || '_fkey';
       query := format('ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s)',
                        child::TEXT, quote_ident(trigger_name), child_col_list, parent::TEXT, parent_col_list);
       EXECUTE query;
    ELSE 
       PERFORM DBMS_OUTPUT.PUT_LINE('INFO: '||child::TEXT||' already has Fkey');
    END IF;
  END IF;

ELSE
  -- parent is partitioned
  -- add trigger for each partitioned table of parent  
  FOR table_oid in SELECT edb_util.get_partition_list(parent) 
  LOOP
    trigger_name = name_suffix||parent::OID|| '_' || table_oid || '_' || child::OID||'_'||parent_col_list || '_fkey';
    IF NOT edb_util.has_fk_trigger(trigger_name,table_oid::REGCLASS::TEXT) THEN
       PERFORM DBMS_OUTPUT.PUT_LINE('INFO: creating constraint on '||table_oid::REGCLASS::TEXT);
       EXECUTE 'CREATE TRIGGER ' || quote_ident(trigger_name) || ' BEFORE DELETE OR UPDATE ON ' || table_oid::REGCLASS::TEXT || ' FOR EACH ROW
       EXECUTE PROCEDURE
       check_foreign_key (
       1,  			        -- number of tables that foreign keys need to be checked
       ' || cascade || ', 	        -- boolean defines that corresponding keys must be deleted.
       ' || child_col_list || ', 	-- name of primary key column in triggered table (A). 
 					-- You may use as many columns as you need.
       ' || child|| ', 	-- name of (first) table with foreign keys.
       ' || parent_col_list || ')';
    ELSE
       PERFORM DBMS_OUTPUT.PUT_LINE('INFO: '||table_oid::REGCLASS::TEXT||' already has Fkey');
    END IF;
  END LOOP;

  -- check_primary_key on child table  
   trigger_name = name_suffix||child::OID|| '_' || parent::OID||'_'||parent_col_list || '_fkey';

  IF edb_util.has_fk_trigger(trigger_name,child) THEN
    PERFORM DBMS_OUTPUT.PUT_LINE('INFO: '|| 'Trigger:'|| trigger_name || ' already exists');
  ELSE
    EXECUTE 'CREATE TRIGGER ' || quote_ident(trigger_name )|| ' BEFORE INSERT OR UPDATE ON ' || child || ' FOR EACH ROW
    EXECUTE PROCEDURE
    check_primary_key (
      ' || child_col_list || ',	-- name of foreign key column in triggered (B) table. You may use as
  		  		-- many columns as you need, but number of key columns in referenced
			  	-- table must be the same.
      ' || parent || ', -- referenced table name.
      ' || parent_col_list || ')';
  END IF;
END IF;
RETURN TRUE;  
END; 
$function$;

