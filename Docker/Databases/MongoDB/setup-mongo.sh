#!/bin/bash

# Wait until MongoDB is ready
echo " Waiting for MongoDB to be ready..."

until mongosh --host mong:27017 --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 2)' &>/dev/null; do
  printf '.'
  sleep 1
done

echo -e "\n MongoDB is available."

# Create the replica set initiation JS
cat <<'EOF' > /config-replica.js
try {
    const config = {
        _id: "rs0",
        version: 1,
        members: [
            {
                _id: 0,
                host: "url:27018",
                priority: 2
            }
        ]
    };
    rs.initiate(config);
    print(" Replica set initiated.");
} catch (e) {
    print(" Replica set may already be initialized or failed to initiate:");
    print(e);
}
EOF

# Run the replica set config script
mongosh -u username -p "password" --authenticationDatabase admin --host mongo:27017 /config-replica.js

# Wait for the primary to be elected
echo "⏳ Waiting for PRIMARY election..."

until mongosh -u username -p "password" --authenticationDatabase admin --host mongo:27017 --eval 'db.hello().isWritablePrimary' --quiet | grep -q true; do
  printf '.'
  sleep 1
done

echo -e "\n PRIMARY is ready. Creating additional user..."

# Create a user for external DB access
mongosh -u username -p "password" --authenticationDatabase admin --host mongo:27017 <<EOF
use admin;
db.createUser({
  user: "otheradmin",
  pwd:  "othersecret",
  roles: [
    { role: "readWrite", db: "myowndb" },
    { role: "readWrite", db: "admin" }
  ]
});
EOF

echo " Replica set and user creation complete."
