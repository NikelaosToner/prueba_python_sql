/* Esta prueba fue hecha en Postgresql 15
 Antes de empezar hay que crear una database y seleccionarla
 (lo cual se hizo en shell y por eso no aparece aqui). 
 Posteriormente se crean las tablas e importan los csv
 */

DROP TABLE IF EXISTS bansur;
CREATE TABLE bansur (
TARJETA VARCHAR(10),		
TIPO_TRX VARCHAR(20),	
MONTO NUMERIC,	
FECHA_TRANSACCION VARCHAR(20),	 
CODIGO_AUTORIZACION	VARCHAR(30),
ID_ADQUIRIENTE BIGINT,
FECHA_RECEPCION DATE
);


COPY bansur(
TARJETA,		
TIPO_TRX,	
MONTO,	
FECHA_TRANSACCION,	 
CODIGO_AUTORIZACION,
ID_ADQUIRIENTE,
FECHA_RECEPCION
)
FROM 'C:\Program Files\PostgreSQL\15\pgAdmin 4\BANSUR.csv'
DELIMITER ','
CSV HEADER;

DROP TABLE IF EXISTS clap;
CREATE TABLE clap(
INICIO6_TARJETA VARCHAR(6),
FINAL4_TARJETA VARCHAR(4),
TIPO_TRX VARCHAR(20),
MONTO NUMERIC,
FECHA_TRANSACCION VARCHAR(40),
CODIGO_AUTORIZACION VARCHAR(20),
ID_BANCO BIGINT,
FECHA_RECEPCION_BANCO DATE
);

COPY clap(
INICIO6_TARJETA,
FINAL4_TARJETA,
TIPO_TRX,
MONTO,
FECHA_TRANSACCION,
CODIGO_AUTORIZACION,
ID_BANCO,
FECHA_RECEPCION_BANCO
)
FROM 'C:\Program Files\PostgreSQL\15\pgAdmin 4\CLAP.csv'
DELIMITER ','
CSV HEADER;

-------------------------------------- 1 PREGUNTA ---------------------------------------

/* 1 Pregunta:
 Escriba el código de SQL que le permite conocer el monto y 
 la cantidad de las transacciones que SIMETRIK considera 
 como conciliables para la base de CLAP
 */
 
/* Para responder a esta pregunta primero veamos lo que se entiende
por transacciones conciliables. Segun el criterio de negocio:

<<Simetrik considera una partida como conciliable toda aquella 
transacción cuyo último estado en la base de datos ordenada por 
fecha y hora sea PAGADA.>>

Y que es una partida? Este otro fragmento nos da una idea:

<<IMPORTANTE: Una transacción regular se evidencia en la base de datos
como un PAGO; se debe tener en cuenta que un mismo ID puede también
tomar estado de Cancelación, Chargeback u Otros casos>>

Podemos inferir que el ID es el de una partida, entendiendo partida como
una serie de intentos de pago relacionados a una transaccion, si el ultimo
de ellos temporalmente es PAGO, tenemos una transaccion conciliable.

Ahora, cual es el id en CLAP?
La columna id_banco es una excelente candidata para ser id dado que 
1. claramente se refiere a un id, 2. el conteo de sus registros (163533)
es muy similar al conteo de sus registros unicos (163523) y 3. hace un buen 
match con la columna id_adquiriente de bansur

De hecho, el conteo de registros nos arroja otra pista: 163533 - 163523 = 10.
10 son los casos donde una partida tiene mas de 1 intento de cobro. La siguiente 
query nos muestra que esos 10 casos corresponden a 10 id donde se hicieron dos intentos
de cobro, ademas la fecha_transaccion indica que para cada uno de los diez
pares de intentos de cobro la hora es exactamente la misma, por ende con solo considerar
los casos donde clap tiene tipo_trx PAGADA tendremos todas las partidas conciliables 
que deseamos
 */

-- Query para ver los 10 id repetidos
SELECT * FROM clap WHERE id_banco IN (
	select id_banco from
			(SELECT COUNT(id_banco), id_banco FROM clap 
			 GROUP BY id_banco HAVING COUNT(id_banco) > 1) A 
)
ORDER BY id_banco, fecha_transaccion;

-- query que retorna el monto y 
-- la cantidad de las transacciones que SIMETRIK considera 
-- como conciliables para la base de CLAP

SELECT SUM(monto) AS monto, COUNT(DISTINCT id_banco) AS transacciones
FROM clap WHERE tipo_trx = 'PAGADA';

-- Monto: 61,050,819.41, transacciones: 147,331

-------------------------------------- 2 PREGUNTA ---------------------------------------
/* 2 Pregunta:
 Escriba el código de SQL que le permite conocer el monto 
 y la cantidad de las transacciones que SIMETRIK considera 
 como conciliables para la base de BANSUR
 */
/* De manera similar al punto anterior vamos a usar el campo
id adquiriente como nuestro id (COUNT: 132396, DISTINCT COUNT: 132339).
Tambien revisamos 132396 - 132339 = 57 casos con mas de un intento de 
cobro y de nuevo nos encontramos con parejas de intentos. Dado que estamos
considerando registros del 1 de nov de 2020, tenemos siempre parejas de intentos de cobro
y en la tabla bansur la fecha_transaccion no tienen hora, podemos considerar como conciliables 
todos los casos donde tipo_trx es PAGO
*/

-- query que retorna el monto y 
-- la cantidad de las transacciones que SIMETRIK considera 
-- como conciliables para la base de BANSUR

SELECT SUM(monto) AS monto, COUNT(DISTINCT id_adquiriente) AS transacciones
FROM bansur WHERE tipo_trx = 'PAGO';

-- Monto: 54,053,911.94, transacciones: 132,338

-------------------------------------- 3 PREGUNTA ---------------------------------------
/* 3 Pregunta:
 ¿Cómo se comparan las cifras de los puntos anteriores respecto 
 de las cifras totales en las fuentes desde un punto de vista del negocio?
 */
 
/* Solo viendo las cifras anteriores y sin cruzar las queries lo que mas 
acaba llamando la atencion es que el 88% del monto transado y el 89% de las
transacciones acaban siendo liquidadas por el banco. Es decir, hay que hacer un
seguimiento sobre el 11% de las transacciones restantes asi como del proceso que 
automaticamente envia los reportes de los datafonos a las bases de datos
del adquirente para evitar que los usuarios de los datafonos no reciban todo el 
dinero que transaron en sus ventas. 
*/

------------------------------------- 4 PREGUNTA ------------------------------------------
/* 4 Pregunta:
  Teniendo en cuenta los criterios de cruce entre ambas bases conciliables, 
  escriba una sentencia de SQL que contenga la información de CLAP y BANSUR; 
  agregue una columna en la que se evidencie si la transacción cruzó o no con su 
  contrapartida y una columna en la que se inserte un ID autoincremental para el 
  control de la conciliación.
 */
 
/* En este punto vamos a hacer una query que comprende varios pasos,
para evitar cargar la RAM del motor de base de datos, vamos a guardar cada paso
en disco duro y posteriormente vamos a borrar todos menos el paso final, que es el que nos
interesa. Por ultimo corremos un select sobre ese ultimo paso */

-- Paso 1, con un FULL OUTER JOIN hacemos un cruce entre ambas tablas siguiendo los
-- criterios de negocio. Luego seleccionamos los casos en los que no hay nulls para
-- dos de las columnas (una de cada tabla) que usamos como cruce, asi encontramos
-- los casos que cruzan y los que no cruzan

DROP TABLE IF EXISTS cruce;
CREATE TABLE cruce AS 
SELECT 
a.TARJETA AS a_TARJETA,		
a.TIPO_TRX AS a_TIPO_TRX,	
a.MONTO AS a_MONTO,	
a.FECHA_TRANSACCION AS a_FECHA_TRANSACCION,	 
a.CODIGO_AUTORIZACION AS a_CODIGO_AUTORIZACION,
a.ID_ADQUIRIENTE AS a_ID_ADQUIRIENTE,
a.FECHA_RECEPCION AS a_FECHA_RECEPCION,
b.INICIO6_TARJETA AS b_INICIO6_TARJETA,
b.FINAL4_TARJETA AS b_FINAL4_TARJETA,
b.TIPO_TRX AS b_TIPO_TRX,
b.MONTO AS b_MONTO,
b.FECHA_TRANSACCION AS b_FECHA_TRANSACCION,
b.CODIGO_AUTORIZACION AS b_CODIGO_AUTORIZACION,
b.ID_BANCO AS b_ID_BANCO,
b.FECHA_RECEPCION_BANCO AS b_FECHA_RECEPCION_BANCO,
CASE WHEN a.ID_ADQUIRIENTE IS NOT NULL AND b.ID_BANCO 
		IS NOT NULL THEN 'CRUZAN' ELSE 'NO CRUZAN' END AS cruce
FROM (SELECT * FROM bansur WHERE tipo_trx = 'PAGO') AS a
FULL OUTER JOIN (SELECT * FROM clap WHERE tipo_trx = 'PAGADA') AS b
ON a.id_adquiriente = b.id_banco
AND a.tarjeta = CONCAT(b.INICIO6_TARJETA,b.FINAL4_TARJETA)
AND ABS(a.MONTO - b.MONTO) <= 0.99
AND CAST(CONCAT(LEFT(a.fecha_transaccion, 4), '-',
		LEFT(RIGHT(a.fecha_transaccion, 4), 2), '-',
		RIGHT(a.fecha_transaccion, 2)) AS DATE) = CAST(LEFT(b.fecha_transaccion, 10) AS DATE);


-- Paso 2, implementamos el id_autoincrement

DROP TABLE IF EXISTS cruce_2;
CREATE TABLE cruce_2 AS 
SELECT *, 
ROW_NUMBER() OVER(PARTITION BY cruce) row_number_result
FROM cruce;

-- Paso 3, Limpiamos el id_autoincrement

DROP TABLE IF EXISTS cruce_3;
CREATE TABLE cruce_3 AS 
SELECT *,
CASE WHEN cruce = 'NO CRUZAN' THEN NULL ELSE row_number_result
END AS id_autoincrement
FROM cruce_2;

-- Eliminamos todos los pasos menos el ultimo y corremos un select
DROP TABLE cruce;
DROP TABLE cruce_2;
SELECT * FROM cruce_3;

------------------------------------- 5 PREGUNTA ------------------------------------------
/* 5 Pregunta:
  Diseñe un código que calcule el porcentaje de transacciones de la base conciliable de CLAP 
  cruzó contra la liquidación de BANSUR.
 */

-- Partimos de la tabla creada en el punto anterior

DROP TABLE IF EXISTS clap_calculo_porcentaje;
CREATE TABLE clap_calculo_porcentaje AS 
SELECT CAST((SELECT COUNT(*) FROM cruce_3 WHERE CONCAT(b_INICIO6_TARJETA,
b_FINAL4_TARJETA,
b_TIPO_TRX,
b_MONTO,
b_FECHA_TRANSACCION,
b_CODIGO_AUTORIZACION,
b_ID_BANCO,
b_FECHA_RECEPCION_BANCO) != '') AS NUMERIC) AS clap_total,

CAST((SELECT COUNT(*) FROM cruce_3 WHERE CONCAT(b_INICIO6_TARJETA,
b_FINAL4_TARJETA,
b_TIPO_TRX,
b_MONTO,
b_FECHA_TRANSACCION,
b_CODIGO_AUTORIZACION,
b_ID_BANCO,
b_FECHA_RECEPCION_BANCO) != ''
AND cruce = 'CRUZAN') AS NUMERIC) AS clap_cruzan;


SELECT clap_cruzan / clap_total AS porcentaje_clap FROM clap_calculo_porcentaje;

-- Porcentaje: 65,4%

------------------------------------- 6 PREGUNTA ------------------------------------------
/* 6 Pregunta:
  Diseñe un código que calcule el porcentaje de transacciones de la base conciliable de CLAP 
  cruzó contra la liquidación de BANSUR.
 */
 
-- De forma similar al punto anterior

DROP TABLE IF EXISTS bansur_calculo_porcentaje;
CREATE TABLE bansur_calculo_porcentaje AS 
SELECT CAST((SELECT COUNT(*) FROM cruce_3 WHERE CONCAT(a_TARJETA,		
a_TIPO_TRX,	
a_MONTO,	
a_FECHA_TRANSACCION,	 
a_CODIGO_AUTORIZACION,
a_ID_ADQUIRIENTE,
a_FECHA_RECEPCION) != '') AS NUMERIC) AS bansur_total,

CAST((SELECT COUNT(*) FROM cruce_3 WHERE CONCAT(a_TARJETA,		
a_TIPO_TRX,	
a_MONTO,	
a_FECHA_TRANSACCION,	 
a_CODIGO_AUTORIZACION,
a_ID_ADQUIRIENTE,
a_FECHA_RECEPCION) != ''
AND cruce = 'CRUZAN') AS NUMERIC) AS bansur_cruzan;


SELECT bansur_cruzan / bansur_total AS porcentaje_bansur FROM bansur_calculo_porcentaje;

-- Porcentaje: 72,8%