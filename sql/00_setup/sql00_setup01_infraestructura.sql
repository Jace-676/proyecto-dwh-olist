-- =====================================================
-- 01_infraestructura.sql
-- Zona horaria, Resource Monitor, Warehouses, BD y esquemas
-- =====================================================

-- ---------- A. Configuración de cuenta (ACCOUNTADMIN) ----------
USE ROLE ACCOUNTADMIN;

-- Zona horaria acordada por el equipo (afecta las horas que se muestran)
ALTER ACCOUNT SET TIMEZONE = 'America/Cancun';

-- Resource Monitor: tope de créditos para proteger la cuenta trial.
-- 100 créditos es una cuarta parte aprox. del crédito de la trial; ajústalo si quieres.
CREATE OR REPLACE RESOURCE MONITOR RM_PROYECTO_DWH
  WITH CREDIT_QUOTA = 10
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 50  PERCENT DO NOTIFY
           ON 80  PERCENT DO NOTIFY
           ON 90  PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- ---------- B. Warehouses (los crea SYSADMIN) ----------
USE ROLE SYSADMIN;

-- Ingesta ELT (COPY INTO, MERGE)
CREATE WAREHOUSE IF NOT EXISTS WH_CARGA
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ingesta ELT: COPY INTO y MERGE';

-- Depuración, clasificación IoT, construcción de CORE y MART
CREATE WAREHOUSE IF NOT EXISTS WH_TRANSFORMACION
  WAREHOUSE_SIZE      = 'SMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Transformaciones RAW -> STAGE -> CORE -> MART';

-- Consultas de analistas y tableros
CREATE WAREHOUSE IF NOT EXISTS WH_ANALISIS
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Consultas analiticas y tableros';

-- ---------- C. Asignar el Resource Monitor (ACCOUNTADMIN) ----------
USE ROLE ACCOUNTADMIN;

ALTER WAREHOUSE WH_CARGA          SET RESOURCE_MONITOR = RM_PROYECTO_DWH;
ALTER WAREHOUSE WH_TRANSFORMACION SET RESOURCE_MONITOR = RM_PROYECTO_DWH;
ALTER WAREHOUSE WH_ANALISIS       SET RESOURCE_MONITOR = RM_PROYECTO_DWH;

-- ---------- D. Base de datos y esquemas (SYSADMIN) ----------
USE ROLE SYSADMIN;
USE WAREHOUSE WH_CARGA;

CREATE DATABASE IF NOT EXISTS DWH_OLIST
  COMMENT = 'Data Warehouse Olist + telemetria IoT simulada';

-- Se elimina el esquema PUBLIC que Snowflake crea por defecto (no lo usaremos)
DROP SCHEMA IF EXISTS DWH_OLIST.PUBLIC;

CREATE SCHEMA IF NOT EXISTS DWH_OLIST.RAW
  COMMENT = 'Datos originales sin transformar (CSV y JSON en VARIANT)';

-- STAGE transitorio: sus tablas son transitorias (menos costo, regenerables)
CREATE TRANSIENT SCHEMA IF NOT EXISTS DWH_OLIST.STAGE
  COMMENT = 'Datos depurados y tipados; JSON aplanado';

CREATE SCHEMA IF NOT EXISTS DWH_OLIST.CORE
  COMMENT = 'Modelo dimensional: hechos y dimensiones';

CREATE SCHEMA IF NOT EXISTS DWH_OLIST.MART
  COMMENT = 'Vistas y agregados para reportes';

-- Esquema adicional (no estaba en la propuesta) para bitacora de cargas
-- y resultados de calidad; asi no se mezclan con los datos de negocio.
CREATE SCHEMA IF NOT EXISTS DWH_OLIST.CONTROL
  COMMENT = 'Bitacora de cargas y resultados de calidad';

-- Contexto de trabajo por defecto para las siguientes fases
USE DATABASE DWH_OLIST;