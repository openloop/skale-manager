const init = require("./Init.js");
const Tx = require("ethereumjs-tx").Transaction;
async function sendTransaction(web3Inst, account, privateKey, data, receiverContract) {
    console.log("Transaction generating started!");
    const nonce = await web3Inst.eth.getTransactionCount(account);
    const rawTx = {
        from: web3Inst.utils.toChecksumAddress(account),
        nonce: "0x" + nonce.toString(16),
        data: data,
        to: receiverContract,
        gasPrice: 10000000000,
        gas: 8000000
        // chainId: await web3Inst.eth.getChainId()
    };
    const tx = new Tx(rawTx, {chain: "rinkeby"});
    tx.sign(privateKey);
    const serializedTx = tx.serialize();
    const txReceipt = await web3Inst.eth.sendSignedTransaction('0x' + serializedTx.toString('hex')); //.on('receipt', receipt => {
    console.log("Transaction receipt is - ");
    console.log(txReceipt);
    console.log();
    return true;
}

async function grantRole(address) {
    const admin_role = await init.SkaleManager.methods.ADMIN_ROLE().call();
    console.log("Is this address has admin role: ",await init.SkaleManager.methods.hasRole(admin_role, address).call());
    const grantRoleABI = init.SkaleManager.methods.grantRole(admin_role, address).encodeABI(); //.send({from: init.mainAccount});
    contractAddress = init.jsonData['skale_manager_address'];
    let privateKeyB = Buffer.from(init.privateKey, "hex");
    const success = await sendTransaction(init.web3, init.mainAccount, privateKeyB, grantRoleABI, contractAddress, "0");
    console.log("Is this address has admin role after transaction: ",await init.SkaleManager.methods.hasRole(admin_role, address).call());
    console.log()
    console.log("Transaction was successful:", success);
    console.log("Exiting...");
    process.exit()
}

async function deleteSchain(schainName) {
    console.log("Check is schain exist: ", await init.SchainsInternal.methods.isSchainExist(init.web3.utils.soliditySha3(schainName)).call());
    contractAddress = init.jsonData['skale_manager_address'];
    const deleteSchainABI = init.SkaleManager.methods.deleteSchainByRoot(schainName).encodeABI();
    const privateKeyAdmin = process.env.PRIVATE_KEY_ADMIN;
    const accountAdmin = process.env.ACCOUNT_ADMIN;
    const privateKeyB = Buffer.from(privateKeyAdmin, "hex");
    const success = await sendTransaction(init.web3, accountAdmin, privateKeyB, deleteSchainABI, init.jsonData['skale_manager_address']);
    console.log("Transaction was successful:", success);
    console.log();
    console.log("Check is schain exist after transaction: ", await init.SchainsInternal.methods.isSchainExist(init.web3.utils.soliditySha3(schainName)).call());
    console.log("Exiting...");
    process.exit()
}

async function calculateNormalBounty(nodeIndex) {
    console.log();
    console.log("Should show normal bounty for ", nodeIndex, " node");
    console.log("Normal bounty : ", await init.Bounty.methods.calculateNormalBounty(nodeIndex).call());
    console.log();
    process.exit();
}


if (process.argv[2] == 'grantRole') {
    grantRole(process.argv[3]);
} else if (process.argv[2] == 'deleteSchain') {
    deleteSchain(process.argv[3]);
} else if (process.argv[2] == 'calculateNormalBounty') {
    calculateNormalBounty(process.argv[3]);
} else {
    console.log("Recheck name of function");
    process.exit();
}
