# BeamCleaning Technical Reference

Technical documentation for developers and advanced users modifying the OpenFOAM case.

---

## Project Overview

**Type:** OpenFOAM CFD Simulation  
**Purpose:** DUNE Beam Cleaning - Compressible turbulent flow through hollow beam with high-pressure air jets  
**Solver:** rhoSimpleFoam (steady-state compressible RANS)  
**Turbulence:** k-epsilon model  
**Version:** OpenFOAM 13 / v2312  

---

## Geometry Specifications

### Coordinate System
- **Origin:** (0, 0, 0)
- **Beam axis:** Along -Y direction
- **Beam extent:** y = 0 to y = -3240 mm

### Beam Dimensions
- **Length:** 3240 mm (along Y-axis)
- **Cross-section:** 50.8 × 50.8 mm (square, in X-Z plane)
- **Wall thickness:** 6.35 mm
- **Hollow interior:** 38.1 × 38.1 mm
- **Front opening:** y ≈ 0 mm
- **Back opening:** y ≈ -3240 mm
- **Holes:** 32 total (need 54), from y = -28 to y = -3212 mm

### Nozzle Dimensions
- **Length:** 510 mm
- **Position:** y = -2490 to y = -3000 mm
- **Outer diameter:** ~20 mm
- **Inlet diameter:** ~8.5 mm
- **Inlet face:** y ≈ -2600 mm

### Enclosure (Atmospheric Boundary)
- **X:** -250 to 250 mm (500 mm width)
- **Y:** -3740 to 500 mm (4240 mm length)
- **Z:** -250 to 250 mm (500 mm height)

### Computational Domain
- **Dimensions:** 500 × 4240 × 500 mm
- **Background mesh:** 100 × 170 × 100 cells (~1.7M base)
- **Cell size:** ~5 mm uniform

---

## Directory Structure

```
BeamCleaning/
├── 0/                          # Initial/boundary conditions
│   ├── p                       # Pressure field
│   ├── U                       # Velocity field
│   ├── T                       # Temperature field
│   ├── k                       # Turbulent kinetic energy
│   ├── epsilon                 # Turbulent dissipation
│   └── nut                     # Turbulent viscosity
├── constant/
│   ├── polyMesh/               # Mesh (generated)
│   ├── triSurface/             # STL geometries
│   │   ├── beam_walls.stl      # Beam structure
│   │   ├── beam_holes.stl      # 32 holes (scaled in config)
│   │   ├── beam_front_opening.stl
│   │   ├── beam_back_opening.stl
│   │   ├── nozzle.stl          # Nozzle body
│   │   ├── nozzle_inlet.stl    # Nozzle inlet face
│   │   └── enclosure.stl       # Atmospheric boundary
│   ├── extendedFeatureEdgeMesh/ # Feature edges (generated)
│   ├── thermophysicalProperties # Fluid properties (air)
│   └── turbulenceProperties     # Turbulence model config
├── system/
│   ├── controlDict             # Runtime control, I/O
│   ├── fvSchemes               # Numerical schemes
│   ├── fvSolution              # Linear solver settings
│   ├── blockMeshDict           # Background mesh definition
│   ├── snappyHexMeshDict       # Mesh refinement config
│   ├── surfaceFeaturesDict     # Feature extraction
│   └── decomposeParDict        # Parallel decomposition (auto-generated)
├── scripts/                    # Automation scripts
├── docs/                       # Documentation
├── logs/                       # Log files (timestamped)
└── [1-9]*/                     # Time directories (results)
```

---

## OpenFOAM Commands

### Mesh Generation
```bash
# Automated (recommended)
scripts/Allrun.mesh

# Manual steps
blockMesh                    # Create background mesh
surfaceFeatures              # Extract surface features  
snappyHexMesh -overwrite     # Generate refined mesh
checkMesh                    # Validate mesh quality
```

### Running Solver
```bash
# Serial (local testing)
rhoSimpleFoam

# Parallel (HPC)
decomposePar                 # Decompose mesh for parallel
mpirun -np 16 rhoSimpleFoam -parallel
reconstructPar               # Reconstruct solution

# Test single iteration
rhoSimpleFoam -writeNow

# Background with logging
rhoSimpleFoam > log.rhoSimpleFoam 2>&1 &
```

### Post-Processing
```bash
# Visualization
paraFoam                     # Launch ParaView
paraFoam -builtin            # Use built-in reader

# Function objects
postProcess -func forces
postProcess -func forceCoeffs
postProcess -func wallShearStress
postProcess -func yPlus      # Wall distance

# Sampling
postProcess -func sample     # Sample along lines/surfaces
foamListTimes                # List available time directories
```

### Utilities
```bash
# Mesh checks
checkMesh                    # Quality metrics
checkMesh -allGeometry       # Detailed geometry check
checkMesh -allTopology       # Topology check

# Dictionary queries
foamDictionary 0/U -entry boundaryField
foamDictionary system/controlDict -entry endTime -set 2000

# Field manipulation
mapFields ../otherCase       # Map fields from another case
changeDictionary             # Modify fields using dictionary

# Cleanup
scripts/Allclean             # Remove mesh and results
foamCleanTutorials           # Deep clean (use with caution)
```

---

## File Formats & Conventions

### OpenFOAM Dictionary Files

**Header Template:**
```cpp
/*--------------------------------*- C++ -*----------------------------------*\
| =========                 |                                                 |
| \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox           |
|  \\    /   O peration     | Version:  13                                    |
|   \\  /    A nd           | Website:  www.openfoam.com                      |
|    \\/     M anipulation  |                                                 |
\*---------------------------------------------------------------------------*/
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;     // or volScalarField, volVectorField
    object      controlDict;    // filename
}
// * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * //
```

**Footer:**
```cpp
// ************************************************************************* //
```

### Formatting Rules
- **Indentation:** 4 spaces (no tabs)
- **Semicolons:** Required after all values
- **Comments:** `//` for line, `/* */` for blocks
- **Braces:** Opening brace same line: `subdictionary {`
- **Lists:** Use parentheses: `(value1 value2)` or multiline
- **Alignment:** Align key-value pairs for readability

**Example:**
```cpp
boundaryField
{
    inlet
    {
        type            fixedValue;
        value           uniform (0 0 10);    // m/s
    }
    
    walls
    {
        type            noSlip;
    }
}
```

### Naming Conventions

**Files:**
- Dictionaries: camelCase (`blockMeshDict`, `controlDict`)
- Fields: lowercase (`p`, `U`, `T`, `k`, `epsilon`, `nut`)
- Geometries: snake_case (`beam_walls.stl`, `nozzle_inlet.stl`)
- Scripts: Allrun.* pattern (`scripts/Allrun.mesh`)

**Patches/Boundaries:**
- Convention: camelCase
- Examples: `beamWalls`, `nozzleInlet`, `beamHoles`, `enclosure`

**Standard Fields:**
- `U` - Velocity vector (always uppercase)
- `p` - Pressure (lowercase)
- `T` - Temperature
- `k` - Turbulent kinetic energy
- `epsilon` - Turbulent dissipation rate
- `nut` - Turbulent viscosity

---

## Dimensions & Units

OpenFOAM uses SI units with dimensional notation: `[kg m s K mol A cd]`

```cpp
dimensions      [0 1 -1 0 0 0 0];    // m/s (velocity)
dimensions      [1 -1 -2 0 0 0 0];   // Pa (pressure)
dimensions      [0 0 0 1 0 0 0];     // K (temperature)
dimensions      [0 2 -2 0 0 0 0];    // m²/s² (k)
dimensions      [0 2 -3 0 0 0 0];    // m²/s³ (epsilon)
dimensions      [0 2 -1 0 0 0 0];    // m²/s (nut)
```

### This Case - Key Values
- **Pressure:** 482,633 Pa (inlet), 101,325 Pa (outlets)
- **Velocity:** Calculated from pressure
- **Temperature:** 300 K everywhere
- **Turbulence intensity:** 5% (I = 0.05)
- **Turbulent length scale:** 0.07 * hydraulic diameter

---

## Boundary Condition Types

### Common Types

**Fixed Value (Dirichlet):**
```cpp
inlet
{
    type            fixedValue;
    value           uniform (0 0 10);  // Vector
}
```

**Zero Gradient (Neumann):**
```cpp
outlet
{
    type            zeroGradient;
}
```

**Wall Functions:**
```cpp
walls
{
    type            noSlip;          // U
}
walls
{
    type            kqRWallFunction;  // k at walls
    value           uniform 0.01;
}
```

**Total Pressure (Compressible):**
```cpp
inlet
{
    type            totalPressure;
    p0              uniform 600000;   // Pa
    value           uniform 600000;   // Initial value
}
```

**Wave Transmissive (Non-reflecting outlet):**
```cpp
outlet
{
    type            waveTransmissive;
    field           p;
    psi             thermo:psi;       // Compressibility
    gamma           1.4;               // Specific heat ratio
    fieldInf        101325;           // Far-field value
    lInf            1;                // Length scale
    value           uniform 101325;
}
```

**Pressure Inlet/Outlet Velocity:**
```cpp
outlet
{
    type            pressureInletOutletVelocity;
    value           uniform (0 0 0);
}
```

### This Case - Patches & BCs

| Patch | p | U | T | k | epsilon | nut |
|-------|---|---|---|---|---------|-----|
| **nozzleInlet** | totalPressure (482.6 kPa) | zeroGradient | fixedValue (300K) | turbulentIntensity | turbulentMixing | calculated |
| **beamHoles** | waveTransmissive (101.325 kPa) | pressureInletOutlet | inletOutlet (300K) | inletOutlet | inletOutlet | calculated |
| **enclosure** | waveTransmissive (101.325 kPa) | pressureInletOutlet | inletOutlet (300K) | inletOutlet | inletOutlet | calculated |
| **beamWalls** | zeroGradient | noSlip | zeroGradient | kqRWallFunction | epsilonWallFunction | nutkWallFunction |
| **nozzle** | zeroGradient | noSlip | zeroGradient | kqRWallFunction | epsilonWallFunction | nutkWallFunction |
| **openings** | waveTransmissive (101.325 kPa) | pressureInletOutlet | inletOutlet (300K) | inletOutlet | inletOutlet | calculated |

---

## Mesh Configuration

### Background Mesh (system/blockMeshDict)
```cpp
blocks
(
    hex (0 1 2 3 4 5 6 7) (100 170 100) simpleGrading (1 1 1)
);
```
- **Domain:** 500 × 4240 × 500 mm
- **Cells:** 100 × 170 × 100 = 1,700,000 base cells
- **Resolution:** ~5 mm uniform

### Refinement Levels (system/snappyHexMeshDict)

**Surface Refinement:**
```cpp
refinementSurfaces
{
    beamHoles    { level (5 6); }  // Finest - 8x finer than before
    nozzleInlet  { level (4 5); }  // Fine
    nozzle       { level (4 5); }
    beamWalls    { level (3 4); }  // Medium
    enclosure    { level (1 2); }  // Coarse (just capture boundary)
    openings     { level (2 3); }
}
```

**Refinement meaning:**
- Level 0: Base cell size (~5 mm)
- Level 1: 2.5 mm
- Level 2: 1.25 mm  
- Level 3: 0.625 mm
- Level 4: 0.3125 mm
- Level 5: 0.156 mm
- Level 6: 0.078 mm (finest)

**Feature Edges:**
```cpp
features
(
    { file "beam_holes.eMesh"; level 5; }
    { file "nozzle.eMesh"; level 4; }
    // ... etc
);
```

**Important:** All STL files are in millimeters, scaled in config:
```cpp
geometry
{
    beam_holes.stl  { type triSurfaceMesh; name beamHoles; scale 0.001; }
    // mm → m conversion
}
```

---

## Solver Configuration

### Control Dict (system/controlDict)
```cpp
application     rhoSimpleFoam;
startFrom       latestTime;
startTime       0;
stopAt          endTime;
endTime         1000;           // Iterations (steady-state)
deltaT          1;              // Pseudo-time step
writeControl    timeStep;
writeInterval   100;            // Write every 100 iterations
purgeWrite      3;              // Keep last 3 time directories
```

### Numerical Schemes (system/fvSchemes)
```cpp
ddtSchemes      { default steadyState; }
gradSchemes     { default Gauss linear; }
divSchemes
{
    default         none;
    div(phi,U)      bounded Gauss linearUpwind grad(U);
    div(phi,K)      bounded Gauss upwind;
    div(phi,h)      bounded Gauss upwind;
    div(phi,k)      bounded Gauss upwind;
    div(phi,epsilon) bounded Gauss upwind;
}
laplacianSchemes { default Gauss linear corrected; }
```

### Linear Solvers & Relaxation (system/fvSolution)
```cpp
solvers
{
    p
    {
        solver          GAMG;
        tolerance       1e-06;
        relTol          0.01;
    }
    
    U
    {
        solver          smoothSolver;
        smoother        GaussSeidel;
        tolerance       1e-07;
        relTol          0.1;
    }
}

relaxationFactors
{
    fields
    {
        p               0.3;    // Conservative for stability
        rho             0.01;
    }
    equations
    {
        U               0.7;
        h               0.7;
        k               0.7;
        epsilon         0.7;
    }
}
```

**Convergence criteria:**
```cpp
SIMPLE
{
    nNonOrthogonalCorrectors 0;
    consistent      yes;
    
    residualControl
    {
        p               1e-5;
        U               1e-6;
        "(k|epsilon)"   1e-5;
    }
}
```

---

## Common Modifications

### Adjust Mesh Refinement
Edit `system/snappyHexMeshDict`:
```cpp
refinementSurfaces
{
    beamHoles
    {
        level (5 6);  // Increase first number for coarser mesh
                      // Decrease for finer mesh
    }
}
```

**Impact:**
- Level (4 5) instead of (5 6): 8x fewer cells, faster but less accurate
- Level (6 7) instead of (5 6): 8x more cells, slower but more accurate

### Change Inlet Pressure
Edit `0/p`:
```cpp
nozzleInlet
{
    type            totalPressure;
    p0              uniform 550000;  // Change from 70 psi to 80 psi as example
    value           uniform 550000;
}
```

### Modify Convergence Criteria
Edit `system/fvSolution`:
```cpp
residualControl
{
    p               1e-4;  // Less strict (faster, less accurate)
    U               1e-5;
}
```

Or `system/controlDict`:
```cpp
endTime         2000;  // More iterations if not converging
```

### Add Post-Processing Functions
Edit `system/controlDict`:
```cpp
functions
{
    forces
    {
        type            forces;
        libs            ("libforces.so");
        patches         (beamWalls nozzle);
        rho             rhoInf;
        rhoInf          1.225;
        CofR            (0 0 0);
        writeControl    timeStep;
        writeInterval   10;
    }
}
```

### Change Turbulence Model
Edit `constant/turbulenceProperties`:
```cpp
simulationType      RAS;
RAS
{
    RASModel        kOmegaSST;  // Change from kEpsilon
    turbulence      on;
    printCoeffs     on;
}
```

Then update boundary conditions in `0/k`, `0/epsilon` → `0/omega`.

---

## Troubleshooting

### Mesh Issues

**Negative volumes:**
```bash
checkMesh | grep "negative"
```
Fix: Reduce refinement levels, check STL file orientation

**High non-orthogonality (>75°):**
```bash
checkMesh | grep "non-orthogonality"
```
Fix: Increase nNonOrthogonalCorrectors in system/fvSolution

**High skewness (>4):**
Fix: Adjust refinement regions, add layers gradually

### Solver Issues

**Divergence:**
- Reduce relaxation factors (system/fvSolution)
- Use upwind schemes (system/fvSchemes)
- Check mesh quality
- Verify boundary conditions are physical

**Slow convergence:**
- Check residuals are decreasing
- Increase iterations (system/controlDict)
- Adjust solver tolerances (system/fvSolution)
- Try different linear solvers

**Unphysical results:**
- Check boundary conditions
- Verify dimensions in all fields
- Check turbulence model parameters
- Validate mesh quality near critical regions

---

## Advanced Topics

### Parallel Decomposition
```bash
# Auto-generate decomposeParDict
decomposePar -copyZero

# Or manually edit system/decomposeParDict
numberOfSubdomains 16;
method          scotch;  // or hierarchical, simple
```

### Adaptive Mesh Refinement
Not implemented in this case, but can be added via:
- dynamicMeshDict
- refinementRegions based on field gradients

### Custom Boundary Conditions
Compile custom BC:
```bash
cd customBC/
wmake libso
```
Reference in controlDict:
```cpp
libs ("libcustomBC.so");
```

### Field Manipulation
Initialize fields from expressions:
```bash
funkySetFields -field U -expression "vector(0, -10, 0)"
```

---

## Performance Optimization

### Mesh Size vs Accuracy
- Refinement level +1: 8x more cells, 8x longer runtime
- Target: Capture holes with 20+ cells across diameter
- Current: Level 5-6 achieves ~50 cells across 8.5mm hole

### Solver Settings
- GAMG for pressure: Fast convergence on large meshes
- GaussSeidel for velocity: Stable for convection-dominated flows
- Relaxation factors: Lower = more stable but slower

### Parallel Scaling
- Ideal: 200,000-500,000 cells per core
- This case: 6M cells → 12-30 cores optimal
- Diminishing returns beyond 32 cores

---

## References

- **OpenFOAM User Guide:** https://www.openfoam.com/documentation/user-guide
- **OpenFOAM Wiki:** https://openfoamwiki.net
- **CFD Online:** https://www.cfd-online.com/Forums/openfoam
- **rhoSimpleFoam Source:** $FOAM_SOLVERS/compressible/rhoSimpleFoam/

---

**Version:** OpenFOAM 13 / v2312  
**Last Updated:** February 2026  
**Case Status:** Configured and ready for HPC
