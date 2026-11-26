USE ROLE SYSADMIN;
USE WAREHOUSE WH_TRANSFORMACION;
USE DATABASE DWH_OLIST;

CREATE OR REPLACE TABLE CORE.DIM_FECHA (
  fecha_key         NUMBER(8,0) NOT NULL,
  fecha             DATE        NOT NULL,
  anio              NUMBER(4,0) NOT NULL,
  trimestre         NUMBER(1,0) NOT NULL,
  mes               NUMBER(2,0) NOT NULL,
  nombre_mes        VARCHAR(10),
  dia               NUMBER(2,0) NOT NULL,
  dia_semana        NUMBER(1,0) NOT NULL,
  nombre_dia        VARCHAR(10),
  es_fin_de_semana  BOOLEAN,
  CONSTRAINT pk_dim_fecha PRIMARY KEY (fecha_key)
);

CREATE OR REPLACE TABLE CORE.DIM_GEOGRAFIA (
  geografia_key  NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  zip_prefix     VARCHAR(5) NOT NULL,
  ciudad         VARCHAR,
  estado         VARCHAR(2),
  latitud        FLOAT,
  longitud       FLOAT,
  n_puntos       NUMBER(38,0),
  CONSTRAINT pk_dim_geografia PRIMARY KEY (geografia_key),
  CONSTRAINT uq_dim_geografia_zip UNIQUE (zip_prefix)
);

CREATE OR REPLACE TABLE CORE.DIM_CLIENTE (
  cliente_key         NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  customer_id         VARCHAR NOT NULL,
  customer_unique_id  VARCHAR,
  geografia_key       NUMBER(38,0),
  CONSTRAINT pk_dim_cliente PRIMARY KEY (cliente_key),
  CONSTRAINT uq_dim_cliente_id UNIQUE (customer_id),
  CONSTRAINT fk_cliente_geo FOREIGN KEY (geografia_key) REFERENCES CORE.DIM_GEOGRAFIA (geografia_key)
);

CREATE OR REPLACE TABLE CORE.DIM_VENDEDOR (
  vendedor_key   NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  seller_id      VARCHAR NOT NULL,
  geografia_key  NUMBER(38,0),
  CONSTRAINT pk_dim_vendedor PRIMARY KEY (vendedor_key),
  CONSTRAINT uq_dim_vendedor_id UNIQUE (seller_id),
  CONSTRAINT fk_vendedor_geo FOREIGN KEY (geografia_key) REFERENCES CORE.DIM_GEOGRAFIA (geografia_key)
);

CREATE OR REPLACE TABLE CORE.DIM_CATEGORIA (
  categoria_key        NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  categoria_pt         VARCHAR NOT NULL,
  categoria_en         VARCHAR,
  origen_traduccion    VARCHAR(20),
  CONSTRAINT pk_dim_categoria PRIMARY KEY (categoria_key),
  CONSTRAINT uq_dim_categoria_pt UNIQUE (categoria_pt)
);

CREATE OR REPLACE TABLE CORE.DIM_PRODUCTO (
  producto_key          NUMBER(38,0) AUTOINCREMENT START 1 INCREMENT 1,
  product_id            VARCHAR NOT NULL,
  categoria_key         NUMBER(38,0),
  longitud_nombre       NUMBER(6,0),
  longitud_descripcion  NUMBER(8,0),
  num_fotos             NUMBER(4,0),
  peso_g                NUMBER(10,0),
  largo_cm              NUMBER(8,0),
  alto_cm               NUMBER(8,0),
  ancho_cm              NUMBER(8,0),
  CONSTRAINT pk_dim_producto PRIMARY KEY (producto_key),
  CONSTRAINT uq_dim_producto_id UNIQUE (product_id),
  CONSTRAINT fk_producto_categoria FOREIGN KEY (categoria_key) REFERENCES CORE.DIM_CATEGORIA (categoria_key)
);

CREATE OR REPLACE TABLE CORE.FACT_ITEM_PEDIDO (
  pedido_id                     VARCHAR NOT NULL,
  item_numero                   NUMBER(4,0) NOT NULL,
  producto_key                  NUMBER(38,0),
  vendedor_key                  NUMBER(38,0),
  cliente_key                   NUMBER(38,0),
  fecha_compra_key              NUMBER(8,0),
  fecha_entrega_estimada_key    NUMBER(8,0),
  fecha_entrega_real_key        NUMBER(8,0),
  estado_pedido                 VARCHAR(20),
  fecha_compra_ts               TIMESTAMP_NTZ,
  fecha_envio_transportista_ts  TIMESTAMP_NTZ,
  fecha_entrega_real_ts         TIMESTAMP_NTZ,
  fecha_entrega_estimada_ts     TIMESTAMP_NTZ,
  fecha_limite_envio_ts         TIMESTAMP_NTZ,
  precio                        NUMBER(12,2),
  flete                         NUMBER(12,2),
  dias_despacho                 NUMBER(6,0),
  dias_retraso                  NUMBER(6,0),
  entregado_a_tiempo            BOOLEAN,
  _fecha_carga                  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_fact_item PRIMARY KEY (pedido_id, item_numero),
  CONSTRAINT fk_fip_producto FOREIGN KEY (producto_key) REFERENCES CORE.DIM_PRODUCTO (producto_key),
  CONSTRAINT fk_fip_vendedor FOREIGN KEY (vendedor_key) REFERENCES CORE.DIM_VENDEDOR (vendedor_key),
  CONSTRAINT fk_fip_cliente  FOREIGN KEY (cliente_key)  REFERENCES CORE.DIM_CLIENTE (cliente_key),
  CONSTRAINT fk_fip_fcompra  FOREIGN KEY (fecha_compra_key) REFERENCES CORE.DIM_FECHA (fecha_key)
);

CREATE OR REPLACE TABLE CORE.FACT_PAGO (
  pedido_id         VARCHAR NOT NULL,
  pago_secuencia    NUMBER(4,0) NOT NULL,
  cliente_key       NUMBER(38,0),
  fecha_compra_key  NUMBER(8,0),
  tipo_pago         VARCHAR(20),
  cuotas            NUMBER(4,0),
  monto             NUMBER(12,2),
  _fecha_carga      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_fact_pago PRIMARY KEY (pedido_id, pago_secuencia),
  CONSTRAINT fk_fp_cliente FOREIGN KEY (cliente_key) REFERENCES CORE.DIM_CLIENTE (cliente_key),
  CONSTRAINT fk_fp_fecha   FOREIGN KEY (fecha_compra_key) REFERENCES CORE.DIM_FECHA (fecha_key)
);

CREATE OR REPLACE TABLE CORE.FACT_RESENA (
  review_id            VARCHAR NOT NULL,
  pedido_id            VARCHAR NOT NULL,
  cliente_key          NUMBER(38,0),
  fecha_creacion_key   NUMBER(8,0),
  calificacion         NUMBER(1,0),
  tiene_comentario     BOOLEAN,
  fecha_respuesta_ts   TIMESTAMP_NTZ,
  _fecha_carga         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_fact_resena PRIMARY KEY (review_id, pedido_id),
  CONSTRAINT fk_fr_cliente FOREIGN KEY (cliente_key) REFERENCES CORE.DIM_CLIENTE (cliente_key),
  CONSTRAINT fk_fr_fecha   FOREIGN KEY (fecha_creacion_key) REFERENCES CORE.DIM_FECHA (fecha_key)
);

SHOW TABLES IN SCHEMA CORE;