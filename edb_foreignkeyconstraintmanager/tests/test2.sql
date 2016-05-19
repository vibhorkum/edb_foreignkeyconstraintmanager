\i inialize_test.sql

\qecho "################ partitioned parent, partitioned child #####################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales', '{order_no}', 'sales2', '{order_no}', true);
\d+ sales
\d+ sales_europe
\d+ sales_asia
\d+ sales_americas

\d+ sales2
\d+ sales2_europe
\d+ sales2_asia
\d+ sales2_americas


\i inialize_test.sql

\qecho "################ partitioned parent, non partitioned child #####################"
\qecho "################################################################################"

select edb_util.create_fk_constraint('sales', '{order_no}', 'sales_np', '{order_no}', true);
\d+ sales
\d+ sales_europe
\d+ sales_asia
\d+ sales_americas


