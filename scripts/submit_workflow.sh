#!/bin/bash
# Simple workflow: submit mesh, then solver with dependency

cd "$(dirname "$0")/.." || exit 1

echo "Submitting workflow..."
echo ""

# Submit mesh job
echo "Submitting mesh job..."
MESH_JOB=$(sbatch scripts/submit_mesh.slurm | grep -oP '\d+$')

if [ -z "$MESH_JOB" ]; then
	echo "ERROR: Failed to submit mesh job"
	exit 1
fi

echo "✓ Mesh job submitted: $MESH_JOB"
echo ""

# Submit solver job with dependency
echo "Submitting solver job (depends on mesh)..."
SOLVER_JOB=$(sbatch --dependency=afterok:$MESH_JOB scripts/submit_solver.slurm | grep -oP '\d+$')

if [ -z "$SOLVER_JOB" ]; then
	echo "ERROR: Failed to submit solver job"
	echo "  Mesh job $MESH_JOB is still queued/running"
	exit 1
fi

echo "✓ Solver job submitted: $SOLVER_JOB"
echo ""

echo "=========================================="
echo "Jobs submitted successfully!"
echo "=========================================="
echo ""
echo "Mesh job:   $MESH_JOB (12 cores, ~20 min)"
echo "Solver job: $SOLVER_JOB (48 cores, ~6 hours)"
echo ""
echo "Solver will start after mesh completes"
echo ""
echo "Monitor: squeue -u \$USER"
echo "Logs:    logs/mesh_${MESH_JOB}.out"
echo "         logs/solver_${SOLVER_JOB}.out"
echo ""
