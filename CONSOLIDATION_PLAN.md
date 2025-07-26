# Repository Consolidation Plan

## Current Situation

We have **TWO** GitHub repositories:
1. **https://github.com/ebowwa/RV1106-RTL8723D-HFP** (current)
2. **https://github.com/ebowwa/RTL8723D-Fix** (earlier attempt)

This is confusing and splits the work. We should consolidate into ONE.

## Consolidation Steps

### Option 1: Merge RTL8723D-Fix into RV1106-RTL8723D-HFP (Recommended)
```bash
# 1. Add the other repo as remote
git remote add rtl8723d-fix https://github.com/ebowwa/RTL8723D-Fix.git

# 2. Fetch its content
git fetch rtl8723d-fix

# 3. Merge relevant content
git checkout -b consolidation
git checkout rtl8723d-fix/main -- README.md  # Get their README
git mv README.md RTL8723D-Fix-README.md     # Rename to avoid conflict

# 4. Copy any unique files
git checkout rtl8723d-fix/main -- <other-important-files>

# 5. Commit consolidation
git add .
git commit -m "Consolidate RTL8723D-Fix repo content"

# 6. Merge to main
git checkout main
git merge consolidation

# 7. Push
git push origin main

# 8. Archive the old repo on GitHub
# Go to Settings → General → Archive this repository
```

### Option 2: Start Fresh with Clean Structure
```
RV1106-Bluetooth-HFP-Solution/
├── README.md                      # Main documentation
├── PROJECT_STATUS.md             # Current status
├── SOLUTION_GUIDE.md            # Step-by-step solutions
│
├── hardware/
│   ├── RV1106-specs.md
│   ├── RTL8723D-datasheet.pdf
│   └── wiring-diagram.md
│
├── firmware/
│   ├── rtk_hciattach/           # Our compiled tool
│   └── rtlbt/                   # Firmware files
│
├── bluefusion-extension/        # Classic BT support
│   ├── src/
│   └── README.md
│
├── scripts/
│   ├── initialization/          # Device init scripts
│   ├── testing/                 # Test scripts
│   └── deployment/             # ADB push scripts
│
├── builds/
│   ├── codespaces/             # GitHub Codespaces builds
│   ├── ofono/                  # oFono build files
│   └── cross-compile/          # Cross-compilation guides
│
├── solutions/
│   ├── bluealsa-workaround.md  # Quick fix
│   ├── ofono-integration.md    # Proper fix
│   └── pipewire-modern.md      # Future approach
│
└── docs/
    ├── original-issue.pdf       # The PDF that started it
    ├── raspberry-pi-test.md     # Saturday's plan
    └── hats-button-fix.md       # Sunday's plan
```

## Immediate Actions

1. **Backup Everything**
```bash
# Create complete backup
tar -czf ~/RV1106-PROJECT-BACKUP-$(date +%Y%m%d).tar.gz .
```

2. **Document What's In Each Repo**
```bash
# Check RTL8723D-Fix content
curl -s https://api.github.com/repos/ebowwa/RTL8723D-Fix/contents | jq -r '.[].name'
```

3. **Create Master README**
Combining all findings, solutions, and next steps

## Repository Decision

**Recommendation**: Keep `RV1106-RTL8723D-HFP` as the main repo because:
- It has more complete history
- Better naming (includes hardware model)
- Already has the builds and scripts

Then:
1. Import any unique content from RTL8723D-Fix
2. Archive RTL8723D-Fix with a note pointing to the main repo
3. Update all documentation to reference only the main repo

## For Tomorrow (Raspberry Pi)

Create a new branch:
```bash
git checkout -b raspberry-pi-testing
# Document all Pi-specific findings here
```

## For Sunday (HATs Button)

Create another branch:
```bash
git checkout -b hats-button-integration
# GPIO control and button mapping
```

This keeps everything organized in ONE place!