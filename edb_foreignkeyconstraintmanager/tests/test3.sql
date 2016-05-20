\i inialize_test.sql

\qecho "################ non partitioned parent, non partitioned child #################"
\qecho "######### https://github.com/EnterpriseDB/kronos_api/issues/15 #################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales_np', '{order_no}', 'sales2_np', '{order_no}', true);
\d+ sales_np
\d+ sales2_np
