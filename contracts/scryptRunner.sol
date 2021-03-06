pragma solidity ^0.4.0;

import {ScryptFramework} from "./scryptFramework.sol";
 

contract ScryptRunner is ScryptFramework {
    function initMemory(State memory state) pure internal {
        state.fullMemory = new uint[](4 * 1024);
    }

    function run(bytes input, uint upToStep) pure public returns (uint[4] vars, bytes32 memoryHash, bytes32[] proof, bytes output) {
        State memory s = inputToState(input);
        Proofs memory proofs;
        if (upToStep > 0) {
            uint internalStep = upToStep - 1;
            for (uint i = 0; i < internalStep; i++) {
                runStep(s, i, proofs);
            }
            proofs.generateProofs = true;
            if (internalStep < 2048) {
                runStep(s, internalStep, proofs);
            } else {
                output = finalStateToOutput(s);
            }
        }
        return (s.vars, s.memoryHash, proofs.proof, output);
    }

    // The proof for reading memory consists of a list of proof from
    // leaf to root plus the four values read from memory.
    function readMemory(State memory state, uint index, Proofs memory proofs) pure internal returns (uint a, uint b, uint c, uint d) {
        require(index < 1024);
        uint pos = 0x20 * 4 * index;
        uint[] memory fullMem = state.fullMemory;
        assembly {
            pos := add(pos, 0x20)
            a := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            b := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            c := mload(add(fullMem, pos))
            pos := add(pos, 0x20)
            d := mload(add(fullMem, pos))
        }
        if (proofs.generateProofs) {
            bytes32[] memory proof;
            (proof, state.memoryHash) = generateMemoryProof(state.fullMemory, index);
            proofs.proof = new bytes32[](proof.length + 4);
            for (uint i = 0; i < proof.length; i++)
                proofs.proof[i] = proof[i];
            proofs.proof[proof.length + 0] = bytes32(a);
            proofs.proof[proof.length + 1] = bytes32(b);
            proofs.proof[proof.length + 2] = bytes32(c);
            proofs.proof[proof.length + 3] = bytes32(d);
        }
    }
    // The proof for writing to memory consists of a list of proof
    // from leaf to root.
    function writeMemory(State memory state, uint index, uint[4] values, Proofs memory proofs) pure internal {
        require(index < 1024);
        uint pos = 0x20 * 4 * index;
        uint[] memory fullMem = state.fullMemory;
        uint[4] memory oldValues;
        if (proofs.generateProofs) {
            oldValues[0] = fullMem[4 * index + 0];
            oldValues[1] = fullMem[4 * index + 1];
            oldValues[2] = fullMem[4 * index + 2];
            oldValues[3] = fullMem[4 * index + 3];
        }
        var (a, b, c, d) = (values[0], values[1], values[2], values[3]);
        assembly {
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), a)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), b)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), c)
            pos := add(pos, 0x20)
            mstore(add(fullMem, pos), d)
        }
        if (proofs.generateProofs) {
            (proofs.proof, state.memoryHash) = generateMemoryProof(state.fullMemory, index);
            // We need the values before we write - the siblings will still be the same.
            proofs.proof[0] = bytes32(oldValues[0]);
            proofs.proof[1] = bytes32(oldValues[1]);
            proofs.proof[2] = bytes32(oldValues[2]);
            proofs.proof[3] = bytes32(oldValues[3]);
        }
    }
    // Generate a proof that shows that the memory root hash was updated correctly.
    // Returns the value stored at the index (4 array elemets) followed by
    // a list of siblings (from leaf to root) and the new root hash.
    // This assumes that index is multiplied by four.
    // Since we know that memory is only written in sequence, this might be
    // optimized, but we keep it general for now.
    function generateMemoryProof(uint[] fullMem, uint index) internal pure returns (bytes32[] proof, bytes32) {
        uint access = index;
        proof = new bytes32[](14);
        proof[0] = bytes32(fullMem[4 * i]);
        proof[1] = bytes32(fullMem[4 * i + 1]);
        proof[2] = bytes32(fullMem[4 * i + 2]);
        proof[3] = bytes32(fullMem[4 * i + 3]);
        bytes32[] memory hashes = new bytes32[](1024);
        for (uint i = 0; i < 1024; i++)
            hashes[i] = keccak256(proof[0], proof[1], proof[2], proof[3]);
        uint numHashes = 1024;
        for (uint step = 4; step < proof.length; step++) {
            proof[step] = hashes[access ^ 1];
            access /= 2;
            numHashes /= 2;
            for (i = 0; i < numHashes; i++) {
                hashes[i] = keccak256(hashes[2 * i], hashes[2 * i + 1]);
            }
        }
        assert(numHashes == 1);
        return (proof, hashes[0]);
    }
}
