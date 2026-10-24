-- ==============================================================================
-- 02_seed.sql: datos de prueba
-- Las referencias se resuelven por clave natural (email, nit, sku, nombre),
-- porque los id son UUID generados por la base.
-- ==============================================================================

INSERT INTO cliente (nombre, email, telefono) VALUES
  ('Laura Gómez',   'laura.gomez@mail.com',   '3001234567'),
  ('Andrés Pérez',  'andres.perez@mail.com',  '3109876543'),
  ('Valentina Ruiz','valentina.ruiz@mail.com','3205554433');

-- Varios domicilios por cliente
INSERT INTO direccion (cliente_id, alias, linea, ciudad, departamento, codigo_postal, es_principal)
SELECT c.id, v.alias, v.linea, v.ciudad, v.departamento, v.cp, v.principal
  FROM (VALUES
    ('laura.gomez@mail.com',   'Casa',    'Cra 7 # 45-10',         'Bogotá',   'Cundinamarca', '110231', true),
    ('laura.gomez@mail.com',   'Oficina', 'Cl 100 # 19-61 Of 802', 'Bogotá',   'Cundinamarca', '110111', false),
    ('andres.perez@mail.com',  'Casa',    'Cl 10 # 43-20',         'Medellín', 'Antioquia',    '050021', true),
    ('valentina.ruiz@mail.com','Casa',    'Av 6N # 23-50',         'Cali',     'Valle',        '760045', true),
    ('valentina.ruiz@mail.com','Padres',  'Cra 15 # 8-30',         'Palmira',  'Valle',        '763533', false)
  ) AS v(email, alias, linea, ciudad, departamento, cp, principal)
  JOIN cliente c ON c.email = v.email;

INSERT INTO tienda (nombre, nit) VALUES
  ('TecnoAndina', '900123456-1'),
  ('ModaUrbana',  '900654321-2'),
  ('HogarFácil',  '900777888-3');

INSERT INTO administrador (nombre, email, rol) VALUES
  ('Carlos Rojas',  'carlos@tecnoandina.co', 'PROPIETARIO'),
  ('Diana Torres',  'diana@tecnoandina.co',  'EDITOR'),
  ('Sofía Medina',  'sofia@modaurbana.co',   'PROPIETARIO'),
  ('Julián Castro', 'julian@soporte.co',     'EDITOR');

-- Múltiples administradores por tienda; Julián administra dos tiendas
INSERT INTO tienda_administrador (tienda_id, administrador_id)
SELECT t.id, a.id
  FROM (VALUES
    ('900123456-1', 'carlos@tecnoandina.co'),
    ('900123456-1', 'diana@tecnoandina.co'),
    ('900654321-2', 'sofia@modaurbana.co'),
    ('900654321-2', 'julian@soporte.co'),
    ('900777888-3', 'julian@soporte.co')
  ) AS v(nit, email)
  JOIN tienda t        ON t.nit = v.nit
  JOIN administrador a ON a.email = v.email;

INSERT INTO categoria (nombre) VALUES
  ('Tecnología'), ('Moda'), ('Hogar');

INSERT INTO categoria (nombre, categoria_padre_id)
SELECT v.nombre, p.id
  FROM (VALUES
    ('Celulares',  'Tecnología'),
    ('Portátiles', 'Tecnología'),
    ('Camisetas',  'Moda'),
    ('Cocina',     'Hogar')
  ) AS v(nombre, padre)
  JOIN categoria p ON p.nombre = v.padre;

INSERT INTO producto (tienda_id, categoria_id, sku, nombre, precio, stock, atributos)
SELECT t.id, c.id, v.sku, v.nombre, v.precio, v.stock, v.atributos
  FROM (VALUES
    ('900123456-1', 'Celulares',  'CEL-001', 'Smartphone X12 128GB',     1499000, 25, '{"color": "negro", "ram_gb": 8}'::jsonb),
    ('900123456-1', 'Portátiles', 'POR-001', 'Portátil Pro 14"',         3299000, 10, '{"ram_gb": 16, "ssd_gb": 512}'::jsonb),
    ('900654321-2', 'Camisetas',  'CAM-001', 'Camiseta básica algodón',    49900, 100, '{"talla": "M", "color": "blanco"}'::jsonb),
    ('900654321-2', 'Camisetas',  'CAM-002', 'Camiseta estampada',         69900, 3,   '{"talla": "L", "color": "azul"}'::jsonb),
    ('900777888-3', 'Cocina',     'COC-001', 'Olla a presión 6L',         189900, 15, '{"material": "acero inoxidable"}'::jsonb)
  ) AS v(nit, categoria, sku, nombre, precio, stock, atributos)
  JOIN tienda t    ON t.nit = v.nit
  JOIN categoria c ON c.nombre = v.categoria;
