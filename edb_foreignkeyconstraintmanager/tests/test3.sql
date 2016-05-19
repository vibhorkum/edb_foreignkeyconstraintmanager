\i inialize_test.sql

\qecho "################ non partitioned parent, non partitioned child #####################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales_np', '{order_no}', 'sales2_np', '{order_no}', true);
\d+ sales_np
\d+ sales2_np
