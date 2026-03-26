#!/bin/bash
#SBATCH --job-name=prof_1n
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=00:30:00
#SBATCH --output=profiling/hybrid1p/slurm_%j.log

source /home/guest/init-hpc.sh
mkdir -p profiling/hybrid1p

export OMP_PROC_BIND=close
export OMP_PLACES=cores
PERF_EVENTS="cpu-clock,task-clock,context-switches,cpu-migrations,page-faults,cycles,instructions,branches,branch-misses,L1-dcache-loads,L1-dcache-load-misses"

THREAD_COUNTS=(1 2 4 8 16 32)
TESTS=(
    "test_02:20000:test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6"
    "test_07:1000000:test_files/test_07_a1M_p5k_w1 test_files/test_07_a1M_p5k_w2 test_files/test_07_a1M_p5k_w3 test_files/test_07_a1M_p5k_w4"
    "test_08:100000000:test_files/test_08_a100M_p1_w1 test_files/test_08_a100M_p1_w2 test_files/test_08_a100M_p1_w3"
)

make clean
make energy_storms_mpi_omp
for test_spec in "${TESTS[@]}"; do
    IFS=':' read -r name size files <<< "$test_spec"
    for nt in "${THREAD_COUNTS[@]}"; do
        export OMP_NUM_THREADS=$nt
        perf stat -e $PERF_EVENTS mpirun -np 1 --bind-to none \
            ./energy_storms_mpi_omp "$size" $files > "profiling/hybrid1p/perf_${name}_t${nt}.txt" 2>&1
    done
done
