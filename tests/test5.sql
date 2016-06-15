SELECT edb_util.alter_table_drop_partition('patients', 'pO', ARRAY['appointments'], 'restrict');
SELECT edb_util.alter_table_drop_partition('patients', 'pO', ARRAY['appointments'], 'setnull');

