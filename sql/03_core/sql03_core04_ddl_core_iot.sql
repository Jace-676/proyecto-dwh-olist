USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

CREATE TABLE IF NOT EXISTS CORE.DIM_CLASIFICACION_IOT (
  clasificacion_key  NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  dimension          VARCHAR(20) NOT NULL,
  perfil             VARCHAR(20) NOT NULL,
  clase              VARCHAR(20) NOT NULL,
  temp_min           FLOAT,
  temp_max           FLOAT,
  vel_min            FLOAT,
  vel_max            FLOAT,
  lat_min            FLOAT,
  lat_max            FLOAT,
  lon_min            FLOAT,
  lon_max            FLOAT,
  desvio_min_km      FLOAT,
  descripcion        VARCHAR,
  CONSTRAINT pk_dim_clasif PRIMARY KEY (clasificacion_key),
  CONSTRAINT uq_dim_clasif UNIQUE (dimension, perfil, clase)
) COMMENT = 'Catalogo parametrizable de clasificacion IoT. Umbrales = supuestos de diseno del equipo.';

CREATE TABLE IF NOT EXISTS CORE.DIM_DISPOSITIVO_IOT (
  dispositivo_key    NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  device_id          VARCHAR(20) NOT NULL,
  tipo_sensor        VARCHAR(30),
  primera_lectura_ts TIMESTAMP_NTZ,
  ultima_lectura_ts  TIMESTAMP_NTZ,
  CONSTRAINT pk_dim_dispositivo PRIMARY KEY (dispositivo_key),
  CONSTRAINT uq_dim_dispositivo UNIQUE (device_id)
);

CREATE TABLE IF NOT EXISTS CORE.FACT_TELEMETRIA_IOT (
  dispositivo_key        NUMBER(38,0) NOT NULL,
  lectura_ts             TIMESTAMP_NTZ NOT NULL,
  fecha_key              NUMBER(8,0) NOT NULL,
  latitud                FLOAT,
  longitud               FLOAT,
  temperatura_c          FLOAT,
  velocidad_kmh          FLOAT,
  desvio_km              FLOAT,
  perfil_termico         VARCHAR(20),
  pedido_principal_id    VARCHAR,
  clasif_termica_key     NUMBER(38,0),
  clasif_movimiento_key  NUMBER(38,0),
  clasif_calidad_key     NUMBER(38,0),
  _lote                  VARCHAR(10),
  _fecha_stage           TIMESTAMP_NTZ,
  _fecha_carga           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_fact_tel PRIMARY KEY (dispositivo_key, lectura_ts),
  CONSTRAINT fk_ft_disp  FOREIGN KEY (dispositivo_key) REFERENCES CORE.DIM_DISPOSITIVO_IOT (dispositivo_key),
  CONSTRAINT fk_ft_fecha FOREIGN KEY (fecha_key) REFERENCES CORE.DIM_FECHA (fecha_key),
  CONSTRAINT fk_ft_ct    FOREIGN KEY (clasif_termica_key) REFERENCES CORE.DIM_CLASIFICACION_IOT (clasificacion_key),
  CONSTRAINT fk_ft_cm    FOREIGN KEY (clasif_movimiento_key) REFERENCES CORE.DIM_CLASIFICACION_IOT (clasificacion_key),
  CONSTRAINT fk_ft_cc    FOREIGN KEY (clasif_calidad_key) REFERENCES CORE.DIM_CLASIFICACION_IOT (clasificacion_key)
);

CREATE TABLE IF NOT EXISTS CORE.PUENTE_ENTREGA_DISPOSITIVO (
  pedido_id        VARCHAR NOT NULL,
  dispositivo_key  NUMBER(38,0) NOT NULL,
  inicio_ts        TIMESTAMP_NTZ,
  fin_ts           TIMESTAMP_NTZ,
  n_lecturas       NUMBER(38,0),
  CONSTRAINT pk_puente PRIMARY KEY (pedido_id, dispositivo_key),
  CONSTRAINT fk_puente_disp FOREIGN KEY (dispositivo_key) REFERENCES CORE.DIM_DISPOSITIVO_IOT (dispositivo_key)
);

-- Catalogo (MERGE: re-ejecutar actualiza umbrales sin duplicar)
MERGE INTO CORE.DIM_CLASIFICACION_IOT t
USING (
  SELECT * FROM (VALUES
   ('TERMICO','REFRIGERADO','NORMAL',  2,    8,    NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Refrigerado: 2 a menos de 8 C'),
   ('TERMICO','REFRIGERADO','ALERTA',  0,    12,   NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Refrigerado: 0 a menos de 12 C y fuera del rango normal'),
   ('TERMICO','REFRIGERADO','CRITICO', NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Refrigerado: fuera del rango de alerta'),
   ('TERMICO','CONTROLADO','NORMAL',   15,   25,   NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Perfumeria, salud y belleza: 15 a menos de 25 C'),
   ('TERMICO','CONTROLADO','ALERTA',   10,   30,   NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Controlado: 10 a menos de 30 C y fuera del rango normal'),
   ('TERMICO','CONTROLADO','CRITICO',  NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Controlado: fuera del rango de alerta'),
   ('TERMICO','AMBIENTE','NORMAL',     10,   32,   NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Ambiente: 10 a menos de 32 C'),
   ('TERMICO','AMBIENTE','ALERTA',     5,    38,   NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Ambiente: 5 a menos de 38 C y fuera del rango normal'),
   ('TERMICO','AMBIENTE','CRITICO',    NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Ambiente: fuera del rango de alerta'),
   ('MOVIMIENTO','*','EN_RUTA',        NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Avanza sobre la ruta esperada'),
   ('MOVIMIENTO','*','DETENIDO',       NULL, NULL, 0,3,       NULL,NULL, NULL,NULL, NULL, 'Velocidad menor a 3 km/h'),
   ('MOVIMIENTO','*','DESVIO',         NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, 30,   'Distancia a la ruta vendedor-cliente de 30 km o mas'),
   ('CALIDAD','*','VALIDA',            NULL, NULL, NULL,NULL, NULL,NULL, NULL,NULL, NULL, 'Lectura sin anomalias'),
   ('CALIDAD','*','SOSPECHOSA',        -30,  60,   0,120,     NULL,NULL, NULL,NULL, NULL, 'Temperatura fuera de -30..60 C o velocidad fuera de 0..120 km/h'),
   ('CALIDAD','*','RECHAZADA',         -60,  80,   NULL,NULL, -34,6,     -74,-34,   NULL, 'Temperatura fuera de -60..80 C, coordenadas fuera de Brasil o campos nulos')
  ) AS v(dimension, perfil, clase, temp_min, temp_max, vel_min, vel_max,
         lat_min, lat_max, lon_min, lon_max, desvio_min_km, descripcion)
) s
ON t.dimension = s.dimension AND t.perfil = s.perfil AND t.clase = s.clase
WHEN MATCHED THEN UPDATE SET
  temp_min = s.temp_min, temp_max = s.temp_max, vel_min = s.vel_min, vel_max = s.vel_max,
  lat_min = s.lat_min, lat_max = s.lat_max, lon_min = s.lon_min, lon_max = s.lon_max,
  desvio_min_km = s.desvio_min_km, descripcion = s.descripcion
WHEN NOT MATCHED THEN INSERT
  (dimension, perfil, clase, temp_min, temp_max, vel_min, vel_max,
   lat_min, lat_max, lon_min, lon_max, desvio_min_km, descripcion)
VALUES
  (s.dimension, s.perfil, s.clase, s.temp_min, s.temp_max, s.vel_min, s.vel_max,
   s.lat_min, s.lat_max, s.lon_min, s.lon_max, s.desvio_min_km, s.descripcion);

SELECT * FROM CORE.DIM_CLASIFICACION_IOT ORDER BY clasificacion_key;   -- 15 filas