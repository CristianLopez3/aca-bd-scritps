-- ==============================================================================
-- 02_seed.sql: datos de prueba
-- ==============================================================================

INSERT INTO cliente (nombre, email, telefono) VALUES
  ('Laura Gómez',   'laura.gomez@mail.com',   '3001234567'),
  ('Andrés Pérez',  'andres.perez@mail.com',  '3109876543'),
  ('Valentina Ruiz','valentina.ruiz@mail.com','3205554433');

-- Varios domicilios por cliente
INSERT INTO direccion (cliente_id, alias, linea, ciudad, departamento, codigo_postal, es_principal) VALUES
  (1, 'Casa',    'Cra 7 # 45-10',        'Bogotá',   'Cundinamarca', '110231', true),
  (1, 'Oficina', 'Cl 100 # 19-61 Of 802','Bogotá',   'Cundinamarca', '110111', false),
  (2, 'Casa',    'Cl 10 # 43-20',        'Medellín', 'Antioquia',    '050021', true),
  (3, 'Casa',    'Av 6N # 23-50',        'Cali',     'Valle',        '760045', true),
  (3, 'Padres',  'Cra 15 # 8-30',        'Palmira',  'Valle',        '763533', false);

INSERT INTO tienda (nombre, nit) VALUES
  ('TecnoAndina',    '900123456-1'),
  ('ModaUrbana',     '900654321-2'),
  ('HogarFácil',     '900777888-3');

INSERT INTO administrador (nombre, email, rol) VALUES
  ('Carlos Rojas',  'carlos@tecnoandina.co', 'PROPIETARIO'),
  ('Diana Torres',  'diana@tecnoandina.co',  'EDITOR'),
  ('Sofía Medina',  'sofia@modaurbana.co',   'PROPIETARIO'),
  ('Julián Castro', 'julian@soporte.co',     'EDITOR');

-- Múltiples administradores por tienda; Julián administra dos tiendas
INSERT INTO tienda_administrador (tienda_id, administrador_id) VALUES
  (1, 1), (1, 2), (2, 3), (2, 4), (3, 4);

INSERT INTO categoria (nombre, categoria_padre_id) VALUES
  ('Tecnología', NULL), ('Moda', NULL), ('Hogar', NULL);
INSERT INTO categoria (nombre, categoria_padre_id) VALUES
  ('Celulares', 1), ('Portátiles', 1), ('Camisetas', 2), ('Cocina', 3);

INSERT INTO producto (tienda_id, categoria_id, sku, nombre, precio, stock, atributos) VALUES
  (1, 4, 'CEL-001', 'Smartphone X12 128GB',  1499000, 25, '{"color": "negro", "ram_gb": 8}'),
  (1, 5, 'POR-001', 'Portátil Pro 14"',      3299000, 10, '{"ram_gb": 16, "ssd_gb": 512}'),
  (2, 6, 'CAM-001', 'Camiseta básica algodón', 49900, 100, '{"talla": "M", "color": "blanco"}'),
  (2, 6, 'CAM-002', 'Camiseta estampada',      69900, 3,   '{"talla": "L", "color": "azul"}'),
  (3, 7, 'COC-001', 'Olla a presión 6L',      189900, 15, '{"material": "acero inoxidable"}');
