// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Errors {
    error SusuPool__NotOrganizer();
    error SusuPool__NotVRFManager();
    error SusuPool__PoolNotReady();
    error SusuPool__AlreadyJoined();
    error SusuPool__PoolFull();
    error SusuPool__NotMember();
    error SusuPool__NotYourTurn();
    error SusuPool__NotEligible();
    error SusuPool__PoolNotOrdered();
    error SusuPool__WrongAmount();
    error SusuPool__UnderCollateralized();
    error SusuPool__OrganizerZeroAddress();
    error SusuPool__AssetZeroAddress();
    error SusuPool__OracleZeroAddress();
    error SusuPool__VRFManagerZeroAddress();
    error SusuPool__CollateralNotEnabledZeroOracle();
    error SusuPool__MustHaveAtLeastTwoHands();
    error SusuPool__TooManyHands();
    error SusuPool__NoHandsAssigned();
    error SusuPool__PoolAmountZero();
    error SusuPool__PoolStateIsNotOpen();
    error PoolConfig__InvalidInterval();
    error SusuPool__RotationAlreadySet();
    error SusuPool__SingleHandOnly();
    error SusuPool__InvalidHand();
    error SusuPool__AlreadyClaimedHand();
    error SusuPool__BadOrderLength();
    error SusuPool__WaitInterval();
    error SusuPool__UserNotInRotation();
    error SusuPool__PoolStateNotOpen();
    error SusuPool__PoolStateNotLocked();
    error SusuPool__PoolStateNotActive();
    error SusuPool__PoolStateNotActiveAndOrdered();
    error SusuPool__OrderAlreadyRequested();
    error SusuPool__OrderNotRequested();
    error SusuFactory__InvalidAsset();
    error SusuFactory__InvalidOracle();
    error PoolConfig__InvalidTurn();
    error PoolConfig__PoolSizeTooSmall();
    error PoolConfig__PoolSizeTooBig();
    error SusuVRFManager__ZeroAddress();
    error SusuVRFManager__NotFactory();
}
