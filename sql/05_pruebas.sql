-- ==============================================================================
-- 05_pruebas.sql: demostración de triggers y SP (evidencia para el informe)
-- Ejecutar con: docker compose exec -T database psql -U dba_admin -d ecommerce_db -f /sql/05_pruebas.sql
-- ==============================================================================
\set ON_ERROR_STOP off
\pset border 2

\echo '=== P1. Stock inicial ==='
SELECT id, sku, nombre, precio, stock FROM producto ORDER BY id;

\echo '=== P2. sp_crear_pedido: Laura compra 2 celulares + 1 portátil (envío a Oficina) ==='
CALL sp_crear_pedido(1, 2, '[{"producto_id": 1, "cantidad": 2}, {"producto_id": 2, "cantidad": 1}]');
SELECT id, cliente_id, direccion_id, estado, total FROM pedido ORDER BY id;
SELECT * FROM detalle_pedido ORDER BY pedido_id, producto_id;
\echo '--- Stock descontado por trg_validar_descontar_stock (celular 25->23, portátil 10->9):'
SELECT id, sku, stock FROM producto WHERE id IN (1, 2) ORDER BY id;

\echo '=== P3. Pedido SIN stock: Andrés pide 5 camisetas estampadas (stock 3) -> debe fallar y revertir todo ==='
CALL sp_crear_pedido(2, 3, '[{"producto_id": 3, "cantidad": 1}, {"producto_id": 4, "cantidad": 5}]');
\echo '--- No se creó el pedido ni se descontó la camiseta básica (sigue en 100):'
SELECT count(*) AS pedidos_totales FROM pedido;
SELECT id, sku, stock FROM producto WHERE id IN (3, 4) ORDER BY id;

\echo '=== P4. Dirección ajena: Andrés intenta enviar a la casa de Laura -> debe fallar ==='
CALL sp_crear_pedido(2, 1, '[{"producto_id": 3, "cantidad": 1}]');

\echo '=== P5. Pago aprobado -> trg_pago_actualiza_pedido marca el pedido como PAGADO ==='
INSERT INTO pago (pedido_id, metodo, monto) SELECT id, 'PSE', total FROM pedido WHERE id = 1;
SELECT id, estado, total FROM pedido WHERE id = 1;

\echo '=== P6. Otros pedidos válidos ==='
CALL sp_crear_pedido(2, 3, '[{"producto_id": 3, "cantidad": 4}, {"producto_id": 4, "cantidad": 3}]');
CALL sp_crear_pedido(3, 5, '[{"producto_id": 5, "cantidad": 2}]');
SELECT id, cliente_id, estado, total FROM pedido ORDER BY id;

\echo '=== P7. sp_cancelar_pedido(4) (el id 2 lo consumió el pedido fallido de P3): la olla vuelve al inventario (13 -> 15) ==='
SELECT id, sku, stock FROM producto WHERE id = 5;
CALL sp_cancelar_pedido(4);
SELECT id, sku, stock FROM producto WHERE id = 5;
SELECT id, estado FROM pedido WHERE id = 4;

\echo '=== P8. No se puede cancelar dos veces -> debe fallar ==='
CALL sp_cancelar_pedido(4);

\echo '=== P9. sp_ajustar_precios_tienda: TecnoAndina sube 10% -> trg_auditar_precio registra cada cambio ==='
CALL sp_ajustar_precios_tienda(1, 10);
SELECT producto_id, precio_anterior, precio_nuevo, usuario FROM auditoria_precio ORDER BY id;
\echo '--- El pedido 1 conserva el precio histórico (precio_unitario sin cambios):'
SELECT pedido_id, producto_id, precio_unitario FROM detalle_pedido WHERE pedido_id = 1;

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
