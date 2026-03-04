#!/bin/bash
#SBATCH --job-name=hybrid_4nodes
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --time=00:30:00
#SBATCH --exclusive=user
#SBATCH --output=report5/hybrid4/slurm_%j.log

source /home/guest/init-hpc.sh
export UCX_TLS=^xpmem

make clean
make energy_storms_mpi_omp

if [ $? -ne 0 ]; then
    echo "Error compiling OpenMP+MPI. Exiting now."
    exit 1
fi

OUTDIR="report/hybrid4"
mkdir -p "$OUTDIR"
FILE="$OUTDIR/data_hybrid_4.csv"
NUM_RUNS=5
THREAD_COUNTS=(1 2 4 8 16 32)

echo "test,threads,r1,r2,r3,r4,r5,min,max,avg,std" > "$FILE"

TESTS=(
    "test_01:35:5-8:4:test_files/test_01_a35_p5_w3 test_files/test_01_a35_p7_w2 test_files/test_01_a35_p8_w1 test_files/test_01_a35_p8_w4"
    "test_02:20000:20000:6:test_files/test_02_a30k_p20k_w1 test_files/test_02_a30k_p20k_w2 test_files/test_02_a30k_p20k_w3 test_files/test_02_a30k_p20k_w4 test_files/test_02_a30k_p20k_w5 test_files/test_02_a30k_p20k_w6"
    "test_03:20:4:1:test_files/test_03_a20_p4_w1"
    "test_04:20:4:1:test_files/test_04_a20_p4_w1"
    "test_05:20:4:1:test_files/test_05_a20_p4_w1"
    "test_06:20:4:1:test_files/test_06_a20_p4_w1"
    "test_07:1000000:5000:4:test_files/test_07_a1M_p5k_w1 test_files/test_07_a1M_p5k_w2 test_files/test_07_a1M_p5k_w3 test_files/test_07_a1M_p5k_w4"
    "test_08:100000000:1:3:test_files/test_08_a100M_p1_w1 test_files/test_08_a100M_p1_w2 test_files/test_08_a100M_p1_w3"
    "test_09:16:3:1:test_files/test_09_a16-17_p3_w1"
)

for ts in "${TESTS[@]}"; do
    IFS=':' read -r name size part storm files <<< "$ts"
    for nt in "${THREAD_COUNTS[@]}"; do
        export OMP_NUM_THREADS=$nt
        times=()
        for ((r=0; r<NUM_RUNS; r++)); do
            # Lancio su 4 nodi, 1 processo per nodo
            t=$(mpirun -np 4 --map-by node ./energy_storms_mpi_omp "$size" $files | grep -oP 'Time: \K[0-9.]+')
            times+=($t)
        done
        stats=$(echo "${times[@]}" | awk '{
            sum=0; min=1e18; max=-1e18;
            for(i=1; i<=NF; i++) { v[i]=$i; sum+=$i; if($i<min) min=$i; if($i>max) max=$i; }
            avg=sum/NF; ss=0; for(i=1; i<=NF; i++) ss+=(v[i]-avg)^2;
            printf "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f", v[1], v[2], v[3], v[4], v[5], min, max, avg, sqrt(ss/NF)
        }')
        echo "$name,$nt,$stats" >> "$FILE"
    done
done
