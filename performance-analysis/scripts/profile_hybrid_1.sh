#!/bin/bash
#SBATCH --job-name=prof_1n
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=00:20:00
#SBATCH --output=profile_1.log

source /home/guest/init-hpc.sh

module load scalasca 2>/dev/null || echo "Scalasca module load failed"
module load scorep 2>/dev/null || echo "Score-P module load failed"

# Strumentazione e compilazione
make clean
make MPICC="scalasca -instrument mpicc" energy_storms_mpi_omp_9

export OMP_NUM_THREADS=32

# Esecuzione con tutti i 6 file del Test 02
scalasca -analyze mpirun -np 1 ./energy_storms_mpi_omp 20000 test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6
