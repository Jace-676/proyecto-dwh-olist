-- =====================================================
-- 00_test_edicion.sql
-- Verifica que la cuenta es Enterprise (o superior)
-- =====================================================
USE ROLE ACCOUNTADMIN;

-- Datos de la cuenta (evidencia de región y versión)
SELECT CURRENT_ACCOUNT()  AS cuenta,
       CURRENT_REGION()   AS region,
       CURRENT_VERSION()  AS version_snowflake;

-- Base de prueba temporal
CREATE OR REPLACE DATABASE TEST_EDICION;

-- TEST 1: Time Travel de 90 días (solo Enterprise o superior).
-- En Standard esta sentencia da error porque el máximo es 1 día.
CREATE OR REPLACE TABLE TEST_EDICION.PUBLIC.T_PRUEBA (id INT)
  DATA_RETENTION_TIME_IN_DAYS = 90;

-- TEST 2: Masking policy (solo Enterprise o superior).
CREATE OR REPLACE MASKING POLICY TEST_EDICION.PUBLIC.MP_PRUEBA
  AS (v STRING) RETURNS STRING -> '***';

-- Evidencia: la columna "retention_time" debe mostrar 90
SHOW TABLES LIKE 'T_PRUEBA' IN SCHEMA TEST_EDICION.PUBLIC;