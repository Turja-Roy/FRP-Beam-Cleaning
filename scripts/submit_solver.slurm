#!/bin/bash
#SBATCH --job-name=BeamClean_Solver
#SBATCH --output=logs/solver_%j.out
#SBATCH --error=logs/solver_%j.err
#SBATCH --ntasks=48
#SBATCH --cpus-per-task=1
#SBATCH --mem=144GB
#SBATCH --time=08:00:00
#SBATCH --partition=standard

# ==============================================================================
# OPTIMIZED CONFIGURATION (Feb 2026)
# - Increased MPI tasks: 16 -> 48 (optimal decomposition: ~35k cells/core)
# - Increased Memory: 64GB -> 144GB (3GB per core, safe for rhoSimpleFoam)
# - Reduced Time: 24h -> 8h (expected 3x speedup with better parallelization)
# - Mesh: ~1.7M cells optimally distributed across 48 processors
# ==============================================================================

# SLURM Job Script for OpenFOAM Solver (rhoSimpleFoam)
# BeamCleaning Simulation - DUNE Beam Cleaning
# ==============================================================================

echo "=========================================="
echo "PERFORMANCE METRICS"
echo "Job: $SLURM_JOB_NAME"
echo "Job ID: $SLURM_JOB_ID"
echo "Node(s): $SLURM_NODELIST"
echo "Tasks: $SLURM_NTASKS"
echo "CPUs per task: $SLURM_CPUS_PER_TASK"
echo "Memory: $SLURM_MEM_PER_NODE MB"
echo "Expected cells/core: ~35,400 (1.7M / 48)"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# Load OpenFOAM module
module load openfoam/13

echo "OpenFOAM version:"
which rhoSimpleFoam
echo ""

# Navigate to case directory
cd $SLURM_SUBMIT_DIR
echo "Working directory: $(pwd)"
echo ""

# Create logs directory with timestamp
LOGDIR="logs/solver_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOGDIR"
echo "Logs will be saved to: $LOGDIR"
echo ""

# Check if mesh exists
if [ ! -f "constant/polyMesh/boundary" ]; then
    echo "ERROR: Mesh not found! Run mesh generation first."
    exit 1
fi

# Decompose mesh for parallel run (if using multiple tasks)
if [ $SLURM_NTASKS -gt 1 ]; then
    echo "Decomposing mesh for $SLURM_NTASKS processors..."
    echo "NOTE: Using decomposeParDict (scotch method for optimal load balancing)"
    decomposePar > "$LOGDIR/log.decomposePar" 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ Mesh decomposed successfully"
    else
        echo "✗ Decomposition failed! Check $LOGDIR/log.decomposePar"
        exit 1
    fi
    echo ""
    
    # Run solver in parallel
    echo "Running rhoSimpleFoam in parallel..."
    mpirun -np $SLURM_NTASKS rhoSimpleFoam -parallel > "$LOGDIR/log.rhoSimpleFoam" 2>&1
    
    # Reconstruct the solution
    echo "Reconstructing solution..."
    reconstructPar > "$LOGDIR/log.reconstructPar" 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ Solution reconstructed"
    else
        echo "⚠ Reconstruction had issues - check $LOGDIR/log.reconstructPar"
    fi
else
    # Run solver in serial
    echo "Running rhoSimpleFoam in serial..."
    rhoSimpleFoam > "$LOGDIR/log.rhoSimpleFoam" 2>&1
fi

# Check convergence
if [ -f "$LOGDIR/log.rhoSimpleFoam" ]; then
    echo ""
    echo "=========================================="
    echo "Solver completed!"
    echo "=========================================="
    echo ""
    echo "Final residuals:"
    grep "Solving for" "$LOGDIR/log.rhoSimpleFoam" | tail -10
    echo ""
    
    # Save final statistics
    ls -d [0-9]* | tail -1 > "$LOGDIR/final_time.txt"
    echo "Final time step: $(cat $LOGDIR/final_time.txt)"
else
    echo "ERROR: Solver log not found!"
    exit 1
fi

echo ""
echo "Job finished at: $(date)"
echo "Total runtime: $SECONDS seconds ($(($SECONDS / 3600))h $(($SECONDS % 3600 / 60))m)"
echo ""
echo "=========================================="
echo "PERFORMANCE SUMMARY"
echo "=========================================="
echo "Cores used: $SLURM_NTASKS"
echo "Runtime: $SECONDS seconds"
if [ $SLURM_NTASKS -gt 1 ]; then
    echo "Parallel efficiency: Check MPI communication time in logs"
    echo "Target: <10% communication overhead for good scaling"
fi
echo ""
echo "To visualize results:"
echo "  paraFoam"
echo "Or copy results and run locally"
