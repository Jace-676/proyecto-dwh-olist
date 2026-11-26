USE ROLE SYSADMIN;
SHOW WAREHOUSES;
SELECT "name", "size", "auto_suspend", "auto_resume", "resource_monitor"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));