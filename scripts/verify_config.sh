#!/bin/bash
# Quick verification script to check configuration before HPC submission
# Can be run from anywhere - will automatically navigate to case directory

# Navigate to case root (one level up from scripts/)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$CASE_DIR" || exit 1

echo "=========================================="
echo "BeamCleaning Configuration Verification"
echo "=========================================="
echo "Case directory: $CASE_DIR"
echo ""

ERRORS=0
WARNINGS=0

# Check if required files exist
echo "Checking required files..."
FILES=(
    "system/snappyHexMeshDict"
    "system/surfaceFeaturesDict"
    "system/blockMeshDict"
    "system/controlDict"
    "system/fvSchemes"
    "system/fvSolution"
    "constant/triSurface/enclosure.stl"
    "constant/triSurface/beam_walls.stl"
    "constant/triSurface/beam_holes.stl"
    "constant/triSurface/nozzle.stl"
    "0/p"
    "0/U"
    "0/T"
    "0/k"
    "0/epsilon"
    "0/nut"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ MISSING: $file"
        ((ERRORS++))
    fi
done
echo ""

# Check if enclosure is in snappyHexMeshDict
echo "Checking enclosure configuration..."
if grep -q "enclosure" system/snappyHexMeshDict; then
    echo "  ✓ Enclosure found in snappyHexMeshDict"
else
    echo "  ✗ Enclosure NOT found in snappyHexMeshDict"
    ((ERRORS++))
fi

if grep -q "enclosure.stl" system/surfaceFeaturesDict; then
    echo "  ✓ Enclosure found in surfaceFeaturesDict"
else
    echo "  ✗ Enclosure NOT found in surfaceFeaturesDict"
    ((ERRORS++))
fi
echo ""

# Check boundary conditions include enclosure
echo "Checking boundary conditions..."
BC_FILES=("0/p" "0/U" "0/T" "0/k" "0/epsilon" "0/nut")
for file in "${BC_FILES[@]}"; do
    if grep -q "enclosure" "$file"; then
        echo "  ✓ $file includes enclosure BC"
    else
        echo "  ✗ $file MISSING enclosure BC"
        ((ERRORS++))
    fi
done
echo ""

# Check if scripts are executable
echo "Checking executable scripts..."
SCRIPTS=("scripts/Allrun.mesh" "scripts/Allrun.solver" "scripts/submit_mesh.slurm" "scripts/submit_solver.slurm")
for script in "${SCRIPTS[@]}"; do
    if [ -x "$script" ]; then
        echo "  ✓ $script is executable"
    else
        echo "  ⚠ $script is NOT executable (run: chmod +x $script)"
        ((WARNINGS++))
    fi
done
echo ""

# Check logs directory
echo "Checking logs directory..."
if [ -d "logs" ]; then
    echo "  ✓ logs/ directory exists"
else
    echo "  ⚠ logs/ directory missing (will be created automatically)"
    ((WARNINGS++))
fi
echo ""

# Check STL file sizes (should not be zero)
echo "Checking STL file sizes..."
STLS=(
    "constant/triSurface/enclosure.stl"
    "constant/triSurface/beam_walls.stl"
    "constant/triSurface/beam_holes.stl"
    "constant/triSurface/nozzle.stl"
)
for stl in "${STLS[@]}"; do
    if [ -f "$stl" ]; then
        SIZE=$(stat -f%z "$stl" 2>/dev/null || stat -c%s "$stl" 2>/dev/null)
        if [ "$SIZE" -gt 0 ]; then
            echo "  ✓ $stl ($SIZE bytes)"
        else
            echo "  ✗ $stl is EMPTY"
            ((ERRORS++))
        fi
    fi
done
echo ""

# Summary
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✓ Configuration looks good!"
    if [ $WARNINGS -gt 0 ]; then
        echo "⚠ $WARNINGS warning(s) - check above"
    fi
    echo ""
    echo "Ready for HPC submission!"
    echo ""
    echo "Next steps:"
    echo "1. Edit scripts/submit_mesh.slurm with your HPC's OpenFOAM module command"
    echo "2. Edit scripts/submit_solver.slurm with your HPC's OpenFOAM module command"
    echo "3. Submit: sbatch scripts/submit_mesh.slurm"
else
    echo "✗ Found $ERRORS error(s)"
    if [ $WARNINGS -gt 0 ]; then
        echo "⚠ Found $WARNINGS warning(s)"
    fi
    echo ""
    echo "Fix errors before running!"
fi
echo "=========================================="
