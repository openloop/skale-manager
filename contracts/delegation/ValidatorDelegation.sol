/*
    ValidatorDelegation.sol - SKALE Manager
    Copyright (C) 2019-Present SKALE Labs
    @author Dmytro Stebaiev

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity ^0.5.3;


contract ValidatorDelegation {
    uint validatorId = 1;
    struct Validator {
        address ownerAddress;
        string name;
        string description;
        uint validatorFeeShare;
        uint lastBountyCollectionMonth;
    }

    mapping (uint => Validator) public validators;
    mapping (address => uint) public validatorAddressToId;

    function registerValidator(
        string calldata name,
        string calldata description,
        uint validatorFeeShare
    )
        external returns (uint newValidatorId)
    {
        newValidatorId = validatorId++;
        validators[newValidatorId] = Validator(
            msg.sender,
            name,
            description,
            validatorFeeShare,
            0
        );
        validatorAddressToId[msg.sender] = newValidatorId;
    }

    function checkValidatorAddressToId(address validatorAddress, uint validatorID) external view returns (bool) {
        return validatorAddressToId[validatorAddress] == validatorID ? true : false;
    }
}