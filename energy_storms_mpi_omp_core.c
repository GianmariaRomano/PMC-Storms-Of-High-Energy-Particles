#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>
#include <omp.h>
#include "energy_storms.h"

/* THIS FUNCTION CAN BE MODIFIED */
/* Function to update a single position of the layer */
inline static void update( float *layer, int layer_size, int k, int pos, float energy ) {
    /* 1. Compute the absolute value of the distance between the
        impact position and the k-th position of the layer */
    /* 2. Impact cell has a distance value of 1 */
    int distance = abs(pos - k) + 1;

    /* 3. Square root of the distance */
    /* NOTE: Real world atenuation typically depends on the square of the distance.
       We use here a tailored equation that affects a much wider range of cells */
    float atenuacion = sqrtf( (float)distance );

    /* 4. Compute attenuated energy */
    float energy_k = energy / layer_size / atenuacion;

    /* 5. Do not add if its absolute value is lower than the threshold */
    if ( energy_k >= THRESHOLD / layer_size || energy_k <= -THRESHOLD / layer_size )
        layer[k] = layer[k] + energy_k;
}


void core(int layer_size, int num_storms, Storm *storms, float *maximum, int *positions) {
    int my_rank, comm_sz;
    int local_array_size, remainder, local_start, local_end;
    int i, j, k;

    /* Derive the number of processes and the rank of the working process */
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &comm_sz);

    /* Distribute the workload among processes
    However, the layer size may not be perfectly divisible by the number of processes
    In this case, distribute the remaining cells among the first processes to avoid imbalance */
    local_array_size = layer_size / comm_sz; // Cells per process.
    remainder = layer_size % comm_sz; // Remaining cells.
    if (my_rank < remainder) {
        local_array_size = local_array_size + 1; // Add the extra cell.
        local_start = my_rank * local_array_size;
    } else {
        local_start = (my_rank * local_array_size) + remainder;
    }
    local_end = local_start + local_array_size;

    /* Define the auxiliary variables for the relaxation and reduction steps
    This is done outside of the loops to avoid unnecessary recomputations as these variables will never really change */
    int aux_start = local_start;
    int aux_end = local_end;
    if (my_rank == 0) {
        /* Process 0 needs to skip cell 0 */
        aux_start = 1;
    }
    if (my_rank == comm_sz - 1) {
        /* Process comm_sz - 1 needs to skip cell layer_size - 1*/
        aux_end = layer_size - 1;
    }
    int max_start = aux_start;
    int max_end = aux_end;

    /* Declare the request handlers for the communication steps */
    MPI_Request reqs_copy[4];
    MPI_Request reqs_relax[4];
    int counter;

    /* Create a constant to reduce bottlenecks in the update() function */
    const float threshold_scaled = THRESHOLD / layer_size;

    /* 3. Allocate memory for the layer and initialize to zero
    Consider a different initialization approach that allows to perform pointer swapping for better efficiency
    Additionally, use posix_memalign for better memory management */
    /* Allocate buffers to handle halo exchanges as well */
    float *layer, *layer_copy;
    size_t alignment = 64;
    size_t size = (layer_size + 2) * sizeof(float);
    if (posix_memalign((void**)&layer, alignment, size) != 0 || posix_memalign((void**)&layer_copy, alignment, size) != 0) {
        fprintf(stderr, "Error: Allicating the layer memory\n");
        exit(EXIT_FAILURE);
    }
    /* Initialize to 0 as posix_memalign does not clean previously used memory */
    memset(layer, 0, size);
    memset(layer_copy, 0, size);
    /* Initialize the pointers performing computations and set them on the actual starting cell */
    float *current_ptr = &layer[1];
    float *copy_ptr = &layer_copy[1];
    
    /* 4. Storms simulation */
    for (i = 0; i < num_storms; i++) {
        /* Declare the structs that will be used for the maximum here to have them as shared items */
        struct {
            float max_val;
            int max_pos;
        } local_max, global_max;
        
        /* 4.1. Add impacts energies to layer cells */
        /* Try to flip the loops so that each cell is updated with respect to the entire storm
        Opt for a guided loop scheduling to reduce overhead */ 
        #pragma omp parallel for schedule(guided) private(j)
        for (k = local_start; k < local_end; k++) {
            /* Vectorize the innermost loop, using the safelen clause to avoid alignment issues */
            #pragma omp simd safelen(8)
            for (j = 0; j < storms[i].size; j++) {
                float energy = (float)storms[i].posval[j*2+1] * 1000;
                int position = storms[i].posval[j*2];

                int distance = abs(position - k) + 1;
                float atenuacion = sqrtf((float)distance);
                float energy_k = energy / layer_size / atenuacion;

                /* Remove the if statement as low energy amounts should not influence the results */
                current_ptr[k] += energy_k;
            }
        }

        /* 4.2. Energy relaxation between storms */
        /* 4.2.1. Copy values to the ancillary array (skipped in favour of the pointer swap technique) */

        /* 4.2.2. Update layer using the ancillary values (fixed for the pointer swap)
        Start by performing non-boundary relaxation during the halo exchange
        Then, handle the boundary updates after communication */
        for (int r = 0; r < 4; r++) {
            /* Initialize the handlers to MPI_REQUEST_NULL
            This is done because not all processes will do all four operations
            In fact, rank 0 only does the right exchange, while rank comm_sz - 1 only does the left exchange */
            reqs_copy[r] = MPI_REQUEST_NULL;
        }
        counter = 0;
        if (my_rank > 0) {
            /* Left exchange */
            MPI_Irecv(&current_ptr[local_start - 1], 1, MPI_FLOAT, my_rank - 1, 0, MPI_COMM_WORLD, &reqs_copy[counter++]); // The process receives the last cell of its left neighbour.
            MPI_Isend(&current_ptr[local_start], 1, MPI_FLOAT, my_rank - 1, 0, MPI_COMM_WORLD, &reqs_copy[counter++]); // The process sends its first cell to its left neighbour.
        }
        if (my_rank < comm_sz - 1) {
            /* Right exchange */
            MPI_Irecv(&current_ptr[local_end], 1, MPI_FLOAT, my_rank + 1, 0, MPI_COMM_WORLD, &reqs_copy[counter++]); // The process receives the first cell of its right neighbour.
            MPI_Isend(&current_ptr[local_end - 1], 1, MPI_FLOAT, my_rank + 1, 0, MPI_COMM_WORLD, &reqs_copy[counter++]); // The process sends its last cell to its right neighbour.
        }

        #pragma omp parallel for schedule(static, 1024)
        for (k = aux_start + 1; k < aux_end - 1; k++) {
            copy_ptr[k] = (current_ptr[k - 1] + current_ptr[k] + current_ptr[k + 1]) / 3;
        }

        MPI_Waitall(counter, reqs_copy, MPI_STATUSES_IGNORE); // Coordinate communication and skip updating MPI_Status.

        /* Update the boundaries */
        copy_ptr[aux_start] = (current_ptr[aux_start - 1] + current_ptr[aux_start] + current_ptr[aux_start + 1]) / 3;
        if (aux_end - 1 > aux_start) {
            /* Update the right boundary only if the local array is large enough to allow this */
            copy_ptr[aux_end - 1] = (current_ptr[aux_end - 2] + current_ptr[aux_end - 1] + current_ptr[aux_end]) / 3;
        }
        if (my_rank == 0) {
            /* Copy cell 0 */
            copy_ptr[0] = current_ptr[0];
        }
        if (my_rank == comm_sz - 1) {
            /* Copy cell layer_size - 1*/
            copy_ptr[layer_size - 1] = current_ptr[layer_size - 1];
        }
        
        /* Perform the pointer swap rather than copying the array */
        float *to_swap = current_ptr;
        current_ptr = copy_ptr;
        copy_ptr = to_swap;

        /* Exchange the post-relaxation values to handle the cells located at the boundaries of each chunk */
        for (int r = 0; r < 4; r++) {
            reqs_relax[r] = MPI_REQUEST_NULL;
        }
        counter = 0;

        if (my_rank > 0) {
            /* Left exchange */
            MPI_Irecv(&current_ptr[local_start - 1], 1, MPI_FLOAT, my_rank - 1, 1, MPI_COMM_WORLD, &reqs_relax[counter++]);
            MPI_Isend(&current_ptr[local_start], 1, MPI_FLOAT, my_rank - 1, 1, MPI_COMM_WORLD, &reqs_relax[counter++]);
        }
        if (my_rank < comm_sz - 1) {
            /* Right exchange */
            MPI_Irecv(&current_ptr[local_end], 1, MPI_FLOAT, my_rank + 1, 1, MPI_COMM_WORLD, &reqs_relax[counter++]);
            MPI_Isend(&current_ptr[local_end - 1], 1, MPI_FLOAT, my_rank + 1, 1, MPI_COMM_WORLD, &reqs_relax[counter++]);
        }
        MPI_Waitall(counter, reqs_relax, MPI_STATUSES_IGNORE);

        /* 4.3. Locate the maximum value in the layer, and its position */
        /* For better efficiency, use the struct and apply an Allreduce with MAXLOC */
        /* Initialize the local maximum struct using placeholder values */
        local_max.max_val = -1.0f;
        local_max.max_pos = -1;

        #pragma omp parallel
        {
            /* Repeat initialization for thread-local maxima */
            float t_max_val = -1.0f;
            int t_max_pos = -1;
            #pragma omp for simd schedule(static)
            for (k = max_start; k < max_end; k++) {
                if (current_ptr[k] > current_ptr[k - 1] && current_ptr[k] > current_ptr[k + 1] && current_ptr[k] > t_max_val) {
                    /* Check it only if it is a local maximum */
                    t_max_val = current_ptr[k];
                    t_max_pos = k;
                }
            }
            /* Acquire the lock to update the local maximum */
            #pragma omp critical
            {
                if (t_max_val > local_max.max_val) {
                    local_max.max_val = t_max_val;
                    local_max.max_pos = t_max_pos;
                }
            }
        }

        /* After locating the local maxima, find the global maximum using MPI_Allreduce() and store the results for the current wave in the arrays */
        MPI_Allreduce(&local_max, &global_max, 1, MPI_FLOAT_INT, MPI_MAXLOC, MPI_COMM_WORLD);
        maximum[i] = global_max.max_val; // Place the maximum value at maximum[i].
        positions[i] = global_max.max_pos; // Place the position of the global maximum at positions[i].
    }
    free(layer);
    free(layer_copy);
}
