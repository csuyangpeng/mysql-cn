-- 由 tidb 容器 entrypoint 在首启、且尚无 data/tidb_entrypoint/.initdb_done 时按文件名顺序执行
-- 密码与 compose 中 TIDB_ROOT_PASSWORD 一致

-- CREATE DATABASE IF NOT EXISTS myapp;
-- CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED BY 'change_me';
-- GRANT ALL ON myapp.* TO 'app'@'%';

SELECT 1;
