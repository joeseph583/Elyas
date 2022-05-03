// Convert a string to bytes32 
// String cannot be longer than 32
const toBytes32 = (string) => {
  const length = string.length;
  for (let i = 0; i < 32 - length; i++) {
    string += '\0'
  }
  return web3.utils.asciiToHex(string);
};

// Decode bytes32 to original string
const fromBytes32 = (bytes32) => {
  return web3.utils.hexToAscii(bytes32).replace(/\0/g, '');
};

const isLocal = (chainId) => {
  return [
    1337, 31337
  ].includes(chainId);
};

module.exports = {
  toBytes32, fromBytes32, isLocal
};