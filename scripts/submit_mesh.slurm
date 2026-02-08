#!/bin/bash
#SBATCH --job-name=BeamClean_Mesh
#SBATCH --output=logs/mesh_%j.out
#SBATCH --error=logs/mesh_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32GB
#SBATCH --time=04:00:00
#SBATCH --partition=standard

# ==============================================================================
# SLURM Job Script for OpenFOAM Mesh Generation
# BeamCleaning Simulation - DUNE Beam Cleaning
# ==============================================================================

echo "=========================================="
echo "Job: $SLURM_JOB_NAME"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "CPUs: $SLURM_CPUS_PER_TASK"
echo "Memory: $SLURM_MEM_PER_NODE MB"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# Load OpenFOAM module (adjust for your HPC system)
# Common module names - uncomment the one that works for your system:
# module load openfoam/13
# module load openfoam/v2312
# module load OpenFOAM/13-foss-2023a
# Or source directly:
# source /opt/openfoam13/etc/bashrc

# REPLACE THIS LINE WITH YOUR HPC'S OPENFOAM LOADING COMMAND:
module load openfoam/13

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
echo "Total runtime: $SECONDS seconds"
