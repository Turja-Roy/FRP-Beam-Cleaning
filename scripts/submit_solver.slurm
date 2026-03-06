#!/bin/bash
#SBATCH -J BeamClean_Solver        # Job name
#SBATCH -o logs/solver_%j.out      # Output file
#SBATCH -e logs/solver_%j.err      # Error file
#SBATCH -p normal                  # Partition (normal for Lonestar6)
#SBATCH -N 1                       # Number of nodes
#SBATCH -n 12                      # Number of tasks (cores)
#SBATCH -t 24:00:00                # Time limit (24 hours)
#SBATCH --mem=48                   # Memory per node in GB
#SBATCH --mail-type=END,FAIL       # Email notifications
#SBATCH --mail-user=turja.roy@uta.edu  # Email address

# ==============================================================================
# Lonestar6 (TACC) Configuration - 12 Core Setup
# - Nodes: 1 (single node for low-latency MPI communication)
# - Cores: 12 (mesh already decomposed for 12 processors)
# - Memory: 48GB (4GB per core)
# - Time: 24 hours (sufficient for 1.7M cell mesh on 12 cores)
# - Partition: 'normal'
# - Email: Notifications on END and FAIL
#
# NOTE: This uses the existing 12-way mesh decomposition from mesh generation
#       Each core handles ~142k cells (1.7M / 12)
# ==============================================================================

# SLURM Job Script for OpenFOAM Solver (rhoSimpleFoam)
# BeamCleaning Simulation - DUNE Beam Cleaning
# ==============================================================================

echo "=========================================="
echo "Lonestar6 Performance Metrics"
echo "Job: $SLURM_JOB_NAME"
echo "Job ID: $SLURM_JOB_ID"
echo "Node(s): $SLURM_NODELIST"
echo "Tasks: $SLURM_NTASKS"
echo "Memory: ${SLURM_MEM_PER_NODE}GB"
echo "Expected cells/core: ~142,000 (1.7M / 12)"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# Load OpenFOAM 12 modules (Lonestar6 at TACC)
module load intel/24.1
module load impi/21.12
module load openfoam/12

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
    # Check if mesh is already decomposed
    PROC_DIRS=$(find . -maxdepth 1 -type d -name "processor*" | wc -l)
    
    if [ $PROC_DIRS -eq $SLURM_NTASKS ]; then
        echo "Mesh already decomposed for $SLURM_NTASKS processors (found $PROC_DIRS processor directories)"
        echo "✓ Using existing decomposition"
    else
        echo "Decomposing mesh for $SLURM_NTASKS processors..."
        echo "NOTE: Using decomposeParDict (scotch method for optimal load balancing)"
        
        # Clean old processor directories if count mismatch
        if [ $PROC_DIRS -gt 0 ]; then
            echo "Removing old processor directories (found $PROC_DIRS, need $SLURM_NTASKS)..."
            rm -rf processor*
        fi
        
        decomposePar > "$LOGDIR/log.decomposePar" 2>&1
        if [ $? -eq 0 ]; then
            echo "✓ Mesh decomposed successfully"
        else
            echo "✗ Decomposition failed! Check $LOGDIR/log.decomposePar"
            exit 1
        fi
    fi
    echo ""
    
    # Run solver in parallel using ibrun (TACC's MPI launcher)
    echo "Running rhoSimpleFoam in parallel..."
    ibrun rhoSimpleFoam -parallel > "$LOGDIR/log.rhoSimpleFoam" 2>&1
    
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
    # Check if solver actually ran (look for fatal errors)
    if grep -q "FOAM FATAL ERROR" "$LOGDIR/log.rhoSimpleFoam"; then
        echo ""
        echo "=========================================="
        echo "Solver FAILED!"
        echo "=========================================="
        echo ""
        echo "Error found in log:"
        grep -A5 "FOAM FATAL ERROR" "$LOGDIR/log.rhoSimpleFoam"
        echo ""
        echo "Check full log: $LOGDIR/log.rhoSimpleFoam"
        exit 1
    fi
    
    echo ""
    echo "=========================================="
    echo "Solver completed!"
    echo "=========================================="
    echo ""
    echo "Final residuals:"
    grep "Solving for" "$LOGDIR/log.rhoSimpleFoam" | tail -10
    echo ""
    
    # Save final statistics
    FINAL_TIME=$(ls -d [0-9]* 2>/dev/null | tail -1)
    if [ -n "$FINAL_TIME" ]; then
        echo "$FINAL_TIME" > "$LOGDIR/final_time.txt"
        echo "Final time step: $FINAL_TIME"
    else
        echo "WARNING: No solution time directories found!"
        echo "Solver may not have run any iterations."
    fi
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
