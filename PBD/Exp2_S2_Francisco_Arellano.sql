-- DEFINICIÓN DE VARIABLE BIND PARA LA FECHA DE PROCESO
VARIABLE b_fecha_proceso VARCHAR2(10);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'DD/MM/YYYY');

DECLARE
    -- USO DE VARIABLES %TYPE
    v_run_emp           empleado.numrun_emp%TYPE;
    v_dv_emp            empleado.dvrun_emp%TYPE;
    v_pnombre           empleado.pnombre_emp%TYPE;
    v_appaterno         empleado.appaterno_emp%TYPE;
    v_sueldo            empleado.sueldo_base%TYPE;
    v_fecha_nac         empleado.fecha_nac%TYPE;
    v_fecha_cont        empleado.fecha_contrato%TYPE;

    -- Variables escalares auxiliares
    v_nombre_est_civil  estado_civil.nombre_estado_civil%TYPE;
    v_id_emp            empleado.id_emp%TYPE;
    v_nombre_completo   VARCHAR2(100);

    -- Variables para cálculos
    v_usuario_gen       usuario_clave.nombre_usuario%TYPE;
    v_clave_gen         usuario_clave.clave_usuario%TYPE;
    v_annos_trabajados  NUMBER(3);
    v_letras_civil      VARCHAR2(2);
    v_fecha_proc        DATE;

    -- Control de iteraciones y validación
    v_total_registros   NUMBER;
    v_contador_proc     NUMBER := 0;

BEGIN
    -- 1. TRUNCADO DE TABLA
    EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';

    -- Convertimos la variable Bind a Date para usarla en cálculos
    v_fecha_proc := TO_DATE(:b_fecha_proceso, 'DD/MM/YYYY');

    -- Obtenemos el total de empleados para validar la transacción al final
    SELECT COUNT(*) INTO v_total_registros FROM empleado;

    -- 2. ITERACION
    FOR r_emp IN (
        SELECT e.id_emp, e.numrun_emp, e.dvrun_emp, e.pnombre_emp, e.snombre_emp,
               e.appaterno_emp, e.apmaterno_emp, e.sueldo_base, e.fecha_nac,
               e.fecha_contrato, ec.nombre_estado_civil
        FROM empleado e
        JOIN estado_civil ec ON e.id_estado_civil = ec.id_estado_civil
        ORDER BY e.id_emp ASC
    ) LOOP
        -- Asignacion de valores a variables locales para limpieza del código
        v_id_emp := r_emp.id_emp;
        v_run_emp := r_emp.numrun_emp;
        v_dv_emp := r_emp.dvrun_emp;
        v_pnombre := r_emp.pnombre_emp;
        v_appaterno := r_emp.appaterno_emp;
        v_sueldo := r_emp.sueldo_base;
        v_fecha_nac := r_emp.fecha_nac;
        v_fecha_cont := r_emp.fecha_contrato;
        v_nombre_est_civil := r_emp.nombre_estado_civil;

        -- Construccion nombre completo para insertar luego
        v_nombre_completo := v_pnombre || ' ' || r_emp.snombre_emp || ' ' || v_appaterno || ' ' || r_emp.apmaterno_emp;
        -- Limpieza de espacios dobles si no tiene segundo nombre
        v_nombre_completo := REPLACE(v_nombre_completo, '  ', ' ');

        /*
        LOGICA DE CREACION DE NOMBRE DE USUARIO
          a) 1ra letra estado civil (minúscula)
          b) 3 primeras letras primer nombre
          c) Largo del primer nombre
          d) Asterisco *
          e) Último dígito sueldo base
          f) Dígito verificador
          g) Años trabajando
          h) Si años < 10 agregar 'X'
        */

        -- Calculo de años trabajados
        v_annos_trabajados := TRUNC(MONTHS_BETWEEN(v_fecha_proc, v_fecha_cont) / 12);

        v_usuario_gen :=
            SUBSTR(LOWER(v_nombre_est_civil), 1, 1) ||                -- a
            SUBSTR(v_pnombre, 1, 3) ||                                -- b
            TO_CHAR(LENGTH(v_pnombre)) ||                             -- c
            '*' ||                                                    -- d
            SUBSTR(TO_CHAR(v_sueldo), -1) ||                          -- e
            v_dv_emp ||                                               -- f
            TO_CHAR(v_annos_trabajados);                              -- g

        IF v_annos_trabajados < 10 THEN
            v_usuario_gen := v_usuario_gen || 'X';                    -- h
        END IF;

        /*
        LÓGICA DE CREACIÓN DE CLAVE (Pauta paso 1)
          a) 3er dígito del RUN
          b) Año nacimiento + 2
          c) Últimos 3 dígitos sueldo - 1
          d) Letras apellido según estado civil
          e) ID empleado
          f) Mes y Año de la BD (MMYYYY)
        */

        -- Lógica condicional para las letras del apellido
        IF v_nombre_est_civil IN ('CASADO', 'ACUERDO DE UNION CIVIL') THEN
            v_letras_civil := SUBSTR(LOWER(v_appaterno), 1, 2);
        ELSIF v_nombre_est_civil IN ('DIVORCIADO', 'SOLTERO') THEN
            v_letras_civil := SUBSTR(LOWER(v_appaterno), 1, 1) || SUBSTR(LOWER(v_appaterno), -1);
        ELSIF v_nombre_est_civil = 'VIUDO' THEN
            -- Antepenultma (-3) y Penultima (-2)
            v_letras_civil := SUBSTR(LOWER(v_appaterno), -3, 1) || SUBSTR(LOWER(v_appaterno), -2, 1);
        ELSIF v_nombre_est_civil = 'SEPARADO' THEN
            v_letras_civil := SUBSTR(LOWER(v_appaterno), -2);
        ELSE
            v_letras_civil := 'xx';
        END IF;

        v_clave_gen :=
            SUBSTR(TO_CHAR(v_run_emp), 3, 1) ||                                     -- a
            TO_CHAR(TO_NUMBER(TO_CHAR(v_fecha_nac, 'YYYY')) + 2) ||                 -- b
            TO_CHAR(TO_NUMBER(SUBSTR(TO_CHAR(v_sueldo), -3)) - 1) ||                -- c
            v_letras_civil ||                                                       -- d
            TO_CHAR(v_id_emp) ||                                                    -- e
            TO_CHAR(v_fecha_proc, 'MMYYYY');                                        -- f

        -- 3. INSERCION DE DATOS
        -- Se insertan los valores calculados en la tabla de resultados final.
        INSERT INTO USUARIO_CLAVE (id_emp, numrun_emp, dvrun_emp, nombre_empleado, nombre_usuario, clave_usuario)
        VALUES (v_id_emp, v_run_emp, v_dv_emp, v_nombre_completo, v_usuario_gen, v_clave_gen);

        -- Incremento contador
        v_contador_proc := v_contador_proc + 1;

    END LOOP;

    -- 4. CONFIRMACIÓN DE TRANSACCION
    IF v_contador_proc = v_total_registros THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Proceso finalizado exitosamente. Registros procesados: ' || v_contador_proc);
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error en el proceso. No coinciden los registros.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM);
END;
/

-- Consulta final
SELECT * FROM USUARIO_CLAVE ORDER BY id_emp;