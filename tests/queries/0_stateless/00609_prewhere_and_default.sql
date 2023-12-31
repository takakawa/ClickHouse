drop table if exists `table_00609`;
create table `table_00609` (key UInt64, val UInt64) engine = MergeTree order by key settings index_granularity=8192;
insert into `table_00609` select number, number / 8192 from system.numbers limit 100000; 
alter table `table_00609` add column def UInt64 default val + 1;
select * from `table_00609` prewhere val > 2 format Null;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=100;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=1000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=10000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=20000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=30000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=40000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=80000;

drop table if exists `table_00609`;
create table `table_00609` (key UInt64, val UInt64) engine = MergeTree order by key settings index_granularity=8192;
insert into `table_00609` select number, number / 8192 from system.numbers limit 100000; 
alter table `table_00609` add column def UInt64;
select * from `table_00609` prewhere val > 2 format Null;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=100;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=1000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=10000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=20000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=30000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=40000;
select * from `table_00609` prewhere val > 2 format Null SETTINGS max_block_size=80000;

drop table if exists `table_00609`;
