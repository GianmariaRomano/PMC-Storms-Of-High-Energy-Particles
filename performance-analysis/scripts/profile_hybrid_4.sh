#!/bin/bash
#SBATCH --job-name=prof_4n
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --time=00:20:00
#SBATCH --output=profile_4.log

source /home/guest/init-hpc.sh

module load scalasca scorep 2>/dev/null

make clean
make MPICC="scalasca -instrument mpicc" energy_storms_mpi_omp_9

export OMP_NUM_THREADS=32

# Esecuzione distribuita su 4 nodi
scalasca -analyze mpirun -np 4 --map-by node ./energy_storms_mpi_omp 20000 test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6
