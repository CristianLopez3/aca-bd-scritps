-- ==============================================================================
-- 03_triggers.sql: disparadores que automatizan procesos del negocio
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- T1. Validar y descontar stock al agregar un producto a un pedido.
--     Fija también el precio histórico y el subtotal de la línea.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_descontar_stock() RETURNS trigger AS $$
DECLARE
    v_precio NUMERIC(12,2);
BEGIN
    -- UPDATE condicional: atómico frente a compras concurrentes del mismo producto
    UPDATE producto
       SET stock = stock - NEW.cantidad
     WHERE id = NEW.producto_id AND activo AND stock >= NEW.cantidad
    RETURNING precio INTO v_precio;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock insuficiente o producto inactivo (producto_id=%)', NEW.producto_id;
    END IF;

    NEW.precio_unitario := v_precio;
    NEW.subtotal        := NEW.cantidad * v_precio;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_descontar_stock
BEFORE INSERT ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_validar_descontar_stock();

-- ------------------------------------------------------------------------------
-- T2. Mantener pedido.total sincronizado con sus líneas de detalle.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalcular_total() RETURNS trigger AS $$
DECLARE
    v_pedido INT := COALESCE(NEW.pedido_id, OLD.pedido_id);
BEGIN
    UPDATE pedido
       SET total = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_pedido WHERE pedido_id = v_pedido)
     WHERE id = v_pedido;
    RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recalcular_total
AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_recalcular_total();

-- ------------------------------------------------------------------------------
-- T3. Auditar cada cambio de precio de un producto.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auditar_precio() RETURNS trigger AS $$
BEGIN
    INSERT INTO auditoria_precio (producto_id, precio_anterior, precio_nuevo)
    VALUES (NEW.id, OLD.precio, NEW.precio);
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditar_precio
AFTER UPDATE OF precio ON producto
FOR EACH ROW WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION fn_auditar_precio();

-- ------------------------------------------------------------------------------
-- T4. Al registrar un pago aprobado, marcar el pedido como PAGADO.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_pago_actualiza_pedido() RETURNS trigger AS $$
BEGIN
    IF NEW.estado = 'APROBADO' THEN
        UPDATE pedido SET estado = 'PAGADO' WHERE id = NEW.pedido_id AND estado = 'PENDIENTE';
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pago_actualiza_pedido
AFTER INSERT ON pago
FOR EACH ROW EXECUTE FUNCTION fn_pago_actualiza_pedido();
