# ⛏️ Mine Worker Payment & Welfare System

A blockchain-based payroll system ensuring fair, timely, and transparent wage distribution for mine workers using Stacks smart contracts.

## 🚀 Features

- 💰 **Automated Payments**: Scheduled wage distribution based on configurable periods
- 📋 **On-chain Receipts**: Immutable payment records stored on blockchain
- 🛡️ **Micro-insurance**: Optional deductions for worker welfare fund
- 📊 **Worker Statistics**: Track earnings, hours, and payment history
- 🔒 **Secure & Transparent**: All transactions verifiable on-chain

## 🏗️ Contract Functions

### 👷 Worker Management
- `register-worker` - Register new worker with hourly rate and insurance preference
- `update-worker-hours` - Update worked hours for payment calculation
- `get-worker-info` - View worker details and current status

### 💸 Payment Processing
- `process-payment` - Execute individual worker payment
- `batch-process-payments` - Process multiple workers simultaneously
- `calculate-payment` - Preview payment amount before processing

### 💼 Employer Operations
- `deposit-funds` - Add STX to contract for payments
- `emergency-withdraw-funds` - Withdraw unused funds (owner only)
- `get-employer-balance` - Check available balance

### 🛡️ Insurance & Welfare
- `withdraw-insurance` - Workers can access their insurance balance
- `update-insurance-rate` - Adjust insurance deduction percentage
- `get-insurance-rate` - View current insurance rate

### 📈 Analytics & Reporting
- `get-worker-statistics` - Comprehensive worker payment data
- `get-payment-receipt` - Individual payment record lookup
- `get-all-worker-payments` - Historical payment range query

## 🛠️ Usage

### Setup
1. Deploy contract to Stacks blockchain
2. Contract deployer becomes owner automatically
3. Set payment period (default: 144 blocks ≈ 24 hours)
4. Set insurance rate (default: 3%)

### Register Workers
```clarity
(contract-call? .mine-worker-payment register-worker 'SP1... u50 true)
```
- Worker address
- Hourly rate in micro-STX
- Insurance enrollment (true/false)

### Process Payroll
```clarity
;; Update hours worked
(contract-call? .mine-worker-payment update-worker-hours 'SP1... u40)

;; Calculate payment preview
(contract-call? .mine-worker-payment calculate-payment 'SP1...)

;; Process payment
(contract-call? .mine-worker-payment process-payment 'SP1...)
```

### Fund Operations
```clarity
;; Employer deposits STX for payroll
(contract-call? .mine-worker-payment deposit-funds u1000000)
```

## 📋 Payment Flow

1. **Registration**: Owner registers workers with hourly rates
2. **Hour Tracking**: Owner updates hours worked per payment period  
3. **Funding**: Employer deposits STX to contract
4. **Payment**: Automatic/manual payment processing
5. **Receipt**: On-chain payment record created
6. **Insurance**: Optional deductions accumulated for welfare

## 🔧 Configuration

- **Payment Period**: Configurable block intervals (default: 144 blocks)
- **Insurance Rate**: Percentage deduction (default: 3%, max: 10%)
- **Batch Size**: Up to 50 workers per batch payment

## 🔐 Security Features

- Owner-only administrative functions
- Payment duplication prevention
- Balance validation before transfers
- Insurance withdrawal restrictions
- Emergency fund recovery

## 📊 Data Structures

### Worker Record
```clarity
{
  hourly-rate: uint,
  hours-worked: uint, 
  insurance-enabled: bool,
  last-payment-block: uint,
  total-earned: uint,
  insurance-balance: uint
}
```

### Payment Receipt
```clarity
{
  gross-amount: uint,
  insurance-deduction: uint,
  net-amount: uint,
  payment-block: uint,
  payment-hash: (buff 32)
}
```

## 🧪 Testing

Run tests using Clarinet:
```bash
clarinet test
```

## 📈 Benefits

- ✅ **Transparency**: All payments publicly verifiable
- ✅ **Reliability**: Blockchain-enforced payment schedules  
- ✅ **Security**: Cryptographic payment receipts
- ✅ **Efficiency**: Batch processing capabilities
- ✅ **Welfare**: Built-in insurance system
- ✅ **Auditability**: Complete payment history on-chain
