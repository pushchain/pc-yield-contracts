const { ethers } = require("ethers");
const { MerkleTree } = require("merkletreejs");

// Generate 10 test users with addresses that match the test
const claims = [
    { address: "0x0000000000000000000000000000000000000456", amount: ethers.parseEther("1000"), epoch: 1 }, // user1
    { address: "0x0000000000000000000000000000000000000789", amount: ethers.parseEther("500"), epoch: 2 },  // user2
    { address: "0x0000000000000000000000000000000000001000", amount: ethers.parseEther("100"), epoch: 1 },  // user3
    { address: "0x0000000000000000000000000000000000001001", amount: ethers.parseEther("150"), epoch: 1 },  // user4
    { address: "0x0000000000000000000000000000000000001002", amount: ethers.parseEther("200"), epoch: 1 },  // user5
    { address: "0x0000000000000000000000000000000000001003", amount: ethers.parseEther("250"), epoch: 1 },  // user6
    { address: "0x0000000000000000000000000000000000001004", amount: ethers.parseEther("300"), epoch: 1 },  // user7
    { address: "0x0000000000000000000000000000000000001005", amount: ethers.parseEther("350"), epoch: 1 },  // user8
    { address: "0x0000000000000000000000000000000000001006", amount: ethers.parseEther("400"), epoch: 1 },  // user9
    { address: "0x0000000000000000000000000000000000001007", amount: ethers.parseEther("450"), epoch: 1 },  // user10
];

// Hash function that matches the contract exactly
function hashLeaf(address, amount, epoch) {
    return ethers.solidityPackedKeccak256(
        ["address", "uint256", "uint256"],
        [address, amount, epoch]
    );
}

// Create the tree
const leaves = claims.map(claim => hashLeaf(claim.address, claim.amount, claim.epoch));
const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });

console.log("Merkle Root:", tree.getHexRoot());
console.log("\nProofs for each user:");
console.log("======================");

claims.forEach((claim, index) => {
    const leaf = hashLeaf(claim.address, claim.amount, claim.epoch);
    const proof = tree.getHexProof(leaf);
    console.log(`\nUser ${index + 1} (${claim.address}):`);
    console.log(`  Amount: ${ethers.formatEther(claim.amount)} PC`);
    console.log(`  Epoch: ${claim.epoch}`);
    console.log(`  Proof: [${proof.map(p => `"${p}"`).join(", ")}]`);
});

console.log("\nFull tree data for Solidity:");
console.log("=============================");
console.log(`merkleRoot = ${tree.getHexRoot()};`);
console.log("\n// Proofs array for each user:");
claims.forEach((claim, index) => {
    const leaf = hashLeaf(claim.address, claim.amount, claim.epoch);
    const proof = tree.getHexProof(leaf);
    console.log(`proof${index + 1} = new bytes32[](${proof.length});`);
    proof.forEach((p, i) => {
        console.log(`proof${index + 1}[${i}] = ${p};`);
    });
    console.log("");
});

