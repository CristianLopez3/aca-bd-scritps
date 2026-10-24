-- ==============================================================================
-- ACA: Diseñando la base de datos de una empresa emergente (e-commerce)
-- 01_schema.sql: modelo relacional en 3FN (PostgreSQL 16)
-- Materia: Administración de Bases de Datos (Semestre 8) - CUN
-- Claves primarias UUIDv7: ordenables por tiempo y no enumerables.
-- ==============================================================================

-- UUIDv7 (RFC 9562): 48 bits de timestamp en ms + version + variant + aleatorio.
-- Conserva la localidad de inserción de un BIGINT y no expone consecutivos.
CREATE OR REPLACE FUNCTION uuid_v7() RETURNS uuid
LANGUAGE sql VOLATILE AS $$
  SELECT (
           lpad(to_hex((extract(epoch FROM clock_timestamp()) * 1000)::bigint), 12, '0')
        || '7'
        || substr(h, 1, 3)
        || substr('89ab', 1 + (random() * 3)::int, 1)
        || substr(h, 4, 1)
        || substr(h, 5, 14)
         )::uuid
  FROM (SELECT replace(gen_random_uuid()::text, '-', '') AS h) AS r;
$$;

CREATE TABLE cliente (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    nombre          VARCHAR(120) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    telefono        VARCHAR(20),
    fecha_registro  TIMESTAMP    NOT NULL DEFAULT now()
);

-- Un cliente puede tener muchos domicilios de envío (1:N)
CREATE TABLE direccion (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    cliente_id      UUID         NOT NULL REFERENCES cliente(id) ON DELETE CASCADE,
    alias           VARCHAR(40)  NOT NULL,
    linea           VARCHAR(200) NOT NULL,
    ciudad          VARCHAR(80)  NOT NULL,
    departamento    VARCHAR(80)  NOT NULL,
    codigo_postal   VARCHAR(10),
    es_principal    BOOLEAN      NOT NULL DEFAULT false,
    UNIQUE (cliente_id, id)
);
-- Solo una dirección principal por cliente
CREATE UNIQUE INDEX ux_direccion_principal ON direccion(cliente_id) WHERE es_principal;

CREATE TABLE tienda (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    nombre          VARCHAR(120) NOT NULL,
    nit             VARCHAR(20)  NOT NULL UNIQUE,
    estado          VARCHAR(10)  NOT NULL DEFAULT 'ACTIVA'
                    CHECK (estado IN ('ACTIVA', 'INACTIVA'))
);

CREATE TABLE administrador (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    nombre          VARCHAR(120) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    rol             VARCHAR(20)  NOT NULL DEFAULT 'EDITOR'
                    CHECK (rol IN ('PROPIETARIO', 'EDITOR'))
);

-- Múltiples administradores por tienda y una persona puede administrar varias tiendas (N:M)
CREATE TABLE tienda_administrador (
    tienda_id        UUID      NOT NULL REFERENCES tienda(id) ON DELETE CASCADE,
    administrador_id UUID      NOT NULL REFERENCES administrador(id) ON DELETE CASCADE,
    fecha_asignacion TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (tienda_id, administrador_id)
);
CREATE INDEX ix_tienda_admin_administrador ON tienda_administrador(administrador_id);

-- Categorías jerárquicas (Tecnología > Celulares)
CREATE TABLE categoria (
    id                 UUID PRIMARY KEY DEFAULT uuid_v7(),
    nombre             VARCHAR(80) NOT NULL UNIQUE,
    categoria_padre_id UUID REFERENCES categoria(id)
);

CREATE TABLE producto (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    tienda_id       UUID          NOT NULL REFERENCES tienda(id),
    categoria_id    UUID          NOT NULL REFERENCES categoria(id),
    sku             VARCHAR(30)   NOT NULL,
    nombre          VARCHAR(150)  NOT NULL,
    precio          NUMERIC(12,2) NOT NULL CHECK (precio > 0),
    stock           INT           NOT NULL DEFAULT 0 CHECK (stock >= 0),
    atributos       JSONB         NOT NULL DEFAULT '{}',
    activo          BOOLEAN       NOT NULL DEFAULT true,
    UNIQUE (tienda_id, sku)
);
CREATE INDEX ix_producto_tienda    ON producto(tienda_id);
CREATE INDEX ix_producto_atributos ON producto USING GIN (atributos);

CREATE TABLE pedido (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    cliente_id      UUID          NOT NULL REFERENCES cliente(id),
    direccion_id    UUID          NOT NULL,
    fecha           TIMESTAMP     NOT NULL DEFAULT now(),
    estado          VARCHAR(12)   NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado IN ('PENDIENTE', 'PAGADO', 'ENVIADO', 'ENTREGADO', 'CANCELADO')),
    total           NUMERIC(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_pedido_direccion_cliente
        FOREIGN KEY (cliente_id, direccion_id) REFERENCES direccion (cliente_id, id)
);
CREATE INDEX ix_pedido_cliente ON pedido(cliente_id);
CREATE INDEX ix_pedido_fecha   ON pedido(fecha);

-- precio_unitario se copia del producto: conserva el precio histórico de la compra
CREATE TABLE detalle_pedido (
    pedido_id       UUID          NOT NULL REFERENCES pedido(id),
    producto_id     UUID          NOT NULL REFERENCES producto(id),
    cantidad        INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,2) NOT NULL,
    subtotal        NUMERIC(14,2) NOT NULL,
    PRIMARY KEY (pedido_id, producto_id)
);
CREATE INDEX ix_detalle_producto ON detalle_pedido(producto_id);

CREATE TABLE pago (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    pedido_id       UUID          NOT NULL UNIQUE REFERENCES pedido(id),
    metodo          VARCHAR(20)   NOT NULL CHECK (metodo IN ('TARJETA', 'PSE', 'NEQUI', 'CONTRAENTREGA')),
    monto           NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    estado          VARCHAR(12)   NOT NULL DEFAULT 'APROBADO'
                    CHECK (estado IN ('APROBADO', 'RECHAZADO', 'REEMBOLSADO')),
    fecha           TIMESTAMP     NOT NULL DEFAULT now()
);

-- Llenada automáticamente por trigger (auditoría)
CREATE TABLE auditoria_precio (
    id              UUID PRIMARY KEY DEFAULT uuid_v7(),
    producto_id     UUID          NOT NULL REFERENCES producto(id),
    precio_anterior NUMERIC(12,2) NOT NULL,
    precio_nuevo    NUMERIC(12,2) NOT NULL,
    fecha           TIMESTAMP     NOT NULL DEFAULT now(),
    usuario         TEXT          NOT NULL DEFAULT current_user
);
