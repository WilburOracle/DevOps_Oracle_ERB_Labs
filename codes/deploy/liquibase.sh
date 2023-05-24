#!/bin/bash

echo "generate liquibase sql file"
echo "lb update -changelog-file ../liquibase/controller.admin.xml" > updateDb.sql
echo "lb update -changelog-file ../liquibase/controller.xml" >> updateDb.sql

if test -f "../liquibase/controller.data.xml"; then
    echo "lb update -changelog-file ../liquibase/controller.data.xml" >> updateDb.sql
fi

cat updateDb.sql
sql ADMIN/oracle@labs.local:1522/ORCLPDB1 @updateDb.sql
echo "apply liquibase sql file successfully"
rm updateDb.sql