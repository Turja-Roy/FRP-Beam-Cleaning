#!/bin/bash
#SBATCH -J BeamClean_Mesh          # Job name
#SBATCH -o logs/mesh_%j.out        # Output file
#SBATCH -e logs/mesh_%j.err        # Error file
#SBATCH -p normal                  # Partition (normal for Lonestar6)
#SBATCH -N 1                       # Number of nodes
#SBATCH -n 12                      # Number of tasks (cores)
#SBATCH -t 01:00:00                # Time limit (1 hour - safe for parallel snappyHexMesh)
#SBATCH --mem=36                   # Memory per node in GB
#SBATCH --mail-type=END,FAIL       # Email notifications
#SBATCH --mail-user=turja.roy@uta.edu  # Email address

# ==============================================================================
# Lonestar6 (TACC) Optimized Configuration - Feb 2026
# - Cores: 12 (PARALLEL snappyHexMesh using MPI decomposition)
# - Memory: 36GB (3GB per core)
# - Time: 1 hour (parallel snappyHexMesh: ~10-20 min, padding for safety)
# - Partition: 'normal' (change to 'development' for quick testing, max 2h)
# - Email: Notifications on END and FAIL
# ==============================================================================

# SLURM Job Script for OpenFOAM Mesh Generation
# BeamCleaning Simulation - DUNE Beam Cleaning
# ==============================================================================

echo "=========================================="
echo "Lonestar6 Performance Metrics"
echo "Job: $SLURM_JOB_NAME"
echo "Job ID: $SLURM_JOB_ID"
echo "Node(s): $SLURM_NODELIST"
echo "Cores: $SLURM_NPROCS"
echo "Memory: ${SLURM_MEM_PER_NODE}GB"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# Load OpenFOAM 12 modules (Lonestar6 at TACC)
module load intel/24.1
module load impi/21.12
module load openfoam/12

echo "OpenFOAM version:"
which blockMesh
echo ""

# Navigate to case directory
cd $SLURM_SUBMIT_DIR
echo "Working directory: $(pwd)"
echo ""

# Create logs directory
mkdir -p logs

# Run mesh generation
echo "Starting mesh generation..."
scripts/Allrun.mesh

# Check if mesh was generated successfully
if [ -f "constant/polyMesh/boundary" ]; then
    echo ""
    echo "=========================================="
    echo "Mesh generation SUCCESSFUL!"
    echo "=========================================="
    echo ""
    echo "Boundary patches created:"
    cat constant/polyMesh/boundary | grep -E "^\s+[a-zA-Z]" | grep -v "type\|nFaces\|startFace\|inGroups\|List"
    echo ""
    echo "Mesh statistics:"
    LOGDIR=$(ls -td logs/mesh_* | head -1)
    cat "$LOGDIR/mesh_stats.txt"
else
    echo ""
    echo "=========================================="
    echo "Mesh generation FAILED!"
    echo "=========================================="
    echo "Check log files in logs/ directory"
    exit 1
fi

echo ""
echo "Job finished at: $(date)"
echo "Total runtime: $SECONDS seconds ($(($SECONDS / 60)) minutes)"
echo ""
echo "=========================================="
echo "PERFORMANCE SUMMARY"
echo "=========================================="
echo "Cores used: $SLURM_NPROCS"
echo "Memory allocated: ${SLURM_MEM_PER_NODE}GB"
echo "Runtime: $SECONDS seconds"
echo "=========================================="
