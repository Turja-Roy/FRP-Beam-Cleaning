# Automated Workflow Quick Reference

## Overview
The automated workflow system manages the complete OpenFOAM beam cleaning simulation from mesh generation through solver execution using SLURM job dependencies.

## Key Features
- **Automatic dependency chain**: Solver starts only after mesh completes successfully
- **Error handling**: Solver auto-cancels if mesh fails
- **Pre-flight checks**: Validates configuration before submission
- **Comprehensive logging**: Timestamped logs for debugging
- **Flexible modes**: Full workflow, mesh-only, or solver-only

---

## Quick Start

### Full Workflow (Mesh → Solver)
```bash
cd /path/to/BeamCleaning
scripts/submit_workflow.sh
```

This submits both jobs with automatic dependency. Solver waits for mesh to complete.

### Check Configuration (No Submission)
```bash
scripts/submit_workflow.sh --check-only
```

### Mesh Only
```bash
scripts/submit_workflow.sh --mesh-only
```

### Solver Only (if mesh exists)
```bash
scripts/submit_workflow.sh --solver-only
```

---

## Monitoring Commands

### Check Job Queue
```bash
scripts/monitor_jobs.sh status    # or just: squeue -u $USER
```

### Watch Logs in Real-Time
```bash
scripts/monitor_jobs.sh mesh-log     # Watch mesh generation
scripts/monitor_jobs.sh solver-log   # Watch solver
```

### Check Status
```bash
scripts/monitor_jobs.sh mesh-status    # Mesh quality/existence
scripts/monitor_jobs.sh solver-status  # Convergence/residuals
scripts/monitor_jobs.sh logs           # List recent logs
```

---

## Job Management

### Cancel Jobs
```bash
scancel <job_id>                    # Cancel specific job
scancel <mesh_id> <solver_id>       # Cancel both
scancel -u $USER                    # Cancel all your jobs
```

### Check Specific Job
```bash
scontrol show job <job_id>          # Detailed job info
sacct -j <job_id> --format=JobID,JobName,State,ExitCode,Elapsed
```

---

## Workflow Details

### Job Configuration
| Stage | Cores | Memory | Time | Expected Runtime |
|-------|-------|--------|------|-----------------|
| Mesh  | 12    | 36GB   | 1h   | 15-25 minutes   |
| Solver| 48    | 144GB  | 8h   | 6-8 hours       |

### Dependency Behavior
- **Mesh completes successfully (exit 0)** → Solver starts automatically
- **Mesh fails (exit ≠ 0)** → Solver is auto-cancelled
- **Mesh cancelled** → Solver is auto-cancelled

### Log Files
```
logs/
├── mesh_<jobid>.out          # Mesh generation output
├── solver_<jobid>.out        # Solver output  
└── workflow_<timestamp>.log  # Submission log
```

---

## Common Scenarios

### First Time Running
```bash
# 1. Check configuration
scripts/submit_workflow.sh --check-only

# 2. Submit full workflow
scripts/submit_workflow.sh

# 3. Monitor
squeue -u $USER
scripts/monitor_jobs.sh mesh-log
```

### Re-run Solver Only (mesh exists)
```bash
scripts/submit_workflow.sh --solver-only
```

### Mesh Failed, Need to Re-run
```bash
# Check what went wrong
scripts/monitor_jobs.sh mesh-status
less logs/mesh_<jobid>.out

# Fix issue, then re-submit full workflow
scripts/submit_workflow.sh
```

### Cancel Everything and Start Over
```bash
scancel -u $USER                      # Cancel all jobs
rm -rf constant/polyMesh processor*   # Clean mesh
scripts/submit_workflow.sh            # Restart
```

---

## Troubleshooting

### "Mesh job failed" - What to check?
1. Check log: `less logs/mesh_<jobid>.out`
2. Look for errors in: snappyHexMesh, decomposePar, checkMesh
3. Common issues:
   - STL files missing/corrupt
   - decomposeParDict.mesh wrong core count
   - Memory exhaustion
   - Time limit exceeded

### "Solver depends on failed job"
The solver was auto-cancelled because mesh failed. Fix mesh, then re-submit full workflow.

### "Job stuck in pending (PD) state"
Check reason: `squeue -u $USER -o "%.18i %.12j %.8T %.10r"`
- `Resources`: Waiting for available nodes (normal)
- `Dependency`: Waiting for mesh job (normal)
- `Priority`: Lower priority, will run eventually

### "Out of memory (OOM)"
Increase memory in submit scripts:
```bash
# Edit scripts/submit_mesh.slurm or submit_solver.slurm
#SBATCH --mem=48G    # Increase from 36G
```

### "Time limit exceeded"
Increase time limit in submit scripts:
```bash
#SBATCH -t 02:00:00  # Increase from 01:00:00
```

---

## Advanced Usage

### Submit with Custom Parameters
Directly edit SLURM scripts before submission:
```bash
vi scripts/submit_mesh.slurm    # Modify cores/memory/time
vi scripts/submit_solver.slurm
scripts/submit_workflow.sh      # Submit with changes
```

### Chain Multiple Workflows
```bash
# Run workflow 1
FIRST=$(scripts/submit_workflow.sh | grep "Job ID" | tail -1 | awk '{print $NF}')

# Run workflow 2 after workflow 1 completes
sbatch --dependency=afterok:$FIRST scripts/submit_mesh.slurm
```

### Manual Dependency Setup
```bash
# Submit mesh
MESH_ID=$(sbatch scripts/submit_mesh.slurm | awk '{print $4}')

# Submit solver dependent on mesh
sbatch --dependency=afterok:$MESH_ID scripts/submit_solver.slurm
```

---

## File Structure

```
BeamCleaning/
├── scripts/
│   ├── submit_workflow.sh      ← Main automation script
│   ├── monitor_jobs.sh         ← Monitoring utilities
│   ├── submit_mesh.slurm       ← Mesh job config
│   ├── submit_solver.slurm     ← Solver job config
│   ├── Allrun.mesh             ← Mesh generation steps
│   └── Allrun.solver           ← Solver execution steps
├── system/
│   ├── decomposeParDict.mesh   ← 12 cores for mesh
│   └── decomposeParDict        ← 48 cores for solver
├── constant/
│   ├── triSurface/             ← STL geometry files
│   └── polyMesh/               ← Generated mesh (after mesh job)
└── logs/                       ← All output logs
```

---

## Performance Tips

1. **Monitor first run carefully** to validate expected runtimes
2. **Reduce time limits** after validating actual runtimes (saves queue time)
3. **Check parallel efficiency** in logs - should be >80%
4. **Archive old logs** regularly: `scripts/monitor_jobs.sh clean-logs`
5. **Scale up cautiously** - test with current settings before increasing cores

---

## Getting Help

```bash
scripts/submit_workflow.sh --help
scripts/monitor_jobs.sh --help
```

For SLURM documentation on TACC:
- https://docs.tacc.utexas.edu/hpc/lonestar6/

For OpenFOAM parallel running:
- https://www.openfoam.com/documentation/guides/latest/doc/guide-running-parallel.html
