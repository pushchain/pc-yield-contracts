const { ethers } = require("ethers");
const { MerkleTree } = require("merkletreejs");

// Generate test users with addresses and multiplier points for RewardSeasonsYieldFarm
const claims = [
    { address: "0x0000000000000000000000000000000000000002", multiplier: 10 }, // user1
    { address: "0x0000000000000000000000000000000000000003", multiplier: 5 },  // user2
    { address: "0x0000000000000000000000000000000000000004", multiplier: 8 },  // user3
    { address: "0x0000000000000000000000000000000000000005", multiplier: 12 }, // user4
    { address: "0x0000000000000000000000000000000000000006", multiplier: 3 },  // user5
];

// Hash function that matches the contract exactly
function hashLeaf(address, multiplier) {
    return ethers.solidityPackedKeccak256(
        ["address", "uint256"],
        [address, multiplier]
    );
}

// Create the tree
const leaves = claims.map(claim => hashLeaf(claim.address, claim.multiplier));
const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });

console.log("Merkle Root:", tree.getHexRoot());
console.log("\nProofs for each user:");
console.log("======================");

claims.forEach((claim, index) => {
    const leaf = hashLeaf(claim.address, claim.multiplier);
    const proof = tree.getHexProof(leaf);
    console.log(`\nUser ${index + 1} (${claim.address}):`);
    console.log(`  Multiplier: ${claim.multiplier}`);
    console.log(`  Proof: [${proof.map(p => `"${p}"`).join(", ")}]`);
});

console.log("\nFull tree data for Solidity:");
console.log("=============================");
console.log(`MERKLE_ROOT = ${tree.getHexRoot()};`);
console.log("\n// Proofs array for each user:");
claims.forEach((claim, index) => {
    const leaf = hashLeaf(claim.address, claim.multiplier);
    const proof = tree.getHexProof(leaf);
    console.log(`proof${index + 1} = new bytes32[](${proof.length});`);
    proof.forEach((p, i) => {
        console.log(`proof${index + 1}[${i}] = ${p};`);
    });
    console.log("");
});
