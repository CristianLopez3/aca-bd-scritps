-- ==============================================================================
-- 05_pruebas.sql: demostración de triggers y SP (evidencia para el informe)
-- Ejecutar con: docker compose exec -T database psql -U dba_admin -d ecommerce_db -f /sql/05_pruebas.sql
--
-- Idempotente: reinicia los datos y recarga 02_seed.sql al inicio.
-- Los id son UUID, así que se resuelven por clave natural al comenzar.
-- ==============================================================================
\set ON_ERROR_STOP off
\pset border 2

TRUNCATE TABLE auditoria_precio, pago, detalle_pedido, pedido,
               tienda_administrador, producto, categoria,
               administrador, tienda, direccion, cliente CASCADE;
\ir 02_seed.sql

SELECT id AS laura     FROM cliente WHERE email = 'laura.gomez@mail.com'    \gset
SELECT id AS andres    FROM cliente WHERE email = 'andres.perez@mail.com'   \gset
SELECT id AS valentina FROM cliente WHERE email = 'valentina.ruiz@mail.com' \gset
SELECT id AS dir_laura_casa FROM direccion WHERE cliente_id = :'laura' AND alias = 'Casa'    \gset
SELECT id AS dir_laura_ofi  FROM direccion WHERE cliente_id = :'laura' AND alias = 'Oficina' \gset
SELECT id AS dir_andres     FROM direccion WHERE cliente_id = :'andres' AND alias = 'Casa'   \gset
SELECT id AS dir_valentina  FROM direccion WHERE cliente_id = :'valentina' AND alias = 'Casa' \gset
SELECT id AS t_tecno FROM tienda WHERE nit = '900123456-1' \gset
SELECT id AS p_cel  FROM producto WHERE sku = 'CEL-001' \gset
SELECT id AS p_por  FROM producto WHERE sku = 'POR-001' \gset
SELECT id AS p_cam1 FROM producto WHERE sku = 'CAM-001' \gset
SELECT id AS p_cam2 FROM producto WHERE sku = 'CAM-002' \gset
SELECT id AS p_coc  FROM producto WHERE sku = 'COC-001' \gset

\echo '=== P1. Stock inicial ==='
SELECT id, sku, nombre, precio, stock FROM producto ORDER BY sku;

\echo '=== P2. sp_crear_pedido: Laura compra 2 celulares + 1 portátil (envío a Oficina) ==='
SELECT jsonb_build_array(
         jsonb_build_object('producto_id', :'p_cel', 'cantidad', 2),
         jsonb_build_object('producto_id', :'p_por', 'cantidad', 1)
       ) AS items \gset
CALL sp_crear_pedido(:'laura', :'dir_laura_ofi', :'items') \gset
\set pedido1 :p_pedido_id
SELECT id, cliente_id, direccion_id, estado, total FROM pedido ORDER BY id;
SELECT d.pedido_id, d.producto_id, d.cantidad, d.precio_unitario, d.subtotal
  FROM detalle_pedido d JOIN producto p ON p.id = d.producto_id
 WHERE d.pedido_id = :'pedido1' ORDER BY p.sku;
\echo '--- Stock descontado por trg_validar_descontar_stock (celular 25->23, portátil 10->9):'
SELECT id, sku, stock FROM producto WHERE id IN (:'p_cel', :'p_por') ORDER BY sku;

\echo '=== P3. Pedido SIN stock: Andrés pide 5 camisetas estampadas (stock 3) -> debe fallar y revertir todo ==='
SELECT jsonb_build_array(
         jsonb_build_object('producto_id', :'p_cam1', 'cantidad', 1),
         jsonb_build_object('producto_id', :'p_cam2', 'cantidad', 5)
       ) AS items \gset
CALL sp_crear_pedido(:'andres', :'dir_andres', :'items');
\echo '--- No se creó el pedido ni se descontó la camiseta básica (sigue en 100):'
SELECT count(*) AS pedidos_totales FROM pedido;
SELECT id, sku, stock FROM producto WHERE id IN (:'p_cam1', :'p_cam2') ORDER BY sku;

\echo '=== P4. Dirección ajena: Andrés intenta enviar a la casa de Laura -> debe fallar ==='
SELECT jsonb_build_array(jsonb_build_object('producto_id', :'p_cam1', 'cantidad', 1)) AS items \gset
CALL sp_crear_pedido(:'andres', :'dir_laura_casa', :'items');

\echo '=== P5. Pago aprobado -> trg_pago_actualiza_pedido marca el pedido como PAGADO ==='
INSERT INTO pago (pedido_id, metodo, monto) SELECT id, 'PSE', total FROM pedido WHERE id = :'pedido1';
SELECT id, estado, total FROM pedido WHERE id = :'pedido1';

\echo '=== P6. Otros pedidos válidos ==='
SELECT jsonb_build_array(
         jsonb_build_object('producto_id', :'p_cam1', 'cantidad', 4),
         jsonb_build_object('producto_id', :'p_cam2', 'cantidad', 3)
       ) AS items \gset
CALL sp_crear_pedido(:'andres', :'dir_andres', :'items') \gset
\set pedido3 :p_pedido_id

SELECT jsonb_build_array(jsonb_build_object('producto_id', :'p_coc', 'cantidad', 2)) AS items \gset
CALL sp_crear_pedido(:'valentina', :'dir_valentina', :'items') \gset
\set pedido4 :p_pedido_id

SELECT id, cliente_id, estado, total FROM pedido ORDER BY fecha, id;

\echo '=== P7. sp_cancelar_pedido: la olla vuelve al inventario (13 -> 15) ==='
SELECT id, sku, stock FROM producto WHERE id = :'p_coc';
CALL sp_cancelar_pedido(:'pedido4');
SELECT id, sku, stock FROM producto WHERE id = :'p_coc';
SELECT id, estado FROM pedido WHERE id = :'pedido4';

\echo '=== P8. No se puede cancelar dos veces -> debe fallar ==='
CALL sp_cancelar_pedido(:'pedido4');

\echo '=== P9. sp_ajustar_precios_tienda: TecnoAndina sube 10% -> trg_auditar_precio registra cada cambio ==='
CALL sp_ajustar_precios_tienda(:'t_tecno', 10);
SELECT a.producto_id, a.precio_anterior, a.precio_nuevo, a.usuario
  FROM auditoria_precio a JOIN producto p ON p.id = a.producto_id ORDER BY p.sku;
\echo '--- El pedido 1 conserva el precio histórico (precio_unitario sin cambios):'
SELECT pedido_id, producto_id, precio_unitario FROM detalle_pedido WHERE pedido_id = :'pedido1' ORDER BY producto_id;

\echo '=== P10. fn_ventas_por_tienda (excluye cancelados) ==='
SELECT * FROM fn_ventas_por_tienda(CURRENT_DATE - 30, CURRENT_DATE);

\echo '=== P11. Consulta JSONB: productos de talla M (flexibilidad tipo documento dentro de SQL) ==='
SELECT sku, nombre, atributos FROM producto WHERE atributos @> '{"talla": "M"}';

\echo '=== P12. Administradores por tienda (N:M) ==='
SELECT t.nombre AS tienda, string_agg(a.nombre || ' (' || a.rol || ')', ', ' ORDER BY a.nombre) AS administradores
  FROM tienda t
  JOIN tienda_administrador ta ON ta.tienda_id = t.id
  JOIN administrador a ON a.id = ta.administrador_id
 GROUP BY t.nombre ORDER BY t.nombre;

\echo '=== P13. UPDATE de cantidad: ajusta stock y recalcula subtotal (trg_ajustar_stock_update) ==='
SELECT jsonb_build_array(jsonb_build_object('producto_id', :'p_cam1', 'cantidad', 2)) AS items \gset
CALL sp_crear_pedido(:'laura', :'dir_laura_casa', :'items') \gset
\set pedido5 :p_pedido_id
SELECT id, sku, stock FROM producto WHERE id = :'p_cam1';
UPDATE detalle_pedido SET cantidad = 5 WHERE pedido_id = :'pedido5' AND producto_id = :'p_cam1';
\echo '--- Mover la línea a otro pedido debe fallar (el total del pedido origen quedaría viejo):'
UPDATE detalle_pedido SET pedido_id = :'pedido1' WHERE pedido_id = :'pedido5' AND producto_id = :'p_cam1';
SELECT pedido_id, producto_id, cantidad, precio_unitario, subtotal FROM detalle_pedido WHERE pedido_id = :'pedido5';
SELECT id, sku, stock FROM producto WHERE id = :'p_cam1';
SELECT id, total FROM pedido WHERE id = :'pedido5';

\echo '=== P14. DELETE de una línea: devuelve las unidades al inventario (trg_devolver_stock_delete) ==='
DELETE FROM detalle_pedido WHERE pedido_id = :'pedido5' AND producto_id = :'p_cam1';
SELECT id, sku, stock FROM producto WHERE id = :'p_cam1';
SELECT id, total FROM pedido WHERE id = :'pedido5';

\echo '=== P15. Pago con monto distinto al total -> debe fallar (trg_validar_pago) ==='
SELECT jsonb_build_array(jsonb_build_object('producto_id', :'p_coc', 'cantidad', 1)) AS items \gset
CALL sp_crear_pedido(:'andres', :'dir_andres', :'items') \gset
\set pedido6 :p_pedido_id
INSERT INTO pago (pedido_id, metodo, monto) VALUES (:'pedido6', 'PSE', 1.00);
SELECT id, estado, total FROM pedido WHERE id = :'pedido6';

\echo '=== P16. Pago sobre un pedido CANCELADO -> debe fallar (trg_validar_pago) ==='
INSERT INTO pago (pedido_id, metodo, monto) VALUES (:'pedido4', 'NEQUI', 379800);

\echo '=== P17. Dirección de otro cliente por INSERT directo -> debe fallar (FK compuesta) ==='
INSERT INTO pedido (cliente_id, direccion_id) VALUES (:'andres', :'dir_laura_casa');

\echo '=== P18. Ítem repetido en el JSON: se agrupa la cantidad en una sola línea ==='
SELECT jsonb_build_array(
         jsonb_build_object('producto_id', :'p_por', 'cantidad', 1),
         jsonb_build_object('producto_id', :'p_por', 'cantidad', 2)
       ) AS items \gset
CALL sp_crear_pedido(:'valentina', :'dir_valentina', :'items') \gset
\set pedido7 :p_pedido_id
SELECT pedido_id, producto_id, cantidad, subtotal FROM detalle_pedido WHERE pedido_id = :'pedido7';
SELECT id, sku, stock FROM producto WHERE id = :'p_por';

\echo '=== P19. Borrar un pedido con líneas -> debe fallar (se conserva el historial) ==='
DELETE FROM pedido WHERE id = :'pedido7';

\echo '--- Borrando primero la línea: devuelve el stock y luego el pedido vacío sí se elimina (9)'
DELETE FROM detalle_pedido WHERE pedido_id = :'pedido7';
SELECT id, sku, stock FROM producto WHERE id = :'p_por';
DELETE FROM pedido WHERE id = :'pedido7';
SELECT count(*) AS pedidos_restantes FROM pedido;

\echo '=== P20. Un pedido CANCELADO es historial: no admite cambios ni devuelve stock otra vez ==='
SELECT id, sku, stock FROM producto WHERE id = :'p_coc';
DELETE FROM detalle_pedido WHERE pedido_id = :'pedido4';
UPDATE detalle_pedido SET cantidad = 99 WHERE pedido_id = :'pedido4';
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
    VALUES (:'pedido4', :'p_coc', 1, 0, 0);
SELECT id, sku, stock FROM producto WHERE id = :'p_coc';
