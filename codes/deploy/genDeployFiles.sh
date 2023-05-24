#!/bin/bash
git clone http://root:Oracle123@labs.local/root/grabdish-deploy.git
modules=(frontend-helidon inventory-helidon order-helidon supplier-helidon-se )
for module in ${modules[@]}; do
    tag=`grep -m1 '<version>' "../$module/pom.xml" | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' | sed -e 's/[ ]*//g'`
    sed -e "s/0.0.1-SNAPSHOT/$tag/g" "../$module/$module-deployment.yaml" | sed -e "s/1521/1522/g" > "grabdish-deploy/$module-deployment.yaml"
    #sed -e "s/0.0.1-SNAPSHOT/$tag/g" "../$module/$module-deployment.yaml" > "grabdish-deploy/$module-deployment.yaml"
done
cd grabdish-deploy && git add . && git commit -m "generate deploy file" && git push
cd ..
rm -rf grabdish-deploy
echo "generate deployment files successfully"