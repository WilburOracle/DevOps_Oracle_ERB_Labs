#!/bin/bash
modules=(frontend-helidon inventory-helidon order-helidon supplier-helidon-se )
for module in ${modules[@]}; do
    tag=`grep -m1 '<version>' "../$module/pom.xml" | awk -F'>' '{print $2}' | awk -F'<' '{print $1}' | sed -e 's/[ ]*//g'`
    echo "docker push labs.local:5000/$module:$tag"
    docker push labs.local:5000/$module:$tag
done
echo "push docker images successfully"