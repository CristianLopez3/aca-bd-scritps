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
    v_estado VARCHAR(12);
BEGIN
    -- Solo se agregan líneas mientras el pedido está PENDIENTE
    SELECT estado INTO v_estado FROM pedido WHERE id = NEW.pedido_id;
    IF v_estado IS DISTINCT FROM 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se pueden agregar líneas a un pedido PENDIENTE (pedido % está %)',
            NEW.pedido_id, COALESCE(v_estado, 'INEXISTENTE');
    END IF;

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
-- T1b. Ajustar el inventario y el subtotal cuando cambia la cantidad de una
--      línea. Sin esto, un UPDATE deja stock y subtotal desincronizados.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_ajustar_stock_update() RETURNS trigger AS $$
DECLARE
    v_estado VARCHAR(12);
BEGIN
    SELECT estado INTO v_estado FROM pedido WHERE id = OLD.pedido_id;
    IF v_estado IS DISTINCT FROM 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se pueden modificar líneas de un pedido PENDIENTE (pedido % está %)',
            OLD.pedido_id, COALESCE(v_estado, 'INEXISTENTE');
    END IF;

    IF NEW.pedido_id <> OLD.pedido_id THEN
        RAISE EXCEPTION 'No se puede mover una línea a otro pedido';
    END IF;

    IF NEW.producto_id <> OLD.producto_id THEN
        RAISE EXCEPTION 'No se puede cambiar el producto de una línea de pedido';
    END IF;

    IF NEW.cantidad <> OLD.cantidad THEN
        -- Mismo patrón atómico que el INSERT: el WHERE condicional evita sobreventa
        UPDATE producto
           SET stock = stock + OLD.cantidad - NEW.cantidad
         WHERE id = NEW.producto_id
           AND stock + OLD.cantidad - NEW.cantidad >= 0;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Stock insuficiente para el producto % (pedido %)',
                NEW.producto_id, NEW.pedido_id;
        END IF;
    END IF;

    -- El precio histórico no se renegocia; el subtotal depende de la cantidad
    NEW.precio_unitario := OLD.precio_unitario;
    NEW.subtotal        := NEW.cantidad * OLD.precio_unitario;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ajustar_stock_update
BEFORE UPDATE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_ajustar_stock_update();

-- ------------------------------------------------------------------------------
-- T1c. Devolver las unidades al inventario cuando se elimina una línea.
--      Solo se permite mientras el pedido está PENDIENTE: un pedido cobrado,
--      enviado o cancelado es historial y no se modifica.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_devolver_stock_delete() RETURNS trigger AS $$
DECLARE
    v_estado VARCHAR(12);
BEGIN
    SELECT estado INTO v_estado FROM pedido WHERE id = OLD.pedido_id;

    IF v_estado IS DISTINCT FROM 'PENDIENTE' THEN
        RAISE EXCEPTION 'Solo se pueden quitar líneas de un pedido PENDIENTE (pedido % está %)',
            OLD.pedido_id, COALESCE(v_estado, 'INEXISTENTE');
    END IF;

    UPDATE producto SET stock = stock + OLD.cantidad WHERE id = OLD.producto_id;
    RETURN OLD;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_devolver_stock_delete
AFTER DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_devolver_stock_delete();

-- ------------------------------------------------------------------------------
-- T2. Mantener pedido.total sincronizado con sus líneas de detalle.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalcular_total() RETURNS trigger AS $$
DECLARE
    v_pedido UUID := COALESCE(NEW.pedido_id, OLD.pedido_id);
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

-- ------------------------------------------------------------------------------
-- T5. Validar el pago antes de registrarlo: el pedido debe existir, no puede
--     estar cancelado y el monto debe coincidir con el total del pedido.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validar_pago() RETURNS trigger AS $$
DECLARE
    v_estado VARCHAR(12);
    v_total  NUMERIC(14,2);
BEGIN
    SELECT estado, total INTO v_estado, v_total
      FROM pedido WHERE id = NEW.pedido_id
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El pedido % no existe', NEW.pedido_id;
    END IF;

    IF v_estado = 'CANCELADO' THEN
        RAISE EXCEPTION 'No se puede registrar un pago para el pedido %: está CANCELADO',
            NEW.pedido_id;
    END IF;

    IF NEW.estado = 'APROBADO' AND NEW.monto <> v_total THEN
        RAISE EXCEPTION 'El monto del pago (%) no coincide con el total del pedido % (%)',
            NEW.monto, NEW.pedido_id, v_total;
    END IF;

    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_pago
BEFORE INSERT OR UPDATE ON pago
FOR EACH ROW EXECUTE FUNCTION fn_validar_pago();
