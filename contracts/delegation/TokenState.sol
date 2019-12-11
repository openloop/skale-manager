/*
    TokenState.sol - SKALE Manager
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
pragma experimental ABIEncoderV2;

import "../Permissions.sol";
import "./DelegationController.sol";
import "./TimeHelpers.sol";


/// @notice Store and manage tokens states
contract TokenState is Permissions {

    enum State {
        NONE,
        UNLOCKED,
        PROPOSED,
        ACCEPTED,
        DELEGATED,
        ENDING_DELEGATED,
        PURCHASED,
        COMPLETED
    }

    ///delegationId => State
    mapping (uint => State) private _state;

    /// delegationId => timestamp
    mapping (uint => uint) private _timelimit;

    ///       holder => amount
    mapping (address => uint) private _purchased;
    ///       holder => amount
    mapping (address => uint) private _totalDelegated;

    ///       holder => delegationId[]
    mapping (address => uint[]) private _endingDelegations;

    constructor(address _contractManager) Permissions(_contractManager) public {
    }

    function getLockedCount(address holder) external returns (uint amount) {
        amount = 0;
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        uint[] memory delegationIds = delegationController.getDelegationsByHolder(holder);
        for (uint i = 0; i < delegationIds.length; ++i) {
            uint id = delegationIds[i];
            if (isLocked(getState(id))) {
                amount += delegationController.getDelegation(id).amount;
            }
        }
        return amount + getPurchasedAmount(holder);
    }

    function getDelegatedCount(address holder) external returns (uint amount) {
        amount = 0;
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        uint[] memory delegationIds = delegationController.getDelegationsByHolder(holder);
        for (uint i = 0; i < delegationIds.length; ++i) {
            uint id = delegationIds[i];
            if (isDelegated(getState(id))) {
                amount += delegationController.getDelegation(id).amount;
            }
        }
        return amount;
    }

    function setState(uint delegationId, State newState) external {
        TimeHelpers timeHelpers = TimeHelpers(contractManager.getContract("TimeHelpers"));
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));

        if (newState == State.PROPOSED) {
            if (_state[delegationId] != State.NONE) {
                revert("Only new delegations can be proposed");
            }

            _state[delegationId] = State.PROPOSED;
            _timelimit[delegationId] = timeHelpers.getNextMonthStart();

            DelegationController.Delegation memory delegation = delegationController.getDelegation(delegationId);
            if (_purchased[delegation.holder] > 0) {
                delegationController.setPurchased(delegationId, true);
                if (_purchased[delegation.holder] > delegation.amount) {
                    _purchased[delegation.holder] -= delegation.amount;
                } else {
                    _purchased[delegation.holder] = 0;
                }
            } else {
                delegationController.setPurchased(delegationId, false);
            }
        } else if (newState == State.PURCHASED) {
            revert("Use setPurchased function instead");
        } else if (newState == State.ACCEPTED) {
            State currentState = getState(delegationId);
            if (currentState != State.PROPOSED) {
                revert("Can't set state to accepted");
            }
            _state[delegationId] = State.ACCEPTED;
            _timelimit[delegationId] = timeHelpers.getNextMonthStart();
        } else if (newState == State.DELEGATED) {
            revert("Can't set state to delegated");
        } else if (newState == State.ENDING_DELEGATED) {
            if (getState(delegationId) != State.DELEGATED) {
                revert("Can't set state to ending delegated");
            }
            DelegationController.Delegation memory delegation = delegationController.getDelegation(delegationId);

            _state[delegationId] = State.ENDING_DELEGATED;
            _timelimit[delegationId] = timeHelpers.calculateDelegationEndTime(delegation.created, delegation.delegationPeriod, 3);
            _endingDelegations[delegation.holder].push(delegationId);
        } else if (newState == State.UNLOCKED) {
            revert("Can't set state to unlocked");
        } else {
            revert("Unknown state");
        }
    }

    function sold(address holder, uint amount) external {
        _purchased[holder] += amount;
    }

    function getState(uint delegationId) public returns (State state) {
        DelegationController delegationController = DelegationController(contractManager.getContract("DelegationController"));
        // TODO: Modify existance check
        require(delegationController.getDelegation(delegationId).holder != address(0), "Delegation does not exists");
        require(_state[delegationId] != State.NONE, "State is unknown");
        state = _state[delegationId];
        if (state == State.PROPOSED) {
            if (now >= _timelimit[delegationId]) {
                state = cancel(delegationId, delegationController.getDelegation(delegationId));
            }
        } else if (state == State.ACCEPTED) {
            if (now >= _timelimit[delegationId]) {
                state = acceptedToDelegated(delegationId);
            }
        } else if (state == State.ENDING_DELEGATED) {
            if (now >= _timelimit[delegationId]) {
                state = endingDelegatedToUnlocked(delegationId, delegationController.getDelegation(delegationId));
            }
        }
    }

    function cancel(uint delegationId, DelegationController.Delegation memory delegation) public returns (State state) {
        if (delegation.purchased) {
            state = purchasedProposedToPurchased(delegationId);
        } else {
            state = proposedToUnlocked(delegationId);
        }
    }

    // private

    function isLocked(State state) internal returns (bool) {
        return state != State.UNLOCKED && state != State.COMPLETED;
    }

    function isDelegated(State state) internal returns (bool) {
        return state == State.DELEGATED || state == State.ENDING_DELEGATED;
    }

    function getPurchasedAmount(address holder) internal returns (uint amount) {
        // check if any delegation was ended
        for (uint i = 0; i < _endingDelegations[holder].length; ++i) {
            getState(_endingDelegations[holder][i]);
        }
        return _purchased[holder];
    }

    function proposedToUnlocked(uint delegationId) internal returns (State state) {
        _state[delegationId] = State.COMPLETED;
        _timelimit[delegationId] = 0;
        return State.COMPLETED;
    }

    function acceptedToDelegated(uint delegationId) internal returns (State) {
        State state = State.DELEGATED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;
        return state;
    }

    function purchasedProposedToPurchased(uint delegationId) internal returns (State) {
        _state[delegationId] = State.COMPLETED;
        _timelimit[delegationId] = 0;
        return State.COMPLETED;
    }

    function endingDelegatedToUnlocked(uint delegationId, DelegationController.Delegation memory delegation) internal returns (State) {
        State state = State.UNLOCKED;
        _state[delegationId] = state;
        _timelimit[delegationId] = 0;

        // remove delegationId from _ending array
        uint endingLength = _endingDelegations[delegation.holder].length;
        for (uint i = 0; i < endingLength; ++i) {
            if (_endingDelegations[delegation.holder][i] == delegationId) {
                for (uint j = i; j + 1 < endingLength; ++j) {
                    _endingDelegations[delegation.holder][j] = _endingDelegations[delegation.holder][j+1];
                }
                _endingDelegations[delegation.holder][endingLength - 1] = 0;
                --_endingDelegations[delegation.holder].length;
            }
        }

        if (delegation.purchased) {
            address holder = delegation.holder;
            _totalDelegated[holder] += delegation.amount;
            if (_totalDelegated[holder] >= _purchased[holder]) {
                purchasedToUnlocked(holder);
            }
        }

        return state;
    }

    function purchasedToUnlocked(address holder) internal {
        _purchased[holder] = 0;
        _totalDelegated[holder] = 0;
    }
}
