# Fee Router Contract

A Sui Move smart contract for automated fee collection on token swaps and transfers. Perfect for DEXs, payment processors, and any application requiring transparent fee management.

## Features

- **Automated Fee Collection**: Seamlessly deducts a percentage fee from incoming tokens
- **Secure Treasury Management**: Admin-controlled fee withdrawals with event tracking
- **Flexible Fee Structure**: Configurable fee percentage (0-10% maximum)
- **Comprehensive Statistics**: Track total fees collected and volume processed
- **Event Tracking**: Detailed events for all fee operations and admin actions
- **Type Safety**: Works with any Sui coin type (SUI, USDC, etc.)
- **Multiple Return Options**: Choose between returning coins directly or to sender
- **Protection Against Abuse**: Maximum fee cap, zero-amount validation, overflow protection

## Prerequisites

- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) installed
- A Sui wallet with sufficient balance for gas fees
- Basic understanding of Sui Move and command-line operations

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/tomcrown/fee_router.git
cd fee_router
```

### 2. Project Structure

```
fee_router/
├── Move.toml
└── sources/
    └── fee_router.move
```

### 3. Build the Contract

```bash
sui move build
```

If successful, you should see:

```
BUILDING fee_router
```

### 4. Deploy to Sui Network

#### Deploy to Testnet

```bash
sui client publish --gas-budget 100000000
```

#### Deploy to Mainnet

```bash
sui client publish --gas-budget 100000000
```

After deployment, save the **Package ID** from the output. You'll need this for all function calls.

Example output:

```
Published Objects:
  PackageID: 0x1234567890abcdef...
```

## Usage

### Step 1: Initialize a Fee Treasury

Before collecting fees, you must create a treasury for each token type.

#### Parameters

- `fee_bps`: Fee in basis points (100 = 1%, 500 = 5%, max 1000 = 10%)
- `type-args`: The coin type (e.g., `0x2::sui::SUI`)

#### Example: Create Treasury with 2.5% Fee

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function init_treasury \
  --type-args 0x2::sui::SUI \
  --args 250 \
  --gas-budget 10000000
```

After creation, save the **Treasury Object ID** from the transaction output. You'll need this for all fee operations.

### Step 2: Collect Fees

#### Function 1: take_fee_and_return

Process a fee and return the remaining coin to your application (recommended for production).

##### Parameters

- `treasury`: The treasury object ID for this coin type
- `coin_in`: The coin object to collect fees from
- `clock`: Sui clock object (`0x6`)
- `type-args`: The coin type

##### Example: Collect Fee and Continue Processing

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function take_fee_and_return \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         <COIN_OBJECT_ID> \
         0x6 \
  --gas-budget 10000000
```

The returned coin (after fee deduction) can be used in subsequent operations within the same programmable transaction block (PTB).

#### Function 2: take_fee_and_return_to_sender

Process a fee and automatically transfer the remaining coin back to sender (useful for CLI testing).

##### Example: Collect Fee and Return to Sender

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function take_fee_and_return_to_sender \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         <COIN_OBJECT_ID> \
         0x6 \
  --gas-budget 10000000
```

## Understanding Fee Calculation

Fees are calculated using **basis points (BPS)**:

- 1 basis point = 0.01%
- 100 basis points = 1%
- 10,000 basis points = 100%

### Fee Examples

| BPS  | Percentage | Input Amount | Fee Collected | Amount Returned |
| ---- | ---------- | ------------ | ------------- | --------------- |
| 50   | 0.5%       | 10 SUI       | 0.05 SUI      | 9.95 SUI        |
| 100  | 1%         | 10 SUI       | 0.1 SUI       | 9.9 SUI         |
| 250  | 2.5%       | 10 SUI       | 0.25 SUI      | 9.75 SUI        |
| 500  | 5%         | 10 SUI       | 0.5 SUI       | 9.5 SUI         |
| 1000 | 10%        | 10 SUI       | 1 SUI         | 9 SUI           |

### Fee Calculation Formula

```
fee_amount = (input_amount × fee_bps) / 10000
remaining_amount = input_amount - fee_amount
```

## Admin Functions

Only the treasury admin can perform these operations.

### Update Fee Percentage

Change the fee percentage for future transactions (does not affect past fees).

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function update_fee \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         300 \
         0x6 \
  --gas-budget 10000000
```

This updates the fee to 3% (300 basis points).

### Withdraw Collected Fees

Withdraw a specific amount of collected fees to the admin address.

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function withdraw_fees \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         1000000000 \
         0x6 \
  --gas-budget 10000000
```

This withdraws 1 SUI from collected fees.

### Withdraw All Fees

Withdraw all collected fees at once.

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function withdraw_all_fees \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         0x6 \
  --gas-budget 10000000
```

### Transfer Admin Rights

Transfer treasury control to a new admin address.

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module fee_router \
  --function transfer_admin \
  --type-args 0x2::sui::SUI \
  --args <TREASURY_OBJECT_ID> \
         0xNEW_ADMIN_ADDRESS \
         0x6 \
  --gas-budget 10000000
```

## Using Different Coin Types

The contract works with any Sui coin type. Simply change the `--type-args` parameter:

### SUI (Native Token)

```bash
--type-args 0x2::sui::SUI
```

### USDC

```bash
--type-args <USDC_PACKAGE_ID>::usdc::USDC
```

### Custom Token

```bash
--type-args <TOKEN_PACKAGE_ID>::<MODULE_NAME>::<TYPE_NAME>
```

**Important**: You need a separate treasury for each token type.

## Events

The contract emits detailed events for transparency and tracking:

### FeeCollectedEvent

Emitted every time a fee is collected:

```rust
{
    treasury_id: address,       // Treasury object address
    user: address,              // User who paid the fee
    coin_type: TypeName,        // Token type (e.g., "0x2::sui::SUI")
    amount_in: u64,             // Original amount before fee
    fee_amount: u64,            // Fee collected
    timestamp_ms: u64           // Unix timestamp in milliseconds
}
```

### FeeWithdrawnEvent

Emitted when admin withdraws fees:

```rust
{
    treasury_id: address,       // Treasury object address
    admin: address,             // Admin who withdrew
    coin_type: TypeName,        // Token type
    amount_withdrawn: u64,      // Amount withdrawn
    remaining_balance: u64,     // Remaining treasury balance
    timestamp_ms: u64           // Unix timestamp
}
```

### FeeUpdatedEvent

Emitted when fee percentage is changed:

```rust
{
    treasury_id: address,       // Treasury object address
    admin: address,             // Admin who updated
    old_fee_bps: u64,           // Previous fee in BPS
    new_fee_bps: u64,           // New fee in BPS
    timestamp_ms: u64           // Unix timestamp
}
```

### AdminTransferredEvent

Emitted when admin rights are transferred:

```rust
{
    treasury_id: address,       // Treasury object address
    old_admin: address,         // Previous admin
    new_admin: address,         // New admin
    timestamp_ms: u64           // Unix timestamp
}
```

## Error Codes

| Code | Constant             | Description                                   |
| ---- | -------------------- | --------------------------------------------- |
| 1    | ENotAdmin            | Caller is not the treasury admin              |
| 2    | EFeeTooHigh          | Fee percentage exceeds 10% (1000 BPS) max     |
| 3    | EInsufficientBalance | Treasury doesn't have enough fees to withdraw |
| 4    | EZeroAmount          | Cannot process zero-amount transactions       |

### Common Error Solutions

**Error: "ENotAdmin"**

- Ensure you're calling admin functions from the admin wallet
- Check the treasury admin address using `get_admin`
- If admin changed, use the new admin wallet

**Error: "EFeeTooHigh"**

- Maximum allowed fee is 10% (1000 basis points)
- Reduce your fee percentage to 1000 or below
- This is a security feature to prevent abuse

**Error: "EInsufficientBalance"**

- Check current treasury balance using `get_collected_fees`
- Reduce withdrawal amount or wait for more fees to accumulate
- Use `withdraw_all_fees` to withdraw available balance

**Error: "EZeroAmount"**

- Ensure the coin you're processing has a non-zero value
- Check coin balance before calling fee functions
- Use `sui client gas` to verify coin amounts

## Security Considerations

1. **Maximum Fee Protection**: Fees are capped at 10% to prevent exploitation
2. **Admin-Only Controls**: Only designated admin can withdraw fees or change settings
3. **Immutable Contract**: Once deployed, core logic cannot be modified
4. **Shared Treasury**: Treasury is shared (not owned), allowing permissionless fee collection
5. **Event Transparency**: All operations emit events for audit trails
6. **Overflow Protection**: Fee calculations use checked arithmetic
7. **Zero-Amount Validation**: Prevents gas waste on empty transactions
8. **Atomic Operations**: Fee collection and balance updates happen atomically

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Test thoroughly on testnet
5. Submit a pull request with detailed description
