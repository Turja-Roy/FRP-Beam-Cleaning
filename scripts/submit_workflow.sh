#!/bin/bash
#
# Automated OpenFOAM Beam Cleaning Workflow
# Submits mesh generation and solver with dependency chain
#
# Usage: ./submit_workflow.sh [options]
# Options:
#   --mesh-only     Submit only mesh generation
#   --solver-only   Submit only solver (requires mesh to exist)
#   --check-only    Check configuration without submitting
#   -h, --help      Show this help message

set -e # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and case directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="$(dirname "$SCRIPT_DIR")"

# Log directory
LOG_DIR="$CASE_DIR/logs"
mkdir -p "$LOG_DIR"

# Workflow log file
WORKFLOW_LOG="$LOG_DIR/workflow_$(date +%Y%m%d_%H%M%S).log"

#===================================
# Helper Functions
#===================================

log_message() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$WORKFLOW_LOG" >&2
}

print_header() {
	echo -e "${BLUE}========================================${NC}" >&2
	echo -e "${BLUE}$1${NC}" >&2
	echo -e "${BLUE}========================================${NC}" >&2
}

print_success() {
	echo -e "${GREEN}✓ $1${NC}" >&2
	log_message "SUCCESS: $1"
}

print_error() {
	echo -e "${RED}✗ $1${NC}" >&2
	log_message "ERROR: $1"
}

print_warning() {
	echo -e "${YELLOW}! $1${NC}" >&2
	log_message "WARNING: $1"
}

print_info() {
	echo -e "${BLUE}→ $1${NC}" >&2
	log_message "INFO: $1"
}

show_help() {
	cat <<EOF
Automated OpenFOAM Beam Cleaning Workflow Submission

Usage: $0 [options]

Options:
    --mesh-only      Submit only mesh generation job
    --solver-only    Submit only solver job (requires completed mesh)
    --check-only     Check configuration without submitting jobs
    -h, --help       Show this help message

Description:
    This script automates the submission of the beam cleaning CFD simulation
    workflow to SLURM. By default, it submits both mesh generation and solver
    jobs with automatic dependency handling.

    The solver job will automatically start only after the mesh job completes
    successfully (exit code 0). If the mesh job fails, the solver job will be
    automatically cancelled.

Examples:
    $0                    # Submit full workflow (mesh → solver)
    $0 --mesh-only        # Submit only mesh generation
    $0 --solver-only      # Submit only solver (mesh must exist)
    $0 --check-only       # Validate configuration

EOF
}

#===================================
# Pre-flight Checks
#===================================

check_configuration() {
	print_header "Pre-flight Configuration Check"

	local errors=0

	# Check if we're on SLURM system
	if ! command -v sbatch &>/dev/null; then
		print_error "sbatch command not found. Not on a SLURM system?"
		((errors++))
	else
		print_success "SLURM detected (sbatch available)"
	fi

	# Check required scripts exist
	if [[ ! -f "$SCRIPT_DIR/submit_mesh.slurm" ]]; then
		print_error "submit_mesh.slurm not found"
		((errors++))
	else
		print_success "submit_mesh.slurm found"
	fi

	if [[ ! -f "$SCRIPT_DIR/submit_solver.slurm" ]]; then
		print_error "submit_solver.slurm not found"
		((errors++))
	else
		print_success "submit_solver.slurm found"
	fi

	# Check OpenFOAM case structure
	if [[ ! -d "$CASE_DIR/system" ]]; then
		print_error "system/ directory not found"
		((errors++))
	else
		print_success "system/ directory found"
	fi

	if [[ ! -d "$CASE_DIR/constant" ]]; then
		print_error "constant/ directory not found"
		((errors++))
	else
		print_success "constant/ directory found"
	fi

	# Check decomposeParDict files
	if [[ ! -f "$CASE_DIR/system/decomposeParDict.mesh" ]]; then
		print_warning "system/decomposeParDict.mesh not found (mesh parallelization disabled)"
	else
		print_success "system/decomposeParDict.mesh found"
	fi

	if [[ ! -f "$CASE_DIR/system/decomposeParDict" ]]; then
		print_error "system/decomposeParDict not found"
		((errors++))
	else
		print_success "system/decomposeParDict found"
	fi

	# Check STL geometry files
	local stl_count=$(find "$CASE_DIR/constant/triSurface" -name "*.stl" 2>/dev/null | wc -l)
	if [[ $stl_count -eq 0 ]]; then
		print_error "No STL files found in constant/triSurface/"
		((errors++))
	else
		print_success "$stl_count STL geometry files found"
	fi

	# Check log directory
	if [[ ! -d "$LOG_DIR" ]]; then
		print_warning "logs/ directory not found, creating..."
		mkdir -p "$LOG_DIR"
	else
		print_success "logs/ directory exists"
	fi

	echo ""
	if [[ $errors -gt 0 ]]; then
		print_error "Configuration check failed with $errors error(s)"
		return 1
	else
		print_success "All pre-flight checks passed"
		return 0
	fi
}

#===================================
# Job Submission Functions
#===================================

submit_mesh_job() {
	print_header "Submitting Mesh Generation Job"

	cd "$CASE_DIR"

	# Submit mesh job and capture job ID
	local submit_output
	submit_output=$(sbatch "$SCRIPT_DIR/submit_mesh.slurm" 2>&1)

	if [[ $? -ne 0 ]]; then
		print_error "Failed to submit mesh job"
		print_error "$submit_output"
		return 1
	fi

	# Extract job ID (format: "Submitted batch job 12345")
	local mesh_job_id=$(echo "$submit_output" | grep -oP 'Submitted batch job \K\d+')

	if [[ -z "$mesh_job_id" ]]; then
		print_error "Could not extract mesh job ID from output: $submit_output"
		return 1
	fi

	print_success "Mesh job submitted: Job ID = $mesh_job_id"
	print_info "Job name: BeamClean_mesh"
	print_info "Cores: 12"
	print_info "Memory: 36GB"
	print_info "Time limit: 1 hour"
	print_info "Log file: logs/mesh_${mesh_job_id}.out"

	# Return job ID via stdout (redirect print messages to stderr to avoid capture)
	echo "$mesh_job_id"
	return 0
}

submit_solver_job() {
	local dependency_job_id=$1

	print_header "Submitting Solver Job"

	cd "$CASE_DIR"

	# Build sbatch command with or without dependency
	local sbatch_cmd="sbatch"

	if [[ -n "$dependency_job_id" ]]; then
		# afterok = run only if dependency job exits with code 0
		sbatch_cmd="sbatch --dependency=afterok:$dependency_job_id"
		print_info "Setting dependency: afterok:$dependency_job_id"
	fi

	# Submit solver job
	local submit_output
	submit_output=$($sbatch_cmd "$SCRIPT_DIR/submit_solver.slurm" 2>&1)

	if [[ $? -ne 0 ]]; then
		print_error "Failed to submit solver job"
		print_error "$submit_output"
		return 1
	fi

	# Extract job ID
	local solver_job_id=$(echo "$submit_output" | grep -oP 'Submitted batch job \K\d+')

	if [[ -z "$solver_job_id" ]]; then
		print_error "Could not extract solver job ID from output: $submit_output"
		return 1
	fi

	print_success "Solver job submitted: Job ID = $solver_job_id"
	print_info "Job name: BeamClean_solver"
	print_info "Cores: 48"
	print_info "Memory: 144GB"
	print_info "Time limit: 8 hours"
	print_info "Log file: logs/solver_${solver_job_id}.out"

	if [[ -n "$dependency_job_id" ]]; then
		print_info "Dependency: Will start after job $dependency_job_id completes successfully"
	fi

	echo "$solver_job_id"
	return 0
}

#===================================
# Main Workflow
#===================================

main() {
	local mode="full" # full, mesh-only, solver-only, check-only

	# Parse command line arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mesh-only)
			mode="mesh-only"
			shift
			;;
		--solver-only)
			mode="solver-only"
			shift
			;;
		--check-only)
			mode="check-only"
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		*)
			print_error "Unknown option: $1"
			show_help
			exit 1
			;;
		esac
	done

	print_header "OpenFOAM Beam Cleaning Workflow Automation"
	print_info "Case directory: $CASE_DIR"
	print_info "Script directory: $SCRIPT_DIR"
	print_info "Workflow log: $WORKFLOW_LOG"
	print_info "Mode: $mode"
	echo ""

	# Run configuration checks
	if ! check_configuration; then
		print_error "Configuration check failed. Aborting."
		exit 1
	fi

	if [[ "$mode" == "check-only" ]]; then
		print_success "Check complete. Ready for submission."
		exit 0
	fi

	echo ""

	# Execute workflow based on mode
	case $mode in
	mesh-only)
		mesh_job_id=$(submit_mesh_job)
		if [[ $? -eq 0 ]]; then
			echo ""
			print_header "Submission Summary"
			print_success "Mesh job submitted: $mesh_job_id"
			print_info "Monitor with: squeue -u \$USER"
			print_info "View log: tail -f $LOG_DIR/mesh_${mesh_job_id}.out"
		else
			exit 1
		fi
		;;

	solver-only)
		# Check if mesh exists
		if [[ ! -d "$CASE_DIR/constant/polyMesh" ]]; then
			print_error "Mesh not found in constant/polyMesh/"
			print_error "Run mesh generation first or use full workflow"
			exit 1
		fi

		solver_job_id=$(submit_solver_job "")
		if [[ $? -eq 0 ]]; then
			echo ""
			print_header "Submission Summary"
			print_success "Solver job submitted: $solver_job_id"
			print_info "Monitor with: squeue -u \$USER"
			print_info "View log: tail -f $LOG_DIR/solver_${solver_job_id}.out"
		else
			exit 1
		fi
		;;

	full)
		# Submit mesh job
		mesh_job_id=$(submit_mesh_job)
		if [[ $? -ne 0 ]]; then
			print_error "Mesh job submission failed. Aborting workflow."
			exit 1
		fi

		echo ""

		# Submit solver job with dependency on mesh job
		solver_job_id=$(submit_solver_job "$mesh_job_id")
		if [[ $? -ne 0 ]]; then
			print_error "Solver job submission failed."
			print_warning "Mesh job $mesh_job_id is still running/queued"
			print_info "You can cancel it with: scancel $mesh_job_id"
			exit 1
		fi

		echo ""
		print_header "Workflow Submission Summary"
		print_success "Full workflow submitted successfully!"
		echo ""
		print_info "Job Chain:"
		print_info "  1. Mesh Generation: Job $mesh_job_id (12 cores, ~15-25 min)"
		print_info "     → Will run immediately or when resources available"
		print_info ""
		print_info "  2. Solver: Job $solver_job_id (48 cores, ~6-8 hours)"
		print_info "     → Will run ONLY after mesh job completes successfully"
		print_info "     → Will be CANCELLED if mesh job fails"
		echo ""
		print_info "Monitoring Commands:"
		print_info "  squeue -u \$USER                               # Check job status"
		print_info "  tail -f $LOG_DIR/mesh_${mesh_job_id}.out      # Watch mesh progress"
		print_info "  tail -f $LOG_DIR/solver_${solver_job_id}.out  # Watch solver progress"
		echo ""
		print_info "Management Commands:"
		print_info "  scancel $mesh_job_id          # Cancel mesh job"
		print_info "  scancel $solver_job_id        # Cancel solver job"
		print_info "  scancel $mesh_job_id $solver_job_id  # Cancel both"
		echo ""
		print_success "Workflow log saved to: $WORKFLOW_LOG"
		;;
	esac

	return 0
}

# Execute main function
main "$@"
