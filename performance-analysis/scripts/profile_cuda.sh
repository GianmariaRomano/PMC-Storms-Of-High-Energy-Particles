#!/bin/bash
#SBATCH --job-name=prof_cuda
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00
#SBATCH --output=profiling/cuda/slurm_%j.log

source /home/guest/init-hpc.sh
mkdir -p profiling/cuda

BLOCK_SIZES=(32 64 128 256 512)
TESTS=(
    "test_02:20000:test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6"
    "test_07:1000000:test_files/test_07_a1M_p5k_w1 test_files/test_07_a1M_p5k_w2 test_files/test_07_a1M_p5k_w3 test_files/test_07_a1M_p5k_w4"
    "test_08:100000000:test_files/test_08_a100M_p1_w1 test_files/test_08_a100M_p1_w2 test_files/test_08_a100M_p1_w3"
)

for test_spec in "${TESTS[@]}"; do
    IFS=':' read -r name size files <<< "$test_spec"
    for bs in "${BLOCK_SIZES[@]}"; do
        make clean >/dev/null
        make energy_storms_cuda_new CUDA_EXTRA_CFLAGS="-DBLOCK_SIZE=$bs" >/dev/null

        # Genera il report .nsys-rep e il log testuale dei kernel
        nsys profile --stats=true --force-overwrite=true \
            -o "profiling/cuda/nsys_${name}_bs${bs}" \
            ./energy_storms_cuda_new "$size" $files > "profiling/cuda/stats_${name}_bs${bs}.txt" 2>&1
    done
done
