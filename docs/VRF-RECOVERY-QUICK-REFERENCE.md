# VRF Recovery - Quick Reference Card

Quick reference for developers integrating Raffl Protocol VRF recovery features.

---

## Contract Interface

### View Functions

```solidity
// Get VRF request details
function getVRFRequestInfo(address raffle)
    returns (uint256 requestId, uint256 requestTime, VRFStatus status)

// Check if timeout elapsed
function hasVRFRequestTimedOut(address raffle)
    returns (bool)

// VRF Status enum
enum VRFStatus { None, Pending, Fulfilled, Failed }
```

### Write Functions

```solidity
// Retry VRF request (anyone can call)
function retryVRFRequest(address raffle) external

// Emergency fail after timeout (anyone can call)
function emergencyFailRaffle(address raffle) external
```

### Events

```solidity
event VRFRequestRetried(address indexed raffle, uint256 indexed requestId);
event RaffleEmergencyFailed(address indexed raffle);
```

### Errors

```solidity
error InvalidVRFRequest();        // Raffle doesn't exist
error VRFRequestNotPending();     // Status is not Pending
error VRFRequestNotTimedOut();    // Timeout not reached (< 24h)
```

---

## JavaScript Quick Start

### Check Status

```javascript
const [requestId, requestTime, status] = await factory.getVRFRequestInfo(raffleAddress);

// Status: 0=None, 1=Pending, 2=Fulfilled, 3=Failed
const isPending = status === 1;
const canRetry = isPending && Date.now() / 1000 - requestTime > 3600;
const canEmergencyFail = await factory.hasVRFRequestTimedOut(raffleAddress);
```

### Retry VRF

```javascript
const tx = await factory.retryVRFRequest(raffleAddress, {
  gasLimit: 200000,
});
await tx.wait();
```

### Emergency Fail

```javascript
const tx = await factory.emergencyFailRaffle(raffleAddress, {
  gasLimit: 150000,
});
await tx.wait();
```

---

## Timing Reference

| Threshold            | Duration   | Action                 |
| -------------------- | ---------- | ---------------------- |
| **Immediate**        | 0-60 min   | Normal operation, wait |
| **Retry Window**     | 1-24 hours | Can retry VRF request  |
| **Emergency Window** | 24+ hours  | Can emergency fail     |

---

## Gas Estimates

| Function                | Gas   | Notes           |
| ----------------------- | ----- | --------------- |
| `getVRFRequestInfo`     | ~5k   | View            |
| `hasVRFRequestTimedOut` | ~3k   | View            |
| `retryVRFRequest`       | ~150k | New VRF request |
| `emergencyFailRaffle`   | ~120k | State update    |

---

## Integration Checklist

### Frontend

- [ ] Display VRF status on raffle page
- [ ] Show "Retry" button when elapsed > 1h
- [ ] Show "Emergency Fail" button when elapsed > 24h
- [ ] Enable refund claims after emergency fail
- [ ] Monitor `VRFRequestRetried` events
- [ ] Monitor `RaffleEmergencyFailed` events

### Backend/Keeper

- [ ] Poll active raffles every 5 minutes
- [ ] Auto-retry after 1 hour (optional)
- [ ] Auto-emergency-fail after 24 hours (optional)
- [ ] Alert monitoring when raffles stuck
- [ ] Log all retry/emergency events

---

## Common Patterns

### Check If Action Needed

```javascript
async function needsRecovery(raffle) {
  const [, requestTime, status] = await factory.getVRFRequestInfo(raffle);

  if (status !== 1) return { retry: false, emergency: false };

  const elapsed = Date.now() / 1000 - requestTime.toNumber();
  return {
    retry: elapsed > 3600,
    emergency: elapsed > 86400,
  };
}
```

### Safe Retry with Error Handling

```javascript
async function safeRetry(raffle) {
  try {
    const { retry, emergency } = await needsRecovery(raffle);

    if (emergency) {
      return await factory.emergencyFailRaffle(raffle);
    } else if (retry) {
      return await factory.retryVRFRequest(raffle);
    }

    return { success: false, reason: "No action needed" };
  } catch (error) {
    if (error.message.includes("VRFRequestNotPending")) {
      return { success: false, reason: "Already fulfilled" };
    }
    throw error;
  }
}
```

### Monitor Active Raffles

```javascript
async function getStuckRaffles() {
  const raffles = await factory.activeRaffles();
  const stuck = [];

  for (const { raffle } of raffles) {
    const [, requestTime, status] = await factory.getVRFRequestInfo(raffle);

    if (status === 1) {
      const elapsed = Date.now() / 1000 - requestTime.toNumber();
      if (elapsed > 3600) {
        stuck.push({ raffle, elapsed });
      }
    }
  }

  return stuck;
}
```

---

## Error Handling

```javascript
try {
  await factory.retryVRFRequest(raffle);
} catch (error) {
  if (error.message.includes("InvalidVRFRequest")) {
    // Raffle doesn't exist
  } else if (error.message.includes("VRFRequestNotPending")) {
    // Already fulfilled or failed
  } else {
    // Other error
  }
}
```

---

## Testing Checklist

- [ ] VRF request tracking works
- [ ] Retry updates request ID and time
- [ ] Emergency fail only works after timeout
- [ ] Status transitions correctly
- [ ] Events emitted properly
- [ ] Refunds work after emergency fail
- [ ] Multiple retries work
- [ ] Gas estimates accurate

---

## Deployment Notes

### Environment Variables

```bash
# Chainlink VRF Configuration
VRF_COORDINATOR_ADDRESS=0x...
VRF_KEY_HASH=0x...
VRF_SUBSCRIPTION_ID=123
VRF_CALLBACK_GAS_LIMIT=500000
VRF_REQUEST_CONFIRMATIONS=3

# Factory Address
RAFFLE_FACTORY_ADDRESS=0x...

# Keeper Configuration (optional)
KEEPER_RETRY_THRESHOLD=3600      # 1 hour
KEEPER_EMERGENCY_THRESHOLD=86400 # 24 hours
KEEPER_CHECK_INTERVAL=300        # 5 minutes
```

### Contract Addresses

Update these in your deployment:

```javascript
const addresses = {
  // Mainnet
  ethereum: {
    factory: "0x...",
    vrfCoordinator: "0x...",
  },
  // L2s
  polygon: {
    factory: "0x...",
    vrfCoordinator: "0x...",
  },
  base: {
    factory: "0x...",
    vrfCoordinator: "0x...",
  },
};
```

---

## Security Notes

✅ **Safe**:

- Anyone can retry (permissionless)
- Anyone can emergency fail after timeout
- No privilege escalation
- No fund manipulation beyond intended recovery

⚠️ **Watch Out**:

- Check gas prices before auto-retry
- Monitor LINK balance in Chainlink subscription
- Log all recovery actions for audit
- Alert on repeated failures

---

## Monitoring Dashboard

Suggested metrics to track:

```javascript
const metrics = {
  totalRetries: 0, // Count of retry calls
  totalEmergencyFails: 0, // Count of emergency fails
  avgRetryTime: 0, // Average time until retry
  avgEmergencyTime: 0, // Average time until emergency
  successRate: 0, // VRF success rate
  activeStuckRaffles: 0, // Current stuck count
};
```

---

## Resources

- **Technical Docs**: [VRF-RECOVERY-TECHNICAL.md](./VRF-RECOVERY-TECHNICAL.md)
- **User Guide**: [VRF-RECOVERY-USER-GUIDE.md](./VRF-RECOVERY-USER-GUIDE.md)
- **Chainlink VRF**: [docs.chain.link/vrf/v2-5](https://docs.chain.link/vrf/v2-5)
- **Contract Source**: `src/RafflFactory.sol`
- **Tests**: `test/factory/RafflFactory.VRFRetry.t.sol`

---

## Support

- **Discord**: [discord.gg/raffl](https://discord.gg/raffl)
- **GitHub Issues**: [github.com/raffl/protocol/issues](https://github.com/raffl/protocol/issues)
- **Email**: dev@raffl.io

---

_Last Updated: January 2026_
