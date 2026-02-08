# BeamCleaning HPC Guide

Complete guide for running the DUNE Beam Cleaning CFD simulation on HPC.

---

## Quick Start

### Before Transfer
```bash
# 1. Clean old files
scripts/Allclean

# 2. Verify configuration
scripts/verify_config.sh

# 3. Edit SLURM scripts with YOUR HPC's OpenFOAM module command
#    Edit line 35 in scripts/submit_mesh.slurm
#    Edit line 27 in scripts/submit_solver.slurm
#    Replace: module load openfoam/13
#    With: module load openfoam/v2312  (or your HPC's command)
```

### Transfer to HPC
```bash
rsync -avz --progress BeamCleaning/ username@hpc.edu:~/BeamCleaning/
```

### On HPC
```bash
cd ~/BeamCleaning
sbatch scripts/submit_mesh.slurm     # 3-5 hours, generates ~6-7M cell mesh
squeue -u $USER                      # Check status
tail -f logs/mesh_*.out              # Monitor progress

# After mesh completes:
cat constant/polyMesh/boundary | grep enclosure  # Verify enclosure exists
sbatch scripts/submit_solver.slurm  # 12-24 hours, runs simulation
```

---

## Configuration Details

### Simulation Parameters
| Parameter | Value | Notes |
|-----------|-------|-------|
| **Solver** | rhoSimpleFoam | Compressible, steady-state RANS |
| **Turbulence** | k-epsilon | 5% inlet turbulence intensity |
| **Inlet** | 70 psi (4.83 bar) (482.6 kPa) at nozzleInlet | 300K temperature |
| **Outlets** | 1 atm (101.325 kPa) | beamHoles, enclosure, openings |
| **Mesh** | ~6-7M cells | Level 5-6 refinement on holes/nozzle |
| **Geometry** | 3240mm beam, 500×4240×500mm domain | STL scaled mm→m |

### SLURM Resource Requests
**Mesh Job** (scripts/submit_mesh.slurm):
- Time: 4 hours
- Memory: 32 GB
- CPUs: 8 (single task)
- Partition: standard

**Solver Job** (scripts/submit_solver.slurm):
- Time: 24 hours
- Memory: 64 GB  
- Tasks: 16 (parallel MPI)
- Partition: standard

**Adjust these** based on your HPC's resources after first run.

### Key Files
```
BeamCleaning/
├── 0/                      # Boundary conditions (p, U, T, k, epsilon, nut)
├── constant/
│   └── triSurface/        # STL geometries (all scaled 0.001 in config)
├── system/
│   ├── blockMeshDict      # Background: 100×170×100 cells
│   ├── snappyHexMeshDict  # Refinement levels, enclosure scale
│   ├── controlDict        # 1000 iterations, residuals < 1e-5
│   ├── fvSchemes          # Numerical schemes
│   └── fvSolution         # Relaxation factors, solvers
└── scripts/               # All executables
```

---

## Finding Your HPC's OpenFOAM Module

SSH to your HPC and run:
```bash
module avail openfoam     # List available OpenFOAM modules
module avail OpenFOAM     # Try uppercase too
```

Common module names:
- `module load openfoam/13`
- `module load openfoam/v2312`
- `module load OpenFOAM/13-foss-2023a`
- `source /opt/openfoam13/etc/bashrc`

Use the **exact name** shown in your HPC's module list.

---

## Monitoring Jobs

### Check Job Status
```bash
squeue -u $USER              # Your jobs
sinfo                        # Available partitions and nodes
sacct -j JOBID --format=JobID,JobName,State,ExitCode  # Job details
```

### View Logs
```bash
# SLURM logs
tail -f logs/mesh_12345.out      # Replace 12345 with your job ID
tail -f logs/mesh_12345.err

# OpenFOAM logs (after job starts)
tail -f logs/mesh_*/log.snappyHexMesh
tail -f logs/solver_*/log.rhoSimpleFoam
```

### Check Progress
```bash
# Mesh job - watch cell count increase
grep "cells:" logs/mesh_*/log.snappyHexMesh

# Solver job - watch residuals decrease
grep "Solving for" logs/solver_*/log.rhoSimpleFoam | tail -20
```

---

## Verification

### After Mesh Generation
```bash
# Check mesh was created
ls -lh constant/polyMesh/

# Verify all patches exist (should see 7 including enclosure)
cat constant/polyMesh/boundary

# Check mesh statistics
cat logs/mesh_*/mesh_stats.txt

# Expected output:
#   cells: 6-7 million
#   beamHoles faces: ~18,000
#   enclosure faces: ~thousands (NEW!)
```

### After Solver Completes
```bash
# Check final residuals
grep "Solving for" logs/solver_*/log.rhoSimpleFoam | tail -10

# List solution time steps
ls -d [0-9]*

# Check convergence
grep "solution converged" logs/solver_*/log.rhoSimpleFoam
```

---

## Troubleshooting

### Mesh Job Fails

**Module not found:**
```bash
# On HPC, test module loading
module load openfoam/13   # Use your actual module name
which blockMesh            # Should show path if loaded correctly
```
Fix: Edit scripts/submit_mesh.slurm line 35 with correct module command

**Out of memory:**
```bash
# Check actual memory usage in SLURM output
grep "memory" logs/mesh_*.err
```
Fix: Increase `--mem=32GB` in scripts/submit_mesh.slurm line 7

**Timeout:**
```bash
# Check if job was killed due to time limit
sacct -j JOBID --format=JobID,State,ExitCode
```
Fix: Increase `--time=04:00:00` in scripts/submit_mesh.slurm line 8

**Enclosure patch missing:**
```bash
# Check snappyHexMesh log for errors
grep -i "enclosure" logs/mesh_*/log.snappyHexMesh
grep -i "error\|warning" logs/mesh_*/log.snappyHexMesh
```
Fix: Verify enclosure.stl exists and snappyHexMeshDict has `scale 0.001;`

### Solver Job Fails

**Decomposition fails:**
```bash
# Check decomposePar log
cat logs/solver_*/log.decomposePar
```
Fix: Verify mesh exists before solver job, check numberOfSubdomains in system/decomposeParDict

**Solver diverges:**
```bash
# Watch residuals increase instead of decrease
tail -100 logs/solver_*/log.rhoSimpleFoam | grep residual
```
Fixes:
1. Reduce relaxation factors in system/fvSolution (try p=0.2, U=0.5)
2. Check mesh quality: `checkMesh` - look for high non-orthogonality
3. Use more stable schemes in system/fvSchemes (e.g., upwind)

**Solution doesn't converge:**
```bash
# Check if residuals plateau above target
grep "residual" logs/solver_*/log.rhoSimpleFoam | tail -50
```
Fixes:
1. Increase iterations in system/controlDict (endTime)
2. Tighten tolerances in system/fvSolution
3. Check boundary conditions are physically realistic

### Job Won't Submit

**Partition doesn't exist:**
```bash
sinfo  # List available partitions
```
Fix: Edit `--partition=standard` in both SLURM scripts (line 9)

**Not enough resources:**
```bash
sinfo  # Check available nodes
squeue  # Check queue load
```
Fix: Reduce resource requests or wait for availability

---

## Downloading Results

### From HPC to Local
```bash
# Download specific time directories
rsync -avz hpc:~/BeamCleaning/[1-9]* .

# Download logs
rsync -avz hpc:~/BeamCleaning/logs/ ./logs/

# Download everything (warning: large!)
rsync -avz hpc:~/BeamCleaning/ .
```

### Visualize Locally
```bash
# On your local machine with OpenFOAM installed
paraFoam

# Or create .foam file for ParaView without OpenFOAM
touch case.foam
# Then open case.foam in ParaView
```

---

## Expected Results

### Mesh Statistics
- **Total cells:** 6-7 million
- **Total faces:** ~18-20 million
- **beamHoles faces:** ~18,000 (excellent refinement!)
- **enclosure faces:** ~thousands (new atmospheric boundary)
- **Mesh quality:** Max non-orthogonality < 70°, no negative volumes
- **Generation time:** 3-5 hours on 8 CPUs

### Solver Convergence
- **Typical iterations:** 200-500 (up to 1000 max)
- **Residuals:** p < 1e-5, U < 1e-6, T < 1e-6
- **Runtime:** 12-24 hours on 16 cores
- **Output:** Pressure, velocity, temperature fields every 100 iterations

### Physical Results
- **Velocity at holes:** High speed jets (100-200 m/s expected)
- **Pressure drop:** From 70 psi (4.83 bar) to 1 atm
- **Flow pattern:** Nozzle → beam → holes → enclosure
- **Temperature:** Should remain near 300K (minimal compression heating)

---

## Post-Processing

### Calculate Forces
```bash
postProcess -func forces
postProcess -func forceCoeffs
```

### Extract Field Values
```bash
# Sample along a line
postProcess -func 'sample(line)'

# Average over surfaces
postProcess -func 'patchAverage(patch=beamHoles,fields=(p U))'

# Volume average
postProcess -func 'volAverage(region=enclosure,fields=(p T))'
```

### Export Data
```bash
# Convert to VTK for external tools
foamToVTK

# Extract specific fields
foamListTimes  # List available times
sample -latestTime  # Sample at final time
```

---

## Known Issues

### 1. Geometry Has 32 Holes Instead of 54
- **Status:** Non-blocking for enclosure validation
- **Impact:** Simulation runs but doesn't match final design
- **Action:** After verifying enclosure works, regenerate beam_holes.stl with 54 holes at 60mm spacing
- **Workaround:** Current results still useful for testing workflow

### 2. Enclosure Configuration Untested  
- **Status:** Configuration complete but never meshed with enclosure
- **Risk:** Low - enclosure.stl is simple box, properly scaled
- **Validation:** First mesh job will confirm enclosure works
- **Mitigation:** Job fails early (~30 min) if enclosure has issues

---

## Advanced: Local Testing (if you have 32GB+ RAM)

```bash
# Test mesh generation locally (WARNING: resource intensive)
scripts/Allrun.mesh

# Test single solver iteration
rhoSimpleFoam -writeNow

# Test with fewer cells (for debugging)
# Edit system/blockMeshDict: reduce cells to (50 85 50)
# Edit system/snappyHexMeshDict: reduce refinement levels by 1-2
```

---

## Getting Help

1. **Verify configuration:** `scripts/verify_config.sh`
2. **Check logs:** Always check logs/ directory first
3. **Test module loading:** SSH to HPC and test `module load openfoam/13`
4. **HPC support:** Contact your HPC support if module/partition issues persist
5. **OpenFOAM errors:** Check OpenFOAM documentation at www.openfoam.com

---

## Command Reference

```bash
# Cleanup
scripts/Allclean

# Verification  
scripts/verify_config.sh

# HPC submission
sbatch scripts/submit_mesh.slurm
sbatch scripts/submit_solver.slurm

# Monitoring
squeue -u $USER
tail -f logs/mesh_*.out
tail -f logs/solver_*.out

# Cancel jobs
scancel JOBID
scancel -u $USER  # Cancel all your jobs

# Check results
cat constant/polyMesh/boundary
ls -d [0-9]*
paraFoam
```

---

**Last Updated:** February 2026  
**OpenFOAM Version:** 13 / v2312  
**Mesh Size:** ~6-7M cells  
**Status:** Ready for HPC transfer
