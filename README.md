# BeamCleaning - DUNE Beam Cleaning CFD Simulation

OpenFOAM 13 simulation of high-pressure air flow through a hollow beam with nozzle system.

## 📁 Directory Structure

```
BeamCleaning/
├── 0/                          # Boundary conditions
│   ├── p                       # Pressure (482.6 kPa inlet)
│   ├── U                       # Velocity
│   ├── T                       # Temperature (300K)
│   ├── k                       # Turbulent kinetic energy
│   ├── epsilon                 # Turbulent dissipation
│   └── nut                     # Turbulent viscosity
├── constant/
│   ├── triSurface/             # STL geometry files (scaled mm→m)
│   │   ├── enclosure.stl       # Atmospheric boundary
│   │   ├── beam_walls.stl      # Beam structure
│   │   ├── beam_holes.stl      # 32 holes (need 54)
│   │   ├── nozzle.stl          # Nozzle body
│   │   ├── nozzle_inlet.stl    # Nozzle inlet
│   │   └── beam_*_opening.stl  # Front/back openings
│   └── (polyMesh/)             # Generated mesh (not in repo)
├── system/                     # OpenFOAM configuration
│   ├── blockMeshDict           # Background mesh (100×170×100)
│   ├── snappyHexMeshDict       # Mesh refinement (levels 5-6)
│   ├── surfaceFeaturesDict     # Feature edge extraction
│   ├── controlDict             # Solver parameters (1000 iters)
│   ├── fvSchemes               # Numerical schemes
│   └── fvSolution              # Linear solver settings
├── scripts/                    # Automation scripts
│   ├── Allrun.mesh             # Automated mesh generation
│   ├── Allrun.solver           # Automated solver (serial)
│   ├── Allclean                # Cleanup script
│   ├── submit_mesh.slurm       # HPC mesh job (4hr, 8 CPUs)
│   ├── submit_solver.slurm     # HPC solver job (24hr, 16 tasks)
│   └── verify_config.sh        # Configuration checker
├── docs/                       # Documentation
│   ├── HPC_GUIDE.md            # Complete HPC guide (START HERE)
│   └── TECHNICAL_REFERENCE.md  # Developer/advanced user guide
├── logs/                       # Timestamped logs (auto-created)
└── README.md                   # This file
```

## 🚀 Quick Start

### Local Mesh Generation (if you have 32GB+ RAM)
```bash
cd BeamCleaning
scripts/Allclean              # Clean old files
scripts/Allrun.mesh           # Generate mesh (1-4 hours)
paraFoam                      # Visualize
```

### HPC Workflow (Recommended)
```bash
# 1. Clean and verify
scripts/Allclean
scripts/verify_config.sh

# 2. Edit SLURM scripts with your HPC's OpenFOAM module
# Edit line 35 in scripts/submit_mesh.slurm
# Edit line 27 in scripts/submit_solver.slurm

# 3. Transfer to HPC
rsync -avz --progress BeamCleaning/ username@hpc:~/BeamCleaning/

# 4. On HPC
cd ~/BeamCleaning
sbatch scripts/submit_mesh.slurm
squeue -u $USER
tail -f logs/mesh_*.out

# 5. After mesh completes
cat constant/polyMesh/boundary  # Verify enclosure patch exists
sbatch scripts/submit_solver.slurm
```

## 📊 Simulation Details

| Parameter | Value |
|-----------|-------|
| **Solver** | rhoSimpleFoam (compressible, steady-state) |
| **Turbulence** | k-epsilon RANS |
| **Inlet Pressure** | 70 psi (4.83 bar) (482.6 kPa) at nozzleInlet |
| **Outlet Pressure** | 1 atm (101.325 kPa) at holes/enclosure |
| **Temperature** | 300 K |
| **Mesh Cells** | ~6-7 million (with enclosure) |
| **Refinement** | Level 5-6 on holes/nozzle (finest) |
| **Beam Length** | 3240 mm |
| **Domain Size** | 500×4240×500 mm |

## ⚠️ Known Issues

1. **Geometry has 32 holes, need 54 holes**
   - Current: 32 holes in beam_holes.stl
   - Required: 54 holes at 60mm spacing
   - Impact: Simulation runs but doesn't match final design
   - Solution: Regenerate beam_holes.stl (after enclosure verification)

2. **Enclosure configuration untested**
   - Status: Configuration complete but never run with enclosure
   - Risk: Low (simple box geometry, properly scaled)
   - Action: First mesh run on HPC will validate

## 📚 Documentation

- **docs/HPC_GUIDE.md** - Complete HPC usage guide (start here!)
- **docs/TECHNICAL_REFERENCE.md** - Technical details for developers
- **QUICK_REFERENCE.txt** - Command cheat sheet (root directory)

## 🔧 Key Configuration Highlights

### Mesh Refinement Levels
- **beamHoles**: Level (5 6) - 8x finer than before
- **nozzle**: Level (4 5) - 8x finer
- **beamWalls**: Level (3 4) - 4x finer
- **enclosure**: Level (1 2) - Basic refinement

### Boundary Conditions
| Patch | Pressure | Velocity | Notes |
|-------|----------|----------|-------|
| nozzleInlet | 482.6 kPa (total) | zeroGradient | High-pressure inlet |
| beamHoles | 101.325 kPa | pressureInletOutlet | Air exits here |
| enclosure | 101.325 kPa | pressureInletOutlet | Atmospheric boundary |
| beamWalls | zeroGradient | noSlip | Solid walls |
| nozzle | zeroGradient | noSlip | Solid nozzle |

### Solver Settings
- **Iterations**: Up to 1000 (or until convergence)
- **Convergence**: Residuals < 1e-5
- **Relaxation**: Under-relaxed for stability (p=0.3, U=0.7, etc.)
- **Parallel**: Decomposed for 16 processors on HPC

## 🆘 Troubleshooting

### Mesh Generation Fails
```bash
# Check logs
cat logs/mesh_*/log.blockMesh
cat logs/mesh_*/log.snappyHexMesh

# Common fixes:
# - Out of memory: Increase SLURM --mem=32GB
# - Timeout: Increase SLURM --time=04:00:00
# - Module not found: Edit scripts/submit_mesh.slurm line 35
```

### Enclosure Patch Missing
```bash
# After mesh generation
cat constant/polyMesh/boundary | grep enclosure

# If missing:
# - Check logs/mesh_*/log.snappyHexMesh for errors
# - Verify enclosure.stl exists: ls -lh constant/triSurface/enclosure.stl
# - Check system/snappyHexMeshDict has "scale 0.001;" for enclosure
```

### Solver Diverges
```bash
# Check residuals
cat logs/solver_*/log.rhoSimpleFoam | grep "Solving for"

# Solutions:
# - Reduce relaxation factors in system/fvSolution
# - Check mesh quality: checkMesh
# - Use more stable schemes in system/fvSchemes
```

## 📈 Expected Results

### Mesh Statistics (with enclosure)
- Total cells: ~6-7 million
- beamHoles faces: ~18,000 (excellent refinement)
- enclosure faces: ~thousands
- Mesh generation time: 3-5 hours on 8 CPUs

### Solver Results
- Convergence: Typically 200-500 iterations
- Runtime: 12-24 hours on 16 cores
- Final residuals: p < 1e-5, U < 1e-6
- Output: Velocity, pressure, temperature fields

## 📞 Getting Help

1. Run verification: `scripts/verify_config.sh`
2. Check documentation in `docs/`
3. Review log files in `logs/`
4. See troubleshooting section above

## 🔄 Next Steps

1. ✅ Verify configuration: `scripts/verify_config.sh`
2. ✅ Clean old mesh: `scripts/Allclean`
3. ⏳ Edit SLURM scripts with HPC module commands
4. ⏳ Transfer to HPC
5. ⏳ Submit mesh job and verify enclosure patch created
6. ⏳ Submit solver job
7. ⏳ Analyze results in ParaView
8. ⏳ Regenerate beam_holes.stl with 54 holes
9. ⏳ Re-run with corrected geometry

---

**Note**: This case is configured for OpenFOAM 13. Make sure your HPC has OpenFOAM 13 or v2312 available.
