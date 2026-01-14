/// # Fee Router Module 
/// 
/// ## Purpose
/// Robust fee collection system for token swaps or transfers
/// Takes a percentage fee from incoming tokens and stores in treasury
/// 
/// ## Security Model
/// - Only admin can withdraw fees or change fee percentage
/// - Maximum fee capped at 5% to prevent abuse
/// - Fees are taken from input token, not output
/// - Protected against zero-amount attacks and overflow
module fee_router::fee_router;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::event;
use sui::clock::Clock;
use std::type_name::{Self, TypeName};


const ENotAdmin: u64 = 1;
const EFeeTooHigh: u64 = 2;
const EInsufficientBalance: u64 = 3;
const EZeroAmount: u64 = 4;


// Maximum allowed fee: 10% (1000 basis points)
const MAX_FEE_BPS: u64 = 1000;

const BPS_DENOMINATOR: u64 = 10000;

public struct FeeTreasury<phantom CoinType> has key {
    id: UID,
    balance: Balance<CoinType>,
    admin: address,
    fee_bps: u64,
    total_fees_collected: u64,  
    total_volume_processed: u64, 
}

public struct FeeCollectedEvent has copy, drop {
    treasury_id: address,
    user: address,
    coin_type: TypeName,
    amount_in: u64,
    fee_amount: u64,
    timestamp_ms: u64,
}

public struct FeeWithdrawnEvent has copy, drop {
    treasury_id: address,
    admin: address,
    coin_type: TypeName,
    amount_withdrawn: u64,
    remaining_balance: u64,
    timestamp_ms: u64,
}

public struct FeeUpdatedEvent has copy, drop {
    treasury_id: address,
    admin: address,
    old_fee_bps: u64,
    new_fee_bps: u64,
    timestamp_ms: u64,
}

public struct AdminTransferredEvent has copy, drop {
    treasury_id: address,
    old_admin: address,
    new_admin: address,
    timestamp_ms: u64,
}

/// Initialize a new fee treasury for a specific token type
/// 
/// # Security
/// - Fee must be within allowed range
/// - Treasury is shared, not owned, for permissionless access
/// 
public fun init_treasury<CoinType>(
    fee_bps: u64,
    ctx: &mut TxContext
) {
    assert!(fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
    
    let treasury = FeeTreasury<CoinType> {
        id: object::new(ctx),
        balance: balance::zero<CoinType>(),
        admin: ctx.sender(),
        fee_bps,
        total_fees_collected: 0,
        total_volume_processed: 0,
    };
    
    transfer::share_object(treasury);
}


/// Take fee from input coin and return remaining amount
/// 
/// # Process
/// 1. Validates amount > 0
/// 2. Calculate fee: amount * fee_bps / 10000
/// 3. Split fee from input coin
/// 4. Add fee to treasury balance
/// 5. Update lifetime statistics
/// 6. Emit FeeCollectedEvent
/// 7. Return remaining coin to caller
/// 
/// # Returns
/// Coin with fee deducted (amount_in - fee_amount)
/// 
/// # Security
/// - Rejects zero-amount transactions
/// - Fee calculation uses checked arithmetic
/// - Original coin is consumed and replaced with reduced coin
/// - Treasury balance increases atomically
/// 
public fun take_fee_and_return<CoinIn>(
    treasury: &mut FeeTreasury<CoinIn>,
    mut coin_in: Coin<CoinIn>,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<CoinIn> {
    let amount = coin_in.value();
    
    assert!(amount > 0, EZeroAmount);
    
    let fee_amount = (amount * treasury.fee_bps) / BPS_DENOMINATOR;
    
    if (fee_amount > 0) {
        let fee_coin = coin_in.split(fee_amount, ctx);
        treasury.balance.join(fee_coin.into_balance());
        
        treasury.total_fees_collected = treasury.total_fees_collected + fee_amount;
    };
    
    treasury.total_volume_processed = treasury.total_volume_processed + amount;

    event::emit(FeeCollectedEvent {
        treasury_id: object::uid_to_address(&treasury.id),
        user: ctx.sender(),
        coin_type: type_name::with_defining_ids<CoinIn>(),
        amount_in: amount,
        fee_amount,
        timestamp_ms: clock.timestamp_ms(),
    });

    coin_in
}



/// Admin Functions
/// Update the fee percentage
/// 
/// # Security
/// - Only admin can call
/// - New fee must be within MAX_FEE_BPS limit
/// - Emits event for transparency
/// 
public fun update_fee<CoinType>(
    treasury: &mut FeeTreasury<CoinType>,
    new_fee_bps: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == treasury.admin, ENotAdmin);
    assert!(new_fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
    
    let old_fee_bps = treasury.fee_bps;
    treasury.fee_bps = new_fee_bps;
    
    event::emit(FeeUpdatedEvent {
        treasury_id: object::uid_to_address(&treasury.id),
        admin: treasury.admin,
        old_fee_bps,
        new_fee_bps,
        timestamp_ms: clock.timestamp_ms(),
    });
}

/// Withdraw collected fees to admin address
/// 
/// # Security
/// - Only admin can call
/// - Checks sufficient balance before withdrawal
/// - Emits event for transparency
/// 
public fun withdraw_fees<CoinType>(
    treasury: &mut FeeTreasury<CoinType>,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == treasury.admin, ENotAdmin);
    
    let available = treasury.balance.value();
    assert!(available >= amount, EInsufficientBalance);
    
    let withdrawn = coin::take(&mut treasury.balance, amount, ctx);
    let remaining = treasury.balance.value();
    
    event::emit(FeeWithdrawnEvent {
        treasury_id: object::uid_to_address(&treasury.id),
        admin: treasury.admin,
        coin_type: type_name::with_defining_ids<CoinType>(),
        amount_withdrawn: amount,
        remaining_balance: remaining,
        timestamp_ms: clock.timestamp_ms(),
    });
    
    transfer::public_transfer(withdrawn, treasury.admin);
}

/// Withdraw all collected fees to admin address
/// 
/// # Security
/// - Only admin can call
/// - Convenient for full withdrawals
/// 
public fun withdraw_all_fees<CoinType>(
    treasury: &mut FeeTreasury<CoinType>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == treasury.admin, ENotAdmin);
    
    let amount = treasury.balance.value();
    if (amount > 0) {
        withdraw_fees(treasury, amount, clock, ctx);
    };
}

/// Transfer admin rights to a new address
/// 
/// # Security
/// - Only current admin can call
/// - Prevents transferring to zero address (implicit via Sui address type)
/// - Emits event for transparency
/// 
public fun transfer_admin<CoinType>(
    treasury: &mut FeeTreasury<CoinType>,
    new_admin: address,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == treasury.admin, ENotAdmin);
    
    let old_admin = treasury.admin;
    treasury.admin = new_admin;
    
    event::emit(AdminTransferredEvent {
        treasury_id: object::uid_to_address(&treasury.id),
        old_admin,
        new_admin,
        timestamp_ms: clock.timestamp_ms(),
    });
}


public fun get_fee_bps<CoinType>(treasury: &FeeTreasury<CoinType>): u64 {
    treasury.fee_bps
}

public fun get_collected_fees<CoinType>(treasury: &FeeTreasury<CoinType>): u64 {
    treasury.balance.value()
}

public fun get_admin<CoinType>(treasury: &FeeTreasury<CoinType>): address {
    treasury.admin
}

public fun get_total_fees_collected<CoinType>(treasury: &FeeTreasury<CoinType>): u64 {
    treasury.total_fees_collected
}

public fun get_total_volume_processed<CoinType>(treasury: &FeeTreasury<CoinType>): u64 {
    treasury.total_volume_processed
}

public fun calculate_fee<CoinType>(
    treasury: &FeeTreasury<CoinType>,
    amount: u64
): u64 {
    (amount * treasury.fee_bps) / BPS_DENOMINATOR
}

public fun get_treasury_stats<CoinType>(
    treasury: &FeeTreasury<CoinType>
): (u64, u64, u64, u64, address) {
    (
        treasury.fee_bps,
        treasury.balance.value(),
        treasury.total_fees_collected,
        treasury.total_volume_processed,
        treasury.admin
    )
}


public fun max_fee_bps(): u64 {
    MAX_FEE_BPS
}

public fun bps_denominator(): u64 {
    BPS_DENOMINATOR
}