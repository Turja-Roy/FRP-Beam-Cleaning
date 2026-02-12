#!/bin/bash
#
# Job Monitoring and Status Checking Script
# Quick utility to check status of OpenFOAM jobs
#
# Usage: ./monitor_jobs.sh [options]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$CASE_DIR/logs"

print_header() {
	echo -e "${BLUE}========================================${NC}"
	echo -e "${BLUE}$1${NC}"
	echo -e "${BLUE}========================================${NC}"
}

show_help() {
	cat <<EOF
Job Monitoring and Status Script

Usage: $0 [command]

Commands:
    status          Show current job queue status (default)
    logs            List available log files
    mesh-log        Tail latest mesh generation log
    solver-log      Tail latest solver log
    mesh-status     Check mesh generation status
    solver-status   Check solver residuals
    clean-logs      Archive old logs
    -h, --help      Show this help message

Examples:
    $0                  # Show job queue
    $0 status           # Show job queue
    $0 mesh-log         # Watch mesh generation
    $0 solver-status    # Check solver progress

EOF
}

show_queue() {
	print_header "SLURM Job Queue"

	if ! command -v squeue &>/dev/null; then
		echo -e "${RED}Error: Not on a SLURM system${NC}"
		exit 1
	fi

	echo -e "${CYAN}Your running/pending jobs:${NC}"
	squeue -u $USER -o "%.18i %.12j %.8T %.10M %.6D %.4C %.8m %.10l %.20S" || echo "No jobs found"

	echo ""
	echo -e "${CYAN}BeamCleaning jobs specifically:${NC}"
	squeue -u $USER --name=BeamClean_mesh,BeamClean_solver -o "%.18i %.15j %.8T %.10M %.6D %.4C %.8m %.10l" 2>/dev/null || echo "No BeamCleaning jobs found"
}

list_logs() {
	print_header "Available Log Files"

	if [[ ! -d "$LOG_DIR" ]]; then
		echo -e "${YELLOW}No logs directory found${NC}"
		return
	fi

	echo -e "${CYAN}Mesh generation logs:${NC}"
	ls -lht "$LOG_DIR"/mesh_*.out 2>/dev/null | head -5 || echo "  No mesh logs found"

	echo ""
	echo -e "${CYAN}Solver logs:${NC}"
	ls -lht "$LOG_DIR"/solver_*.out 2>/dev/null | head -5 || echo "  No solver logs found"

	echo ""
	echo -e "${CYAN}Workflow logs:${NC}"
	ls -lht "$LOG_DIR"/workflow_*.log 2>/dev/null | head -5 || echo "  No workflow logs found"
}

tail_mesh_log() {
	local latest_log=$(ls -t "$LOG_DIR"/mesh_*.out 2>/dev/null | head -1)

	if [[ -z "$latest_log" ]]; then
		echo -e "${YELLOW}No mesh log files found${NC}"
		exit 1
	fi

	print_header "Mesh Generation Log: $(basename $latest_log)"
	echo -e "${CYAN}File: $latest_log${NC}"
	echo -e "${CYAN}Press Ctrl+C to exit${NC}"
	echo ""

	tail -f "$latest_log"
}

tail_solver_log() {
	local latest_log=$(ls -t "$LOG_DIR"/solver_*.out 2>/dev/null | head -1)

	if [[ -z "$latest_log" ]]; then
		echo -e "${YELLOW}No solver log files found${NC}"
		exit 1
	fi

	print_header "Solver Log: $(basename $latest_log)"
	echo -e "${CYAN}File: $latest_log${NC}"
	echo -e "${CYAN}Press Ctrl+C to exit${NC}"
	echo ""

	tail -f "$latest_log"
}

check_mesh_status() {
	print_header "Mesh Generation Status"

	# Check if mesh exists
	if [[ -d "$CASE_DIR/constant/polyMesh" ]]; then
		echo -e "${GREEN}✓ Mesh exists in constant/polyMesh/${NC}"

		# Get mesh info if checkMesh log exists
		local mesh_log=$(ls -t "$LOG_DIR"/mesh_*.out 2>/dev/null | head -1)
		if [[ -n "$mesh_log" ]] && [[ -f "$mesh_log" ]]; then
			echo ""
			echo -e "${CYAN}Mesh quality summary:${NC}"

			if grep -q "Mesh OK" "$mesh_log" 2>/dev/null; then
				echo -e "${GREEN}  Status: Mesh OK${NC}"
			elif grep -q "Failed" "$mesh_log" 2>/dev/null; then
				echo -e "${RED}  Status: Mesh check FAILED${NC}"
			else
				echo -e "${YELLOW}  Status: Unknown (check log)${NC}"
			fi

			# Extract mesh statistics
			local cells=$(grep "cells:" "$mesh_log" 2>/dev/null | tail -1 | awk '{print $2}')
			local points=$(grep "points:" "$mesh_log" 2>/dev/null | tail -1 | awk '{print $2}')
			local faces=$(grep "internal faces:" "$mesh_log" 2>/dev/null | tail -1 | awk '{print $3}')

			if [[ -n "$cells" ]]; then
				echo "  Cells: $cells"
				echo "  Points: $points"
				echo "  Faces: $faces"
			fi
		fi
	else
		echo -e "${YELLOW}✗ Mesh not found in constant/polyMesh/${NC}"
		echo -e "  Run mesh generation first"
	fi

	# Check for processor directories (parallel mesh artifacts)
	local proc_dirs=$(find "$CASE_DIR" -maxdepth 1 -type d -name "processor*" 2>/dev/null | wc -l)
	if [[ $proc_dirs -gt 0 ]]; then
		echo ""
		echo -e "${YELLOW}! Warning: Found $proc_dirs processor directories${NC}"
		echo -e "  These should be cleaned up after mesh reconstruction"
		echo -e "  Run: rm -rf processor*"
	fi
}

check_solver_status() {
	print_header "Solver Status"

	local latest_log=$(ls -t "$LOG_DIR"/solver_*.out 2>/dev/null | head -1)

	if [[ -z "$latest_log" ]]; then
		echo -e "${YELLOW}No solver log files found${NC}"
		echo -e "Solver has not been run yet"
		exit 1
	fi

	echo -e "${CYAN}Log file: $(basename $latest_log)${NC}"
	echo ""

	# Check if solver is running
	if ps aux | grep -q "[s]impleFoam" 2>/dev/null; then
		echo -e "${GREEN}Status: RUNNING${NC}"
	else
		echo -e "${YELLOW}Status: NOT RUNNING (completed or not started)${NC}"
	fi

	echo ""
	echo -e "${CYAN}Latest residuals:${NC}"
	# Extract last few iterations
	grep "^Time = " "$latest_log" 2>/dev/null | tail -5 || echo "  No residual data found"

	echo ""
	echo -e "${CYAN}Solution convergence:${NC}"
	# Check for convergence or completion
	if grep -q "End" "$latest_log" 2>/dev/null; then
		echo -e "${GREEN}  Solver completed${NC}"
		local end_time=$(grep "ExecutionTime" "$latest_log" 2>/dev/null | tail -1)
		if [[ -n "$end_time" ]]; then
			echo "  $end_time"
		fi
	elif grep -q "solution singularity" "$latest_log" 2>/dev/null; then
		echo -e "${RED}  Solution diverged (singularity detected)${NC}"
	else
		echo -e "${YELLOW}  In progress or incomplete${NC}"
	fi

	# Check results directory
	if [[ -d "$CASE_DIR/postProcessing" ]]; then
		echo ""
		echo -e "${CYAN}Post-processing data:${NC}"
		ls -lh "$CASE_DIR/postProcessing" 2>/dev/null || echo "  Empty"
	fi
}

clean_logs() {
	print_header "Clean Old Logs"

	if [[ ! -d "$LOG_DIR" ]]; then
		echo "No logs directory found"
		return
	fi

	local archive_dir="$LOG_DIR/archive_$(date +%Y%m%d)"

	echo -e "${CYAN}Creating archive directory: $archive_dir${NC}"
	mkdir -p "$archive_dir"

	# Move logs older than 7 days
	local moved=0
	while IFS= read -r -d '' file; do
		mv "$file" "$archive_dir/"
		((moved++))
	done < <(find "$LOG_DIR" -maxdepth 1 -name "*.out" -o -name "*.log" -mtime +7 -print0 2>/dev/null)

	if [[ $moved -gt 0 ]]; then
		echo -e "${GREEN}Archived $moved old log files${NC}"
	else
		echo -e "${YELLOW}No logs older than 7 days found${NC}"
	fi
}

# Main
main() {
	local command="${1:-status}"

	case $command in
	status)
		show_queue
		;;
	logs)
		list_logs
		;;
	mesh-log)
		tail_mesh_log
		;;
	solver-log)
		tail_solver_log
		;;
	mesh-status)
		check_mesh_status
		;;
	solver-status)
		check_solver_status
		;;
	clean-logs)
		clean_logs
		;;
	-h | --help)
		show_help
		;;
	*)
		echo -e "${RED}Unknown command: $command${NC}"
		echo ""
		show_help
		exit 1
		;;
	esac
}

main "$@"
