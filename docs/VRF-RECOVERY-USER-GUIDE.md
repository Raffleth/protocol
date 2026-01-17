# Raffl VRF Recovery - User Guide

## What This Means For You

Your funds are **safe**! If a raffle gets stuck, there are now built-in recovery options to ensure you can always get
your money back.

---

## Quick Overview

### The Problem (Before)

Sometimes when a raffle ends, the system needs to randomly pick a winner using something called "Chainlink VRF" (a
secure random number generator). In rare cases, this process could get stuck, and your entry fees would be locked in the
contract forever. 😱

### The Solution (Now)

We've added **two recovery options** that anyone can use to fix stuck raffles:

1. **Retry** - Try requesting a new random number (use this first)
2. **Emergency Fail** - If stuck for 24+ hours, mark raffle as failed and enable refunds

---

## For Raffle Participants

### How to Tell if a Raffle is Stuck

After the raffle deadline passes, you'll see one of these states:

#### ✅ **Normal - Everything is Fine**

- Status: "Drawing winner..."
- Usually completes in a few minutes
- Winner announced automatically
- No action needed!

#### ⚠️ **Delayed - Might Need Help**

- Status: "Waiting for random number..."
- Been waiting for **more than 1 hour**
- You can help by clicking "Retry"
- Or just wait longer - it might complete on its own

#### 🔴 **Stuck - Needs Recovery**

- Status: "VRF Request Stuck"
- Been waiting for **24+ hours**
- You can click "Emergency Refund"
- Get your entry fees back

### What You Can Do

#### Option 1: Retry the Random Draw (Recommended First)

**When to use**: Raffle has been "drawing" for more than an hour

**What it does**: Asks for a new random number from Chainlink

**Steps**:

1. Go to the stuck raffle page
2. Click **"Retry Draw"** button
3. Confirm the transaction in your wallet
4. Wait a few minutes for the new draw

**Cost**: Small gas fee (usually $1-5 depending on network)

**Who can do this**: Anyone! You don't need to be the raffle creator or even a participant.

---

#### Option 2: Emergency Fail & Get Refund

**When to use**:

- Raffle stuck for **24+ hours**
- Multiple retry attempts failed
- Need your money back urgently

**What it does**:

- Marks raffle as failed
- Allows everyone to get refunds
- Creator gets their prizes back

**Steps**:

1. **Trigger Emergency Fail** (if not already done)
   - Go to stuck raffle page
   - Click **"Emergency Fail Raffle"** button
   - Confirm transaction
   - Wait for confirmation

2. **Get Your Refund**
   - Click **"Request Refund"** button
   - Confirm transaction
   - Receive your entry fees back!

**Cost**: Gas fees for transactions

**Who can do this**:

- Anyone can trigger emergency fail (after 24h)
- Each participant claims their own refund

---

## For Raffle Creators

### What Happens to Your Raffle

#### If Retry Works ✅

- Winner is selected randomly
- Prizes automatically transferred to winner
- Entry pool distributed according to your settings
- Everything proceeds normally!

#### If Emergency Fail is Used 🔄

- Raffle marked as "Failed"
- No winner selected
- Participants can claim refunds
- **You can recover your prizes!**

### How to Recover Your Prizes

If your raffle is emergency failed:

1. Go to your raffle page
2. Click **"Recover Prizes"** button
3. Confirm transaction
4. All your NFTs and tokens returned to you!

**Important**: You don't lose your prizes - you can always get them back! 🎉

---

## Step-by-Step Visual Guide

### Scenario 1: Normal Raffle (No Issues)

```
1. Raffle Ends → 2. Winner Drawn → 3. Prizes Sent → ✅ Complete
   (Deadline)        (2-5 minutes)      (Automatic)
```

### Scenario 2: Stuck Raffle - Retry Works

```
1. Raffle Ends → 2. Stuck (1+ hour) → 3. You Click "Retry" → 4. Winner Drawn → ✅ Complete
   (Deadline)       ⚠️ Waiting            (New request)         (2-5 minutes)
```

### Scenario 3: Stuck Raffle - Emergency Refund

```
1. Raffle Ends → 2. Stuck (24+ hours) → 3. Emergency Fail → 4. Everyone Gets Refunds
   (Deadline)       🔴 Still waiting        (Anyone can do)      (Manual claim)
```

---

## Frequently Asked Questions

### Q: Will I lose my money if a raffle gets stuck?

**A:** No! After 24 hours, anyone can trigger emergency fail, and you can get a full refund of your entry fees.

### Q: How long should I wait before retrying?

**A:** We recommend waiting at least 1 hour. The normal draw usually completes in minutes, but network congestion can
cause delays.

### Q: Can I retry multiple times?

**A:** Yes! If the first retry doesn't work, you can try again. Each retry requests a new random number.

### Q: Does retrying cost money?

**A:** Yes, you'll pay a small gas fee (transaction cost), typically $1-5 depending on the network. But you're helping
everyone in the raffle!

### Q: What if someone triggers emergency fail before 24 hours?

**A:** They can't! The smart contract enforces a strict 24-hour waiting period. Any attempt before that will be
rejected.

### Q: Do I have to be the raffle creator to retry or emergency fail?

**A:** No! Anyone can help recover a stuck raffle. It's community-powered! 💪

### Q: What happens to the prizes if a raffle is emergency failed?

**A:** The raffle creator can claim their prizes back using the "Recover Prizes" button. Nothing is lost!

### Q: Can the raffle still complete normally after someone clicks retry?

**A:** Yes! Sometimes the original request completes right as someone retries. The first one to complete wins, and the
raffle proceeds normally.

### Q: How do I know if I need to do anything?

**A:** The raffle page will show clear indicators:

- 🟢 Green: Everything normal
- 🟡 Yellow: Can retry (optional)
- 🔴 Red: Can emergency fail (after 24h)

### Q: Is my refund automatic after emergency fail?

**A:** No, you need to manually claim it by clicking "Request Refund" on the raffle page. This ensures you control when
you pay the gas fee.

### Q: What if I entered with tokens (not ETH)?

**A:** Works the same way! You'll get your tokens back when you claim your refund.

---

## Technical Terms Explained Simply

| Term               | What It Means                                                                   |
| ------------------ | ------------------------------------------------------------------------------- |
| **VRF**            | A system that picks truly random numbers in a secure way (used to pick winners) |
| **Chainlink**      | A trusted service that provides the random numbers                              |
| **Gas Fee**        | A small fee you pay to process transactions on the blockchain                   |
| **Smart Contract** | Automated code that runs the raffle (like a vending machine for raffles)        |
| **Transaction**    | Any action on the blockchain (like clicking a button that costs a small fee)    |
| **Pending**        | Waiting for something to complete                                               |
| **Fulfilled**      | Successfully completed                                                          |
| **Failed**         | Didn't work, but refunds are available                                          |

---

## Warning Signs to Watch For

### 🟢 All Good

- Raffle ended less than 1 hour ago
- Status shows "Drawing winner..."
- Just be patient!

### 🟡 Might Need Help

- Raffle ended 1-4 hours ago
- Status still shows "Drawing winner..."
- Consider clicking "Retry" or wait a bit more

### 🔴 Definitely Stuck

- Raffle ended 24+ hours ago
- No winner announced
- Click "Emergency Fail Raffle" to enable refunds

---

## What Network Am I On?

The retry system works on all supported networks, but timing varies:

### Ethereum Mainnet

- Usually very reliable
- Retry after: 2-4 hours if stuck
- Emergency fail after: 24 hours

### Polygon / Base / Arbitrum / Optimism

- Usually reliable but can have occasional delays
- Retry after: 1 hour if stuck
- Emergency fail after: 24 hours

---

## Need Help?

### Before Asking for Help

1. Check the raffle status on the page
2. Wait at least 1 hour after deadline
3. Try the "Retry" button if available
4. Check if others are reporting the same issue

### Getting Support

- **Discord**: [Join our community](https://discord.gg/raffl)
- **Twitter**: [@RafflProtocol](https://twitter.com/raffl)
- **Email**: support@raffl.io
- **Documentation**: [docs.raffl.io](https://docs.raffl.io)

### What to Include in Your Support Request

1. Raffle address (the long 0x... code)
2. Network you're on (Ethereum, Polygon, etc.)
3. How long it's been stuck
4. Screenshot of the status
5. Your wallet address (if asking about refund)

---

## Safety Tips

### ✅ Do This

- Wait at least 1 hour before worrying
- Check the raffle page for status updates
- Try "Retry" before "Emergency Fail"
- Claim your refund if raffle is marked failed
- Help others by triggering retry if you see a stuck raffle

### ❌ Don't Do This

- Don't panic if raffle takes 30-60 minutes
- Don't try to emergency fail before 24 hours (won't work anyway)
- Don't send tokens directly to the raffle contract
- Don't spam the retry button (once is enough, wait 10 minutes)
- Don't worry about losing funds - refunds are guaranteed!

---

## Real Example Walkthrough

### Sarah's Stuck Raffle Experience

**Monday 2:00 PM**: Sarah enters a raffle for a rare NFT  
**Tuesday 2:00 PM**: Raffle deadline passes  
**Tuesday 2:02 PM**: Status shows "Drawing winner..."  
**Tuesday 3:30 PM**: Still drawing... Sarah is getting concerned  
**Tuesday 4:00 PM**: Sarah clicks "Retry Draw" button  
**Tuesday 4:05 PM**: Winner announced! It worked! 🎉

### Mike's Emergency Refund Experience

**Sunday 10:00 AM**: Mike enters a raffle  
**Monday 10:00 AM**: Raffle deadline passes  
**Monday 10:05 AM**: Status shows "Drawing winner..."  
**Tuesday 10:00 AM**: Still stuck! 24 hours passed  
**Tuesday 10:05 AM**: Mike clicks "Emergency Fail Raffle"  
**Tuesday 10:10 AM**: Transaction confirms - raffle marked as failed  
**Tuesday 10:15 AM**: Mike clicks "Request Refund"  
**Tuesday 10:20 AM**: Mike gets his entry fee back! ✅

---

## Quick Action Guide

### If You're a Participant

| Time Since Deadline | What to Do                     |
| ------------------- | ------------------------------ |
| Less than 1 hour    | ☕ Relax, grab a coffee        |
| 1-4 hours           | 🔄 Can retry (optional)        |
| 4-24 hours          | 🔄 Retry recommended           |
| 24+ hours           | 🚨 Emergency fail & get refund |

### If You're the Creator

| Time Since Deadline | What to Do                        |
| ------------------- | --------------------------------- |
| Less than 1 hour    | ⏳ Wait patiently                 |
| 1-4 hours           | 🔄 Consider retrying              |
| 4-24 hours          | 🔄 Retry or ask community         |
| 24+ hours           | 🚨 Emergency fail, recover prizes |

---

## Success Stories

> "My raffle got stuck for 3 hours. I clicked retry and it completed in 5 minutes. Super easy!" - Alex, Raffle Creator

> "I was worried my $500 entry was gone forever. After 25 hours, I clicked emergency fail and got my full refund. Huge
> relief!" - Jenny, Participant

> "I wasn't even in the raffle, but I saw it was stuck and clicked retry to help out the community. Feels good!" -
> Marcus, Good Samaritan

---

## Remember

- 🛡️ **Your funds are always safe**
- ⏰ **Time-locked protections** prevent premature fails
- 🤝 **Community-powered** - anyone can help
- 💰 **Full refunds** guaranteed after 24h
- 🎯 **Creator prizes** never lost

---

## Last Resort Contact

If you've tried everything and still need help:

**Emergency Support Email**: emergency@raffl.io  
**Response Time**: Within 24 hours  
**Include**: Raffle address, network, and description of issue

---

_This guide is updated regularly. Last update: January 2026_

_For technical details, see [VRF Recovery Technical Documentation](./VRF-RECOVERY-TECHNICAL.md)_

---

## Quick Links

- [Return to Main Docs](./README.md)
- [How to Create a Raffle](./CREATE-RAFFLE.md)
- [How to Enter a Raffle](./ENTER-RAFFLE.md)
- [FAQ](./FAQ.md)
- [Troubleshooting](./TROUBLESHOOTING.md)
