WHENEVER SQLERROR CONTINUE


-- 创建新版本version2，作为ORA$BASE的子版本。ORA$BASE是系统默认的版本
create edition version2 as child of ora$base;

-- 使用新版本
ALTER SESSION SET EDITION = version2;

-- 改变表结构
ALTER TABLE INVENTORYUSER.TB_INVENTORY ADD LAST_UPDATED varchar(32);

-- 改变物化视图结构
CREATE or REPLACE EDITIONING VIEW inventory AS
  select t.inventoryId, t.inventoryLocation, t.inventoryCount, t.LAST_UPDATED
from tb_inventory t;