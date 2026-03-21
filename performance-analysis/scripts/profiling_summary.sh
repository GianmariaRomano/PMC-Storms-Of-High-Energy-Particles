#!/bin/bash

HYBRID_CSV="summary_hybrid.csv"
CUDA_CSV="summary_cuda.csv"

echo "test,type,threads,time_sec,ipc,l1_misses" > "$HYBRID_CSV"
echo "test,block_size,avg_time_ns" > "$CUDA_CSV"

echo "--- OpenMP+MPI Summary ---"
for dir in profiling/hybrid1p profiling/hybrid4p; do
    [ -d "$dir" ] || continue
    type=$(basename "$dir")
    ls "$dir"/perf_test_*.txt 2>/dev/null | sort -V | while read -r file; do
        test_name=$(basename "$file" | cut -d'_' -f2,3)
        threads=$(basename "$file" | sed -n 's/.*_t\([0-9]*\)\.txt/\1/p')
        time=$(grep "seconds time elapsed" "$file" | awk '{print $1}' | tr ',' '.')
        ipc=$(grep "insn per cycle" "$file" | awk '{print $4}' | tr ',' '.')
        l1_misses=$(grep "L1-dcache-load-misses" "$file" | awk '{print $1}' | tr -d '.' | tr ',' '.')
        echo "$test_name,$type,$threads,$time,$ipc,$l1_misses" >> "$HYBRID_CSV"
    done
done

echo "--- CUDA Summary ---"
ls profiling/cuda/stats_test_*.txt 2>/dev/null | sort -V | while read -r file; do
    test_name=$(basename "$file" | cut -d'_' -f2,3)
    bs=$(basename "$file" | sed -n 's/.*_bs\([0-9]*\)\.txt/\1/p')
    
    # Estrazione con AWK:
    # Cerchiamo la prima riga di dati dopo una qualsiasi tabella di statistiche (Kernel o Memcpy)
    # che contenga un valore numerico nella colonna della media.
    avg_val=$(awk '
        # Se troviamo una riga con Avg (ns), la riga successiva di dati e quella dopo i trattini
        /Avg \(ns\)/ { check=1; next }
        check == 1 && /---/ { check=2; next }
        check == 2 && /^[ ]*[0-9]/ {
            val = $4; # Di solito e la quarta o quinta colonna
            # Pulizia radicale: togliamo punti (migliaia) e cambiamo virgola in punto
            gsub(/\./, "", val);
            gsub(/,/, ".", val);
            print val;
            exit;
        }
    ' "$file")

    # Se ancora vuoto, proviamo a prendere il tempo totale del test riportato in alto nel file
    if [ -z "$avg_val" ]; then
        avg_val=$(grep "Time:" "$file" | awk '{print $2}' | tr ',' '.')
    fi

    echo "$test_name,$bs,${avg_val:-N/A}" >> "$CUDA_CSV"
done

echo "Summary completed! The results are available at summary_hybrid.csv and summary_cuda.csv!"
