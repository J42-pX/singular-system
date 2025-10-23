# SingularSystem - Clarity Smart Contract Documentation

## Overview

This Clarity smart contract implements a liquid democracy DAO governance system with expertise-based delegation for the Stacks blockchain. It enables dynamic voting power distribution based on domain expertise and reputation scoring.

## Key Features

### 1. **Liquid Democracy & Delegation**
- Members can delegate voting power to experts in specific domains
- Direct circular delegation protection (A→B, B→A prevented)
- Delegations can be revoked at any time
- Simplified delegation model for Clarity compatibility

### 2. **Expertise Domains**
The system supports 5 expertise domains:
- `DOMAIN-TECHNICAL (1)`: Technical/development proposals
- `DOMAIN-FINANCIAL (2)`: Financial and treasury decisions
- `DOMAIN-GOVERNANCE (3)`: Governance and process changes
- `DOMAIN-COMMUNITY (4)`: Community initiatives
- `DOMAIN-OPERATIONS (5)`: Operational decisions

### 3. **Reputation System**
- Members have reputation scores (0-100) for each domain
- Reputation affects voting power calculation
- Scores updated by contract owner (oracle integration point)
- Formula: `voting_power = (base_power * 70% + reputation * 30%)`

### 4. **Proposal System**
- Domain-specific proposals
- Configurable voting periods (minimum 1440 blocks ≈ 10 days)
- Automatic vote counting
- Finalization after voting period ends

## Core Functions

### Member Management

#### `register-member (initial-power uint)`
Initialize or update member's base voting power.

```clarity
(contract-call? .singular-system register-member u100)
```

#### `update-reputation (member principal) (domain uint) (new-score uint)`
Update member's reputation score for a specific domain (owner only).

```clarity
(contract-call? .singular-system update-reputation 'ST1... u1 u85)
```

### Delegation

#### `delegate-vote (delegate principal) (domain uint)`
Delegate voting power to another member for a specific domain.

```clarity
(contract-call? .singular-system delegate-vote 'ST1PQHQKV... u1)
```

#### `revoke-delegation (domain uint)`
Revoke delegation for a specific domain.

```clarity
(contract-call? .singular-system revoke-delegation u1)
```

### Proposals

#### `create-proposal (title) (description) (domain) (voting-period)`
Create a new proposal for community voting.

```clarity
(contract-call? .singular-system create-proposal
    "Upgrade Protocol"
    "Proposal to upgrade the core protocol"
    u1  ;; Technical domain
    u2880  ;; ~20 days
)
```

#### `vote (proposal-id uint) (vote-for bool)`
Cast a vote on an active proposal.

```clarity
(contract-call? .singular-system vote u1 true)
```

#### `finalize-proposal (proposal-id uint)`
Finalize proposal after voting period ends.

```clarity
(contract-call? .singular-system finalize-proposal u1)
```

## Read-Only Functions

### `get-proposal (proposal-id uint)`
Retrieve proposal details.

### `get-member-reputation (member principal) (domain uint)`
Get member's reputation for a specific domain.

### `get-delegation (delegator principal) (domain uint)`
Check delegation status.

### `get-member-power (member principal)`
Get member's base voting power.

### `calculate-voting-power (member principal) (domain uint)`
Calculate effective voting power for a member in a domain.

### `would-create-circular-delegation (delegator principal) (delegate principal) (domain uint)`
Check if a delegation would create a direct circular reference (A→B and B→A).

### `get-proposal (proposal-id uint)`

### Proposals Map
```clarity
{
    proposer: principal,
    title: string-ascii 256,
    description: string-ascii 1024,
    domain: uint,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    executed: bool,
    passed: bool
}
```

### Delegations Map
```clarity
{
    delegate: principal,
    delegated-at: uint,
    active: bool
}
```

### Member Reputation
```clarity
{
    score: uint,
    last-updated: uint
}
```

## Error Codes

- `u100`: Owner-only function
- `u101`: Not found
- `u102`: Unauthorized
- `u103`: Already voted
- `u104`: Proposal closed
- `u105`: Invalid delegation
- `u106`: Circular delegation detected
- `u107`: Invalid expertise domain
- `u108`: Invalid power value
- `u109`: Voting period too short
- `u110`: Voting period not ended
- `u111`: Already executed

## Deployment Steps

1. Deploy the main contract: `singular-system.clar`
2. Register initial members with base voting power
3. Set up reputation scores for domain experts
4. Create first proposal to test the system

## Usage Example Flow

```clarity
;; 1. Register as a member
(contract-call? .singular-system register-member u100)

;; 2. Update reputation (owner only)
(contract-call? .singular-system update-reputation tx-sender u1 u75)

;; 3. Create a proposal
(contract-call? .singular-system create-proposal
    "Treasury Allocation"
    "Allocate 10% of treasury to development fund"
    u2
    u1440
)

;; 4. Vote on proposal
(contract-call? .singular-system vote u1 true)

;; 5. Or delegate your vote
(contract-call? .singular-system delegate-vote 'ST1EXPERT... u2)

;; 6. Finalize after voting period
(contract-call? .singular-system finalize-proposal u1)
```

## Security Considerations

1. **Direct Circular Delegation Protection**: Prevents A→B, B→A scenarios
2. **Double Voting Prevention**: Each member can only vote once per proposal
3. **Time-Based Validation**: Proposals have clear start/end blocks
4. **Owner Controls**: Critical functions like reputation updates restricted to owner

**Note**: For Clarity compatibility, circular delegation check is simplified to one level. For production use with complex delegation chains, consider implementing an off-chain validation service or upgrading to multi-level checks in a future version.

## Future Enhancements

This is a foundational implementation. Production versions should add:

1. **Conviction Voting**: Time-weighted voting with quadratic multipliers
2. **Oracle Integration**: Automated reputation updates from on-chain activity
3. **Milestone Tracking**: Break proposals into deliverables
4. **Treasury Management**: Direct fund allocation upon proposal passage
5. **Time Decay**: Automatic delegation expiration
6. **Quorum Requirements**: Minimum participation thresholds

## Testing

Use the provided test suite (`singular-system-tests.clar`) to verify core functionality:

```clarity
(contract-call? .singular-system-tests test-member-registration)
(contract-call? .singular-system-tests test-create-proposal)
(contract-call? .singular-system-tests test-delegation)
(contract-call? .singular-system-tests test-voting)
(contract-call? .singular-system-tests test-read-functions)
```

## License

This contract is provided as-is for educational and development purposes.
