#!/bin/bash

# Definisci il percorso dei file
DATA_DIR="./profiling/cuda"
OUTPUT_CSV="summary_cuda_stats.csv"
TEMP_FILE="temp_stats.txt"

echo "Avvio estrazione dati da $DATA_DIR..."
echo "test,block_size,op_htod_ms,op_dtod_ms,op_dtoh_ms,total_mb,throughput_gbs" > "$OUTPUT_CSV"
> "$TEMP_FILE"

# Verifica se la cartella esiste
if [ ! -d "$DATA_DIR" ]; then
    echo "ERRORE: La cartella $DATA_DIR non esiste!"
    exit 1
fi

# Ciclo sui file nella sottocartella
for file in "$DATA_DIR"/stats_test_*.txt; do
    [ -f "$file" ] || continue
    
    filename=$(basename "$file")
    echo "Processando $filename..."
    
    # Estrazione metadati dal nome file
    test_id=$(echo "$filename" | cut -d'_' -f3)
    test_name="test_$test_id"
    bs=$(echo "$filename" | sed -n 's/.*_bs\([0-9]*\)\.txt/\1/p')

    # Estrazione tempi: cerchiamo la riga, prendiamo la colonna 2, togliamo le virgole
    # Poi dividiamo per 1.000.000 (ns -> ms)
    htod=$(grep "Host-to-Device" "$file" | awk '{print $2}' | tr -d ',' | awk '{if($1=="") print 0; else printf "%.6f", $1/1000000}')
    dtod=$(grep "Device-to-Device" "$file" | awk '{print $2}' | tr -d ',' | awk '{if($1=="") print 0; else printf "%.6f", $1/1000000}')
    dtoh=$(grep "Device-to-Host" "$file" | awk '{print $2}' | tr -d ',' | awk '{if($1=="") print 0; else printf "%.6f", $1/1000000}')

    # Estrazione MB totali dalla tabella cuda_gpu_mem_size_sum
    total_mb=$(grep -A 8 "cuda_gpu_mem_size_sum" "$file" | grep -E "Device|Host" | awk '{print $1}' | tr -d ',' | awk '{sum+=$1} END {print (sum==""?0:sum)}')

    # Calcolo Throughput (GB/s)
    throughput=$(echo "$htod $dtod $dtoh $total_mb" | awk '{
        time_sec = ($1+$2+$3)/1000;
        if (time_sec > 0) 
            printf "%.4f", ($4/1024)/time_sec;
        else 
            print 0;
    }')

    # Salvataggio temporaneo per ordinamento (BS a 3 cifre)
    printf "%s %03d %s %s %s %s %s\n" "$test_name" "$bs" "$htod" "$dtod" "$dtoh" "$total_mb" "$throughput" >> "$TEMP_FILE"
done

# Ordinamento e formattazione finale
if [ -s "$TEMP_FILE" ]; then
    sort -k1,1 -k2,2n "$TEMP_FILE" | awk '{print $1 "," int($2) "," $3 "," $4 "," $5 "," $6 "," $7}' >> "$OUTPUT_CSV"
    echo "--------------------------------------"
    echo "Fatto! Creato $OUTPUT_CSV con $(($(wc -l < $OUTPUT_CSV) - 1)) record."
else
    echo "ERRORE: Nessun dato estratto. Controlla il formato dei file .txt"
fi

rm -f "$TEMP_FILE"
