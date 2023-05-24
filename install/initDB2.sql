WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER=ORCLPDB1;
--CREATE TABLESPACE DATA DATAFILE '/home/oracle/tablespaces/tbs_ADMIN.dbf' SIZE 500M AUTOEXTEND ON NEXT 10M;
--CREATE TEMPORARY TABLESPACE tDATA TEMPFILE '/home/oracle/tablespaces/tms_ADMIN.dbf' SIZE 500M AUTOEXTEND ON NEXT 10M;
--CREATE USER ADMIN IDENTIFIED BY oracle DEFAULT TABLESPACE DATA TEMPORARY TABLESPACE tDATA;
--grant dba to ADMIN;
--grant create session to ADMIN;

--connect ADMIN/oracle@labs.local:1522/ORCLPDB1

-- WHENEVER SQLERROR CONTINUE
-- DROP USER AQ CASCADE;
-- DROP USER ORDERUSER CASCADE;
-- DROP USER INVENTORYUSER CASCADE;

-- WHENEVER SQLERROR EXIT 1
-- AQ User
CREATE USER AQ IDENTIFIED BY oracle;
GRANT unlimited tablespace to AQ;
GRANT connect, resource TO AQ;
GRANT aq_user_role TO AQ;
GRANT create session to AQ;
GRANT EXECUTE ON sys.dbms_aqadm TO AQ;
GRANT EXECUTE ON sys.dbms_aq TO AQ;


-- Order User
CREATE USER INVENTORYUSER IDENTIFIED BY oracle;
GRANT unlimited tablespace to INVENTORYUSER;
GRANT connect, resource TO INVENTORYUSER;
GRANT aq_user_role TO INVENTORYUSER;
GRANT EXECUTE ON sys.dbms_aq TO INVENTORYUSER;
-- For inventory-springboot deployment
GRANT aq_administrator_role TO INVENTORYUSER;
GRANT EXECUTE ON sys.dbms_aqadm TO INVENTORYUSER;
-- For inventory-plsql deployment
GRANT CREATE JOB to INVENTORYUSER; 
GRANT EXECUTE ON sys.DBMS_SCHEDULER TO INVENTORYUSER;
GRANT create any edition,drop any edition to INVENTORYUSER;
alter user INVENTORYUSER enable editions;
grant create session, create table, create view to INVENTORYUSER;
--This is all we want but table hasn't been created yet... GRANT select on AQ.inventoryqueuetable to INVENTORYUSER;
GRANT SELECT ANY TABLE TO INVENTORYUSER;
-- GRANT select on gv$session to INVENTORYUSER;
GRANT create session to INVENTORYUSER;
GRANT select on v$diag_alert_ext to INVENTORYUSER;
GRANT select on DBA_QUEUE_SCHEDULES to INVENTORYUSER;

CREATE USER ORDERUSER IDENTIFIED BY oracle;
GRANT unlimited tablespace to ORDERUSER;
GRANT connect, resource TO ORDERUSER;
GRANT aq_user_role TO ORDERUSER;
GRANT EXECUTE ON sys.dbms_aq TO ORDERUSER;
GRANT SODA_APP to ORDERUSER;
--This is all we want but table hasn't been created yet... GRANT select on AQ.orderqueuetable to ORDERUSER;
GRANT SELECT ANY TABLE TO ORDERUSER;
-- GRANT select on "gv$session" to ORDERUSER;
GRANT create session to ORDERUSER;
GRANT select on v$diag_alert_ext to ORDERUSER;
GRANT select on DBA_QUEUE_SCHEDULES to ORDERUSER;



-- WHENEVER SQLERROR EXIT 1
connect AQ/oracle@labs.local:1522/ORCLPDB1

BEGIN
   DBMS_AQADM.CREATE_SHARDED_QUEUE (
      queue_name          => 'ORDERQUEUE',
      queue_payload_type   => DBMS_AQADM.JMS_TYPE,
      multiple_consumers   => true);

   DBMS_AQADM.CREATE_SHARDED_QUEUE (
      queue_name          => 'INVENTORYQUEUE',
      queue_payload_type   => DBMS_AQADM.JMS_TYPE,
      multiple_consumers   => true);

   DBMS_AQADM.START_QUEUE (
      queue_name          => 'ORDERQUEUE');

   DBMS_AQADM.START_QUEUE (
      queue_name          => 'INVENTORYQUEUE');

END;
/


BEGIN
   DBMS_AQADM.grant_queue_privilege (
      privilege     =>     'ENQUEUE',
      queue_name    =>     'ORDERQUEUE',
      grantee       =>     'ORDERUSER',
      grant_option  =>      FALSE);

   DBMS_AQADM.grant_queue_privilege (
      privilege     =>     'DEQUEUE',
      queue_name    =>     'ORDERQUEUE',
      grantee       =>     'INVENTORYUSER',
      grant_option  =>      FALSE);

   DBMS_AQADM.grant_queue_privilege (
      privilege     =>     'ENQUEUE',
      queue_name    =>     'INVENTORYQUEUE',
      grantee       =>     'INVENTORYUSER',
      grant_option  =>      FALSE);

   DBMS_AQADM.grant_queue_privilege (
      privilege     =>     'DEQUEUE',
      queue_name    =>     'INVENTORYQUEUE',
      grantee       =>     'ORDERUSER',
      grant_option  =>      FALSE);

   DBMS_AQADM.add_subscriber(
      queue_name=>'ORDERQUEUE',
      subscriber=>sys.aq$_agent('inventory_service',NULL,NULL));

   DBMS_AQADM.add_subscriber(
      queue_name=>'INVENTORYQUEUE',
      subscriber=>sys.aq$_agent('order_service',NULL,NULL));
END;
/


-- WHENEVER SQLERROR EXIT 1
connect INVENTORYUSER/oracle@labs.local:1522/ORCLPDB1


create table tb_inventory (
  inventoryid varchar(16) PRIMARY KEY NOT NULL,
  inventorylocation varchar(32),
  inventorycount integer CONSTRAINT positive_inventory CHECK (inventorycount >= 0) );

insert into tb_inventory values ('sushi', '1468 WEBSTER ST,San Francisco,CA', 0);
insert into tb_inventory values ('pizza', '1469 WEBSTER ST,San Francisco,CA', 0);
insert into tb_inventory values ('burger', '1470 WEBSTER ST,San Francisco,CA', 0);

CREATE EDITIONING VIEW inventory AS 
  select t.inventoryId, t.inventoryLocation, t.inventoryCount
from tb_inventory t;

set echo on 

--CREATE OR REPLACE PROCEDURE dequeueOrderMessage(p_action OUT varchar2, p_orderid OUT integer)
CREATE OR REPLACE PROCEDURE dequeueOrderMessage(p_orderInfo OUT varchar2)
IS

  dequeue_options       dbms_aq.dequeue_options_t;
  message_properties    dbms_aq.message_properties_t;
  message_handle        RAW(16);
  message               SYS.AQ$_JMS_TEXT_MESSAGE;
  no_messages           EXCEPTION;
  pragma                exception_init(no_messages, -25228);
          
BEGIN
--  dequeue_options.wait := dbms_aq.NO_WAIT;
   dequeue_options.wait := dbms_aq.FOREVER;
   dequeue_options.consumer_name := 'inventory_service';
   dequeue_options.navigation    := DBMS_AQ.FIRST_MESSAGE;
  
  -- dequeue_options.navigation := dbms_aq.FIRST_MESSAGE;
  -- dequeue_options.dequeue_mode := dbms_aq.LOCKED;

  DBMS_AQ.DEQUEUE(
    queue_name => 'AQ.ORDERQUEUE',
    dequeue_options => dequeue_options,
    message_properties => message_properties,
    payload => message,
    msgid => message_handle);
    -- COMMIT;

--  p_action := message.get_string_property('action');
--  p_orderid := message.get_int_property('orderid');
    p_orderInfo := message.text_vc;
--  message.get_text(p_orderInfo);

  EXCEPTION
    WHEN no_messages THEN
    BEGIN
      p_orderInfo := '';
    END;
    WHEN OTHERS THEN
     RAISE;
END;
/
show errors


CREATE OR REPLACE PROCEDURE checkInventoryReturnLocation(p_inventoryId IN VARCHAR2, p_inventorylocation OUT varchar2)
IS

BEGIN
  update INVENTORYUSER.INVENTORY set inventorycount = inventorycount - 1 where inventoryid = p_inventoryId and inventorycount > 0 returning inventorylocation into p_inventorylocation;
  dbms_output.put_line('p_inventorylocation');
  dbms_output.put_line(p_inventorylocation);
END;
/
show errors



-- CREATE OR REPLACE PROCEDURE enqueueInventoryMessage(p_action IN VARCHAR2, p_orderid IN NUMBER)
CREATE OR REPLACE PROCEDURE enqueueInventoryMessage(p_inventoryInfo IN VARCHAR2)
IS
   enqueue_options     DBMS_AQ.enqueue_options_t;
   message_properties  DBMS_AQ.message_properties_t;
   message_handle      RAW(16);
   message             SYS.AQ$_JMS_TEXT_MESSAGE;

BEGIN

  message := SYS.AQ$_JMS_TEXT_MESSAGE.construct;
  -- message.text_vc := p_inventoryInfo;
  message.set_text(p_inventoryInfo);
  -- message.set_string_property('action', p_action);
  -- message.set_int_property('orderid', p_orderid);

  DBMS_AQ.ENQUEUE(queue_name => 'AQ.INVENTORYQUEUE',
           enqueue_options    => enqueue_options,
           message_properties => message_properties,
           payload            => message,
           msgid              => message_handle);

END;
/
show errors


CREATE OR REPLACE PROCEDURE dequeue_order_message(in_wait_option in BINARY_INTEGER, out_order_message OUT varchar2)
IS
  dequeue_options       dbms_aq.dequeue_options_t;
  message_properties    dbms_aq.message_properties_t;
  message_handle        RAW(16);
  message               SYS.AQ$_JMS_TEXT_MESSAGE;
  no_messages           EXCEPTION;
  pragma                exception_init(no_messages, -25228); 
BEGIN
  CASE in_wait_option
  WHEN 0 THEN
    dequeue_options.wait := dbms_aq.NO_WAIT;
  WHEN -1 THEN
    dequeue_options.wait := dbms_aq.FOREVER;
  ELSE
    dequeue_options.wait := in_wait_option;
  END CASE;

  dequeue_options.consumer_name := '$INVENTORY_SERVICE_NAME';
  dequeue_options.navigation    := dbms_aq.FIRST_MESSAGE;  -- Required for TEQ

  DBMS_AQ.DEQUEUE(
    queue_name         => 'AQ.ORDERQUEUE',
    dequeue_options    => dequeue_options,
    message_properties => message_properties,
    payload            => message,
    msgid              => message_handle);

  out_order_message := message.text_vc;

  EXCEPTION
    WHEN no_messages THEN
      out_order_message := '';
    WHEN OTHERS THEN
      RAISE;
END;
/
show errors

CREATE OR REPLACE PROCEDURE enqueue_inventory_message(in_inventory_message IN VARCHAR2)
IS
   enqueue_options     dbms_aq.enqueue_options_t;
   message_properties  dbms_aq.message_properties_t;
   message_handle      RAW(16);
   message             SYS.AQ$_JMS_TEXT_MESSAGE;
BEGIN
  message := SYS.AQ$_JMS_TEXT_MESSAGE.construct;
  message.set_text(in_inventory_message);

  dbms_aq.ENQUEUE(queue_name => 'AQ.INVENTORYQUEUE',
    enqueue_options    => enqueue_options,
    message_properties => message_properties,
    payload            => message,
    msgid              => message_handle);
END;
/
show errors

CREATE OR REPLACE PROCEDURE check_inventory(in_inventory_id IN VARCHAR2, out_inventory_location OUT varchar2)
IS
BEGIN
  update INVENTORYUSER.INVENTORY set inventorycount = inventorycount - 1 
    where inventoryid = in_inventory_id and inventorycount > 0 
    returning inventorylocation into out_inventory_location;
  if sql%rowcount = 0 then
    out_inventory_location := 'inventorydoesnotexist';
  end if;
END;
/
show errors

CREATE OR REPLACE PROCEDURE inventory_service
IS
  order_message VARCHAR2(32767);
  order_inv_id VARCHAR2(16);
  order_inv_loc VARCHAR2(32);
  order_json JSON_OBJECT_T;
  inventory_json JSON_OBJECT_T;
BEGIN
  LOOP
    -- Wait for and dequeue the next order message
    dequeue_order_message(
      in_wait_option    => -1,  -- Wait forever
      out_order_message => order_message);

    -- Parse the order message
    order_json := JSON_OBJECT_T.parse(order_message);
    order_inv_id := order_json.get_string('itemid');

    -- Check the inventory
    check_inventory(
      in_inventory_id        => order_inv_id,
      out_inventory_location => order_inv_loc);
      
    -- Construct the inventory message
    inventory_json := new JSON_OBJECT_T;
    inventory_json.put('orderid',           order_json.get_string('orderid'));
    inventory_json.put('itemid',            order_inv_id);
    inventory_json.put('inventorylocation', order_inv_loc);
    inventory_json.put('suggestiveSale',    'beer');

    -- Send the inventory message
    enqueue_inventory_message(
      in_inventory_message   => inventory_json.to_string() );

    -- commit
    commit;
  END LOOP;
END;
/
show errors

-- WHENEVER SQLERROR EXIT 1
connect ORDERUSER/oracle@labs.local:1522/ORCLPDB1

/*
-- Place Order using MLE JavaScript
CREATE OR REPLACE PROCEDURE place_order_js (
  orderid           IN varchar2,
  itemid            IN varchar2,
  deliverylocation  IN varchar2)
AUTHID CURRENT_USER
IS
  order_json            JSON_OBJECT_T;
BEGIN
  -- Construct the order object
  order_json := new JSON_OBJECT_T;
  order_json.put('orderid', orderid);
  order_json.put('itemid',  itemid);
  order_json.put('deliverylocation', deliverylocation);
  order_json.put('status', 'Pending');
  order_json.put('inventoryLocation', '');
  order_json.put('suggestiveSale', '');

  -- Insert the order object
  insert_order(orderid, order_json.to_string());

  -- Send the order message
  enqueue_order_message(order_json.to_string());

  -- Commit
  commit;

  HTP.print(order_json.to_string());

  EXCEPTION
    WHEN OTHERS THEN
      HTP.print(SQLERRM);

END;
/

CREATE OR REPLACE PROCEDURE place_order_js (
  orderid           IN varchar2,
  itemid            IN varchar2,
  deliverylocation  IN varchar2)
AUTHID CURRENT_USER
IS
   ctx DBMS_MLE.context_handle_t := DBMS_MLE.create_context();
   order VARCHAR2(4000);
   js_code clob := q'~
    var oracledb = require("mle-js-oracledb");
    var bindings = require("mle-js-bindings");
    conn = oracledb.defaultConnection();

    // Construct the order object
    const order = {
      orderid: bindings.importValue("orderid"),
      itemid: bindings.importValue("itemid"),
      deliverylocation: bindings.importValue("deliverylocation"),
      status: "Pending",
      inventoryLocation: "",
      suggestiveSale: ""
    }
    
    // Insert the order object
    insert_order(conn, order);

    // Send the order message
    enqueue_order_message(conn, order);

    // Commit
    conn.commit;

    // Output order
    bindings.exportValue("order", order.stringify());

    function insert_order(conn, order) {
        conn.execute( "BEGIN insert_order(:1, :2); END;", [order.orderid, order.stringify()]);
    }

    function enqueue_order_message(conn, order) {
        conn.execute( "BEGIN enqueue_order_message(:1); END;", [order.stringify()]);
    }
   ~';
BEGIN
   -- Pass variables to JavaScript
   dbms_mle.export_to_mle(ctx, 'orderid', orderid); 
   dbms_mle.export_to_mle(ctx, 'itemid', itemid); 
   dbms_mle.export_to_mle(ctx, 'deliverylocation', deliverylocation); 

   -- Execute JavaScript
   DBMS_MLE.eval(ctx, 'JAVASCRIPT', js_code);
   DBMS_MLE.import_from_mle(ctx, 'order', order);
   DBMS_MLE.drop_context(ctx);

   HTP.print(order);

EXCEPTION
   WHEN others THEN
     dbms_mle.drop_context(ctx);
     HTP.print(SQLERRM);

END;
/
show errors
*/

CREATE OR REPLACE PROCEDURE place_order_js (
  orderid           IN varchar2,
  itemid            IN varchar2,
  deliverylocation  IN varchar2)
AUTHID CURRENT_USER
IS
   ctx DBMS_MLE.context_handle_t := DBMS_MLE.create_context();
   order2 VARCHAR2(4000);
   js_code clob := q'~
    var oracledb = require("mle-js-oracledb");
    var bindings = require("mle-js-bindings");
    conn = oracledb.defaultConnection();

    // Construct the order object
    const order = {
      orderid: bindings.importValue("orderid"),
      itemid: bindings.importValue("itemid"),
      deliverylocation: bindings.importValue("deliverylocation"),
      status: "Pending",
      inventoryLocation: "",
      suggestiveSale: ""
    }
    
    // Insert the order object
    insert_order(conn, order);

    // Send the order message
    enqueue_order_message(conn, order);

    // Commit
    conn.commit;

    // Output order
    bindings.exportValue("order", order.stringify());

    function insert_order(conn, order) {
        conn.execute( "BEGIN insert_order(:1, :2); END;", [order.orderid, order.stringify()]);
    }

    function enqueue_order_message(conn, order) {
        conn.execute( "BEGIN enqueue_order_message(:1); END;", [order.stringify()]);
    }
   ~';
BEGIN
   -- Pass variables to JavaScript
   dbms_mle.export_to_mle(ctx, 'orderid', orderid); 
   dbms_mle.export_to_mle(ctx, 'itemid', itemid); 
   dbms_mle.export_to_mle(ctx, 'deliverylocation', deliverylocation); 

   -- Execute JavaScript
   DBMS_MLE.eval(ctx, 'JAVASCRIPT', js_code);
   DBMS_MLE.import_from_mle(ctx, 'order', order2);
   DBMS_MLE.drop_context(ctx);

   HTP.print(order2);

EXCEPTION
   WHEN others THEN
     dbms_mle.drop_context(ctx);
     HTP.print(SQLERRM);

END;
/


-- Enqueue order message
CREATE OR REPLACE PROCEDURE enqueue_order_message(in_order_message IN VARCHAR2)
AUTHID CURRENT_USER
IS
   enqueue_options     dbms_aq.enqueue_options_t;
   message_properties  dbms_aq.message_properties_t;
   message_handle      RAW(16);
   message             SYS.AQ$_JMS_TEXT_MESSAGE;
BEGIN
  message := SYS.AQ$_JMS_TEXT_MESSAGE.construct;
  message.set_text(in_order_message);

  dbms_aq.ENQUEUE(queue_name => 'AQ.ORDERQUEUE',
    enqueue_options    => enqueue_options,
    message_properties => message_properties,
    payload            => message,
    msgid              => message_handle);
END;
/
show errors


-- Insert order
CREATE OR REPLACE PROCEDURE insert_order(in_order_id IN VARCHAR2, in_order IN VARCHAR2)
AUTHID CURRENT_USER
IS
  order_doc             SODA_DOCUMENT_T;
  collection            SODA_COLLECTION_T;
  status                NUMBER;
  collection_name       CONSTANT VARCHAR2(20) := 'orderscollection';
  collection_metadata   CONSTANT VARCHAR2(4000) := '{"keyColumn" : {"assignmentMethod": "CLIENT"}}';
BEGIN
  -- Write the order object
  collection := DBMS_SODA.open_collection(collection_name);
  IF collection IS NULL THEN
    collection := DBMS_SODA.create_collection(collection_name, collection_metadata);
  END IF;

  order_doc := SODA_DOCUMENT_T(in_order_id, b_content => utl_raw.cast_to_raw(in_order));
  status := collection.insert_one(order_doc);
END;
/
show errors



-- place order microserice (GET)
-- Example: ../ords/orderuser/placeorder/order?orderId=66&orderItem=sushi&deliverTo=Redwood
CREATE OR REPLACE PROCEDURE place_order (
  orderid           IN varchar2,
  itemid            IN varchar2,
  deliverylocation  IN varchar2)
AUTHID CURRENT_USER
IS
  order_json            JSON_OBJECT_T;
BEGIN
  -- Construct the order object
  order_json := new JSON_OBJECT_T;
  order_json.put('orderid', orderid);
  order_json.put('itemid',  itemid);
  order_json.put('deliverylocation', deliverylocation);
  order_json.put('status', 'Pending');
  order_json.put('inventoryLocation', '');
  order_json.put('suggestiveSale', '');

  -- Insert the order object
  insert_order(orderid, order_json.to_string());

  -- Send the order message
  enqueue_order_message(order_json.to_string());

  -- Commit
  commit;

  HTP.print(order_json.to_string());

  EXCEPTION
    WHEN OTHERS THEN
      HTP.print(SQLERRM);

END;
/
show errors





-- frontend place order (POST)
CREATE OR REPLACE PROCEDURE frontend_place_order (
  serviceName IN varchar2,
  commandName IN varchar2,
  orderId     IN varchar2,
  orderItem   IN varchar2,
  deliverTo   IN varchar2)
AUTHID CURRENT_USER
IS
BEGIN
  place_order(
    orderid => orderId,
    itemid  => orderItem,
    deliverylocation => deliverTo);
END;
/
show errors







