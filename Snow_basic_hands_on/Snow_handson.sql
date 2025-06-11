/* database 생성*/
create database citibike;

/* trips table 생성 */
create or replace table trips (
    tripduration integer,
    starttime timestamp,
    stoptime timestamp,
    start_station_id integer, 
    start_station_name string,
    start_station_latitude float,
    start_station_longitude float,
    end_station_id integer,
    end_station_name string,
    end_station_latitude float,
    end_station_longitude float,
    bikeid integer,
    membership_type string,
    usertype string,
    birth_year string,
    gender string
);



/* stage안의 파일 목록 확인 */
list @citibike_trips;


/* File Format을 생성 */
create or replace file format 
  csv type='csv'
  compression = 'auto' 
  field_delimiter = ',' 
  record_delimiter = '\n'
  skip_header = 1 
  field_optionally_enclosed_by = '\042' 
  trim_space = false
  error_on_column_count_mismatch = false 
  escape = 'none' 
  escape_unenclosed_field = '\134'
  date_format = 'auto' 
  timestamp_format = 'auto' 
  null_if = ('') 
  comment = 'file format for ingesting data to snowflake';


/* database내의 생성된 file format 정보를 확인*/
show file formats in database citibike;


/* citibike_trips 외부 스테이지에 있는 데이터 파일을 csv 파일 포맷에 맞춰서 trips 테이블에 로딩 */
copy into trips from @citibike_trips file_format=csv pattern= '.*csv.*';


/* 테이블에 로딩된 데이터를 확인 */
select * from trips limit 20;


/* 자전거를 대여한 시간에서 시간대를 추출해서 각 시간대 별로 이용 현황을 집계
아래는 하버사인 삼각함수를 통해서 위도 경도 데이터로 대략적인 이동 거리를 계산하고 그 외에 다양한 지리 정보 함수를 함께 제공 */
Select 
    date_trunc('hour', starttime) as "date",
    count(*) as "num trips",
    avg(tripduration)/60 as "avg duration (mins)",
    avg(haversine(start_station_latitude, start_station_longitude, end_station_latitude, end_station_longitude)) as "avg distance (km)"
from trips
group by 1 order by 1;


/* 자전거 트립이 많고 이동 거리가 길었던 시간대를 집계 
여기서는 지리 공간 함수를 사용해서 평균 이동 거리를 계산했습니다 */
select 
    date_trunc('hour', starttime) as "date",
    count(*) as "num trips",
    avg(tripduration)/60 as "avg duration (mins)",
    avg(st_distance(st_makepoint(start_station_latitude, start_station_longitude), st_makepoint(end_station_latitude, end_station_longitude)) / 1000) as "avg distance (km)"
from trips
group by 1 
having "num trips" > 100 and "avg distance (km)" > 1.5
order by 1;


/* 2013년 이래로 가장 인기 있는 루트를 집계 */
select
start_station_name,
end_station_name,
count(*) as "num trips"
from trips
where starttime > '2013'
group by 1, 2 order by 3 desc;


/* trips 테이블의 데이터와 메타데이터 삭제 */
truncate table trips;

/* 가상 웨어하우스의 크기를 large로 변경 */
alter warehouse compute_wh set warehouse_size='large';

/* 웨어하우스의 변경 사항 확인 */
show warehouses;

/* citibike_trips 외부 스테이지에 있는 데이터 파일을 csv 파일 포맷에 맞춰서 trips 테이블에 로딩 */
copy into trips from @citibike_trips file_format=csv pattern= '.*csv.*';



--반정형 데이터 로드 하기 
/* 데이터 베이스 생성 */
create database weather;

/* JSON객체 저장 테이블 생성 */
create table json_weather_data (v variant);

/* External Stage 생성 */
create stage nyc_weather
	url = 's3://snowflake-workshop-lab/weather-nyc';

/* Stage 목록 확인 */
list @nyc_weather;

/* 비정형 데이터 로드 */
copy into json_weather_data
from @nyc_weather
file_format = (type=json);

/* 데이터가 잘 로드 되었는지 확인 */
select * from json_weather_data limit 10;

/* View 생성 */
create view json_weather_data_view as
select
v:time::timestamp as observation_time,
v:city.id::int as city_id,
v:city.name::string as city_name,
v:city.country::string as country,
v:city.coord.lat::float as city_lat,
v:city.coord.lon::float as city_lon,
v:clouds.all::int as clouds,
(v:main.temp::float)-273.15 as temp_avg,
(v:main.temp_min::float)-273.15 as temp_min,
(v:main.temp_max::float)-273.15 as temp_max,
v:weather[0].main::string as weather,
v:weather[0].description::string as weather_desc,
v:weather[0].icon::string as weather_icon,
v:wind.deg::float as wind_dir,
v:wind.speed::float as wind_speed
from json_weather_data
where city_id = 5128638;


/* View 확인 */
select * from json_weather_data_view
where date_trunc('month',observation_time) = '2018-01-01'
limit 20;


SELECT DISTINCT date_trunc('hour', observation_time) FROM json_weather_data_view;


/* Join으로 날씨와 자전거 이용횟수의 상관관계 확인 */
select 
    weather as conditions,
    count(*) as num_trips
from citibike.public.trips
left outer join json_weather_data_view
on date_trunc('hour', observation_time) = date_trunc('hour', starttime)
where conditions is not null
group by 1 order by 2 desc
;


--역할관리와 접근제어

/* ACCOUNTADMIN 사용 */
use role accountadmin;

/* 역할 생성 후 유저에게 역할 부여 - 실습에서는 사용하지 않습니다.*/
create role custom_role;
grant role custom_role TO ROLE SYSADMIN;
create user test_user PASSWORD='abc123' DEFAULT_ROLE = custom_role DEFAULT_WAREHOUSE = compute_wh MUST_CHANGE_PASSWORD = FALSE;
grant role custom_role to user test_user;

/* 역할에 권한 부여 */
GRANT ALL ON DATABASE CITIBIKE TO ROLE ab;
GRANT ALL ON ALL SCHEMAS IN DATABASE CITIBIKE TO ROLE CUSTOM_ROLE;
GRANT ALL ON TABLE CITIBIKE.PUBLIC.TRIPS TO ROLE CUSTOM_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE CUSTOM_ROLE;
SHOW GRANTS TO ROLE CUSTOM_ROLE;

/* 권한이 부여된 역할로 쿼리문 실행 */
USE DATABASE CITIBIKE;
USE SCHEMA PUBLIC;
SELECT * FROM TRIPS LIMIT 10;
