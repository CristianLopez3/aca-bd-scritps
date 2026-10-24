-- ==============================================================================
-- 04_procedimientos.sql: procedimientos almacenados y funciones de reporte
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- SP1. Crear un pedido completo en una sola transacción.
--      p_items: '[{"producto_id": "<uuid>", "cantidad": 2}, ...]'
--      Si cualquier línea falla (p. ej. sin stock) se revierte TODO el pedido.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_cliente   UUID,
    p_direccion UUID,
    p_items     JSONB,
    INOUT p_pedido_id UUID DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_item RECORD;
BEGIN
    -- La dirección debe pertenecer al cliente
    IF NOT EXISTS (SELECT 1 FROM direccion WHERE id = p_direccion AND cliente_id = p_cliente) THEN
        RAISE EXCEPTION 'La dirección % no pertenece al cliente %', p_direccion, p_cliente;
    END IF;

    IF p_items IS NULL THEN
        RAISE EXCEPTION 'p_items no puede ser NULL';
    ELSIF jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    ELSIF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El pedido debe tener al menos un producto';
    END IF;

    INSERT INTO pedido (cliente_id, direccion_id)
    VALUES (p_cliente, p_direccion)
    RETURNING id INTO p_pedido_id;

    -- Si el mismo producto llega repetido se agrupa la cantidad: la PK de
    -- detalle_pedido es (pedido_id, producto_id) y no admite dos filas iguales.
    FOR v_item IN
        SELECT (i->>'producto_id')::UUID  AS producto_id,
               SUM((i->>'cantidad')::INT) AS cantidad
          FROM jsonb_array_elements(p_items) AS i
         GROUP BY (i->>'producto_id')::UUID
         ORDER BY (i->>'producto_id')::UUID
    LOOP
        IF v_item.producto_id IS NULL OR v_item.cantidad IS NULL OR v_item.cantidad <= 0 THEN
            RAISE EXCEPTION 'Ítem inválido en p_items: %', v_item;
        END IF;

        -- precio_unitario y subtotal los calcula trg_validar_descontar_stock
        INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
        VALUES (p_pedido_id, v_item.producto_id, v_item.cantidad, 0, 0);
    END LOOP;

    RAISE NOTICE 'Pedido % creado', p_pedido_id;
END $$;

-- ------------------------------------------------------------------------------
-- SP2. Cancelar un pedido y devolver el stock al inventario.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_pedido(p_pedido_id UUID)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado VARCHAR(12);
BEGIN
    SELECT estado INTO v_estado FROM pedido WHERE id = p_pedido_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido % no existe', p_pedido_id;
    ELSIF v_estado IN ('ENVIADO', 'ENTREGADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'No se puede cancelar un pedido en estado %', v_estado;
    END IF;

    UPDATE producto p
       SET stock = p.stock + d.cantidad
      FROM detalle_pedido d
     WHERE d.pedido_id = p_pedido_id AND d.producto_id = p.id;

    UPDATE pago   SET estado = 'REEMBOLSADO' WHERE pedido_id = p_pedido_id AND estado = 'APROBADO';
    UPDATE pedido SET estado = 'CANCELADO'   WHERE id = p_pedido_id;

    RAISE NOTICE 'Pedido % cancelado y stock devuelto', p_pedido_id;
END $$;

-- ------------------------------------------------------------------------------
-- SP3. Ajuste masivo de precios de una tienda (cada cambio queda auditado por T3).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_ajustar_precios_tienda(p_tienda_id UUID, p_porcentaje NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_porcentaje <= -100 THEN
        RAISE EXCEPTION 'Porcentaje inválido: %', p_porcentaje;
    END IF;

    UPDATE producto
       SET precio = ROUND(precio * (1 + p_porcentaje / 100), 2)
     WHERE tienda_id = p_tienda_id AND activo;
END $$;

-- ------------------------------------------------------------------------------
-- F1. Reporte de ventas por tienda en un rango de fechas (para administradores).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ventas_por_tienda(p_desde DATE, p_hasta DATE)
RETURNS TABLE (tienda TEXT, pedidos BIGINT, unidades BIGINT, ingresos NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT t.nombre::TEXT,
           COUNT(DISTINCT pe.id),
           SUM(d.cantidad),
           SUM(d.subtotal)
      FROM detalle_pedido d
      JOIN pedido   pe ON pe.id = d.pedido_id
      JOIN producto pr ON pr.id = d.producto_id
      JOIN tienda   t  ON t.id  = pr.tienda_id
     WHERE pe.estado <> 'CANCELADO'
       AND pe.fecha >= p_desde AND pe.fecha < p_hasta + 1
     GROUP BY t.nombre
     ORDER BY 4 DESC;
$$;
