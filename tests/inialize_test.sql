-- create function
create extension refint;
create extension edb_foreignkeyconstraintmanager;

-- create tables

DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS sales_np CASCADE;
DROP TABLE IF EXISTS sales2 CASCADE;
DROP TABLE IF EXISTS sales2_np CASCADE;
DROP TABLE IF EXISTS "SalesNP" CASCADE;


CREATE TABLE sales
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
)
PARTITION BY LIST(country)
(
  PARTITION europe VALUES('FRANCE', 'ITALY'),
  PARTITION asia VALUES('INDIA', 'PAKISTAN'),
  PARTITION americas VALUES('US', 'CANADA')
);

CREATE TABLE sales2
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
)
PARTITION BY LIST(country)
(
  PARTITION europe VALUES('FRANCE', 'ITALY'),
  PARTITION asia VALUES('INDIA', 'PAKISTAN'),
  PARTITION americas VALUES('US', 'CANADA')
);


CREATE TABLE sales_np
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
);

CREATE TABLE sales2_np
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
);

CREATE TABLE "SalesNP"
(
  order_no    number PRIMARY KEY,
  dept_no     number,
  part_no     varchar2,
  country     varchar2(20),
  date        date,
  amount      number
);



create table blood_group(bid int primary key, bname varchar(255));
insert into blood_group values(1, 'O');
insert into blood_group values(2, 'A');
insert into blood_group values(3, 'B');
insert into blood_group values(4, 'AB');

create table patients(pid int primary key, pname varchar(255), bid int REFERENCES blood_group(bid))
PARTITION BY LIST(bid)
(
  PARTITION pO VALUES (1),
  PARTITION pA VALUES (2),
  PARTITION pB VALUES (3),
  PARTITION pAB VALUES (4)
); 

SELECT  edb_util.create_fk_constraint('blood_group',ARRAY['bid'],'patients',ARRAY['bid'],'cascade');

insert into patients values(1,'p1',1);
insert into patients values(2,'p2',2);
insert into patients values(3,'p3',3);


create table appointments(aid int primary key, doctor_id int, patient_id int REFERENCES patients(pid))
partition by LIST(doctor_id)
(
  PARTITION d1 VALUES (1),
  PARTITION d2 VALUES (2),
  PARTITION d3 VALUES (3)
);


create table sales(tid int primary key, aid int REFERENCES appointments(aid))
partition by LIST(tid)
(
  PARTITION t1 VALUES (1),
  PARTITION t2 VALUES (2),
  PARTITION t3 VALUES (3)
);

SELECT edb_util.create_fk_constraint('patients',ARRAY['pid'],'appointments',ARRAY['patient_id'],'cascade');

SELECT  edb_util.create_fk_constraint('appointments',ARRAY['aid'],'sales',ARRAY['aid'],'cascade');


insert into appointments values(1, 1, 1);
insert into appointments values(2, 2, 2);
insert into appointments values(3, 3, 3);

insert into sales values(1,1);
insert into sales values(2,2);
insert into sales values(3,3);

