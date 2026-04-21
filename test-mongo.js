const { MongoClient } = require('mongodb');

// Connection string with your NEW password
const uri = "mongodb://pavan:4aORvkKVeUfNrdlDmFOfa9wTpguLbBZs_XfEMjIbmnauLqwx@978cbb1f-b10c-4647-badb-af7b91b37850.nam5.firestore.goog:443/cardiocare-quest-telemetry?loadBalanced=true&tls=true&authMechanism=SCRAM-SHA-256&retryWrites=false";

async function run() {
    const client = new MongoClient(uri);

    try {
        console.log("🔌 Attempting to connect via MongoDB API...");
        await client.connect();
        console.log("✅ Connected successfully to Firestore!");

        const database = client.db('cardiocare-quest-telemetry');
        const collection = database.collection('test');

        console.log("📝 Writing test document...");
        const result = await collection.insertOne({
            source: "Node.js MongoDB Driver",
            timestamp: new Date(),
            vibe: "Success at last!"
        });
        
        console.log(`🚀 Injected document with ID: ${result.insertedId}`);

    } catch (err) {
        console.error("❌ Operation failed:", err.message);
        console.log("💡 Tip: If you see 'insufficient permissions', double-check that the role in the Firebase UI is set to readWrite.");
    } finally {
        await client.close();
    }
}

run();