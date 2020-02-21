/*
    TokenLaunchLocker.sol - SKALE Manager
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

import "../Permissions.sol";
import "../interfaces/delegation/ILocker.sol";
import "./DelegationController.sol";
import "./TimeHelpers.sol";


contract TokenLaunchLocker is Permissions, ILocker {

    struct PartialDifferences {
             // month => diff
        mapping (uint => uint) addDiff;
             // month => diff
        mapping (uint => uint) subtractDiff;
        uint value;

        uint firstUnprocessedMonth;
    }

    struct DelegatedAmountAndMonth {
        uint delegated;
        uint month;
    }

    //        holder => tokens
    mapping (address => uint) private _locked;

    //        holder => tokens
    mapping (address => PartialDifferences) private _delegatedAmount;

    mapping (address => DelegatedAmountAndMonth) private _totalDelegatedAmount;

    //        holder => month
    mapping (address => uint) private _latestDelegatedMonth;

    // delegationId => tokens
    mapping (uint => uint) private _delegationAmount;

    function lock(address holder, uint amount) external allow("TokenLaunchManager") {
        _locked[holder] += amount;
    }

    function handleDelegationAdd(
        address holder, uint delegationId, uint amount, uint month)
        external allow("DelegationController")
    {
        if (_locked[holder] > 0) {
            TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));

            uint currentMonth = timeHelpers.getCurrentMonth();
            uint fromLocked = amount;
            uint locked = _locked[holder] - calculateDelegatedAmount(holder, currentMonth);
            if (fromLocked > locked) {
                fromLocked = locked;
            }
            if (fromLocked > 0) {
                require(_delegationAmount[delegationId] == 0, "Delegation already was added");
                addToDelegatedAmount(holder, fromLocked, month);
                addToTotalDelegatedAmount(holder, fromLocked, month);
                _delegationAmount[delegationId] = fromLocked;
                if (month > _latestDelegatedMonth[holder]) {
                    _latestDelegatedMonth[holder] = month;
                }
            }
        }
    }

    function handleDelegationRemoving(address holder, uint delegationId, uint month) external allow("DelegationController") {
        if (_delegationAmount[delegationId] > 0) {
            if (_locked[holder] > 0) {
                removeFromDelegatedAmount(holder, _delegationAmount[delegationId], month);
                if (month > _latestDelegatedMonth[holder]) {
                    _latestDelegatedMonth[holder] = month;
                }
            }
            delete _delegationAmount[delegationId];
        }
    }

    function calculateLockedAmount(address wallet) external returns (uint) {
        if (_locked[wallet] > 0) {
            DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
            TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));

            uint currentMonth = timeHelpers.getCurrentMonth();
            if (_totalDelegatedAmount[wallet].delegated * 2 >= _locked[wallet] &&
                _totalDelegatedAmount[wallet].month + 3 <= currentMonth) {
                unlock(wallet);
                return 0;
            } else {
                uint lockedByDelegationController = calculateDelegatedAmount(wallet, currentMonth) + delegationController.getLockedInPendingDelegations(wallet);
                if (_locked[wallet] > lockedByDelegationController) {
                    return _locked[wallet] - lockedByDelegationController;
                } else {
                    return 0;
                }
            }
        } else {
            return 0;
        }
    }

    function calculateForbiddenForDelegationAmount(address wallet) external returns (uint) {
        return 0;
    }

    function initialize(address _contractManager) public initializer {
        Permissions.initialize(_contractManager);
    }

    // private

    function calculateDelegatedAmount(address holder, uint currentMonth) internal returns (uint) {
        if (_delegatedAmount[holder].firstUnprocessedMonth == 0) {
            return 0;
        }
        for (uint i = _delegatedAmount[holder].firstUnprocessedMonth; i <= currentMonth; ++i) {
            _delegatedAmount[holder].value += _delegatedAmount[holder].addDiff[i] - _delegatedAmount[holder].subtractDiff[i];
            delete _delegatedAmount[holder].addDiff[i];
            delete _delegatedAmount[holder].subtractDiff[i];
        }
        if (_delegatedAmount[holder].firstUnprocessedMonth < currentMonth + 1) {
            _delegatedAmount[holder].firstUnprocessedMonth = currentMonth + 1;
        }
        return _delegatedAmount[holder].value;
    }

    function addToDelegatedAmount(address holder, uint amount, uint month) internal {
        require(_delegatedAmount[holder].firstUnprocessedMonth <= month, "Can't add to the past");

        _delegatedAmount[holder].addDiff[month] += amount;
    }

    function removeFromDelegatedAmount(address holder, uint amount, uint month) internal {
        require(_delegatedAmount[holder].firstUnprocessedMonth <= month, "Can't remove from the past");

        _delegatedAmount[holder].subtractDiff[month] += amount;
    }

    function addToTotalDelegatedAmount(address holder, uint amount, uint month) internal {
        require(
            _totalDelegatedAmount[holder].month == 0 || _totalDelegatedAmount[holder].month <= month,
            "Can't add to total delegated in the past");

        _totalDelegatedAmount[holder].delegated += amount;
        _totalDelegatedAmount[holder].month = month;
    }

    function unlock(address holder) internal {
        delete _locked[holder];
        deleteDelegatedAmount(holder);
        deleteTotalDelegatedAmount(holder);
        delete _latestDelegatedMonth[holder];
    }

    function deleteDelegatedAmount(address holder) internal {
        for (uint i = _delegatedAmount[holder].firstUnprocessedMonth; i <= _latestDelegatedMonth[holder]; ++i) {
            delete _delegatedAmount[holder].addDiff[i];
            delete _delegatedAmount[holder].subtractDiff[i];
        }
        delete _delegatedAmount[holder].value;
        delete _delegatedAmount[holder].firstUnprocessedMonth;
    }

    function deleteTotalDelegatedAmount(address holder) internal {
        delete _totalDelegatedAmount[holder].delegated;
        delete _totalDelegatedAmount[holder].month;
    }
}