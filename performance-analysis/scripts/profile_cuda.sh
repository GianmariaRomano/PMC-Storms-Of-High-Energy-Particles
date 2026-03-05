#!/bin/bash
#SBATCH --job-name=prof_cuda
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:15:00
#SBATCH --output=profile_nsys_%j.log

source /home/guest/init-hpc.sh

# 1. Compilazione standard (come hai sempre fatto)
make clean
make energy_storms_cuda_new

# 2. Esecuzione con Nsight Systems
# --stats=true genera un riepilogo testuale simile a nvprof nel file .log
# -o definisce il nome del file di report che potrai aprire con la GUI
nsys profile --stats=true -o report_test02 ./energy_storms_cuda 20000 test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6
