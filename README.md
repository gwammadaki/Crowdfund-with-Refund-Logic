# Crowdfund with Refund Logic
A secure and transparent crowdfunding solution on Stacks blockchain with automatic refund capability.

## 🚀 Features

- Secure crowdfunding campaign creation
- Automatic refund mechanism if target isn't met
- Real-time campaign status tracking
- Emergency shutdown capability
- Contribution management
- Deadline and target amount validation

## 🛠️ Technical Details

### Security Features
- Input validation for all public functions
- Access control checks for admin functions
- Safe STX transfer handling
- Deadline verification
- Double-claim prevention

### Optimizations
- Efficient state management
- Gas-optimized functions
- Minimal storage usage

## 📋 Usage Instructions

1. Deploy contract using Clarinet:
```bash
clarinet contract deploy
```

2. Initialize campaign:
```bash
clarinet contract call initialize
```

3. Contributors can participate:
```bash
clarinet contract call contribute
```

4. Check campaign status:
```bash
clarinet contract read get-campaign-status
```

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 🎨 UI Components

### Suggested UI Features:
1. Campaign Dashboard
   - Real-time funding progress
   - Countdown timer
   - Contributor lists
   - Refund status

2. Contribution Form
   - Amount input
   - Confirmation dialog
   - Transaction status

3. Admin Panel
   - Campaign management
   - Emergency controls
   - Beneficiary management
