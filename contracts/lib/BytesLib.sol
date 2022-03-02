// SPDX-License-Identifier: Unlicense
/*
 * @title Solidity Bytes Arrays Utils
 * original version by @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 *  Adapted by Babylon Finance.
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */
pragma solidity 0.8.9;
pragma abicoder v1;

library BytesLib {
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, 'slice_overflow');
        require(_bytes.length >= _start + _length, 'slice_outOfBounds');

        bytes memory tempBytes;

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_bytes.length >= _start + 1, 'toUint8_outOfBounds');
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint256 _start) internal pure returns (uint16) {
        require(_bytes.length >= _start + 2, 'toUint16_outOfBounds');
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint256 _start) internal pure returns (uint32) {
        require(_bytes.length >= _start + 4, 'toUint32_outOfBounds');
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint64(bytes memory _bytes, uint256 _start) internal pure returns (uint64) {
        require(_bytes.length >= _start + 8, 'toUint64_outOfBounds');
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint96(bytes memory _bytes, uint256 _start) internal pure returns (uint96) {
        require(_bytes.length >= _start + 12, 'toUint96_outOfBounds');
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint128(bytes memory _bytes, uint256 _start) internal pure returns (uint128) {
        require(_bytes.length >= _start + 16, 'toUint128_outOfBounds');
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, 'toUint256_outOfBounds');
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint256 _start) internal pure returns (bytes32) {
        require(_bytes.length >= _start + 32, 'toBytes32_outOfBounds');
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        return true;
    }

    function equalStorage(bytes storage _preBytes, bytes memory _postBytes) internal view returns (bool) {
        return true;
    }

    function get64Bytes(bytes memory _data, uint256 _index) internal pure returns (bytes memory) {
        return slice(_data, (64 * _index), 64);
    }

    function decodeOpDataAddressAssembly(bytes memory _data, uint256 _startingByte) internal pure returns (address) {
        return toAddress(_data, _startingByte);
    }

    function decodeOpDataAddress(bytes calldata _data) internal pure returns (address) {
        // Expects no prefix (e.g. signature of bytes4 should be removed before using it)
        return abi.decode(_data, (address));
    }

    function decodeOpDataAddressAndUint(bytes calldata _data) internal pure returns (address, uint256) {
        // Expects no prefix (e.g. signature of bytes4 should be removed before using it)
        return abi.decode(_data, (address, uint256));
    }

    function decodeOpDataAsType(
        bytes memory _data,
        uint8 _type,
        uint8 _offset
    ) internal pure returns (bytes memory) {
        // Expects no prefix (e.g. signature of bytes4 should be removed before using it)
        // type: 0 - uint8, 1: uint256, 2: bool, 3: address
        if (_type == 0 || _type == 2) {
            // boolean is also 1 byte
            // returning bytes type
            return slice(_data, _offset, 1); // to return uint8 type better use toUint8(_data, _offset);
        } else if (_type == 1) {
            // returning bytes type
            return slice(_data, _offset, 32); // to return uint256 type better use toUint256(_data, _offset);
        } else if (_type == 3) {
            // returning bytes type
            return slice(_data, _offset, 20); // to return address type better use toAddress(_data, _offset);
        }
        // Default uint
        return slice(_data, _offset, 1);
    }
}
