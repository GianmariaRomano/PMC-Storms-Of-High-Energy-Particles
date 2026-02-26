#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cuda.h>
#include "energy_storms.h"

/* THIS FUNCTION CAN BE MODIFIED */
/* Function to update a single position of the layer */
__device__ static void update( float *layer, int layer_size, int k, int pos, float energy ) {
    /* 1. Compute the absolute value of the distance between the
        impact position and the k-th position of the layer */
    int distance = pos - k;
    if ( distance < 0 ) distance = - distance;

    /* 2. Impact cell has a distance value of 1 */
    distance = distance + 1;

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

/* Kernel to update positions during the bombardment phase
To avoid computational bottlenecks, this version tries to process all particles of a storm at once */
__global__ void update_storm(float *layer, int layer_size, int *posval, int particles) {
    int k = blockIdx.x * blockDim.x + threadIdx.x; // Get cell position.
    if (k < layer_size) {
        /* Keep working on cell k by doing each single update */
        for (int p = 0; p < particles; p++) {
            /* Get particle information */
            int position = posval[p * 2]; // Get particle position.
            float energy = (float)posval[p * 2 + 1] * 1000; // Get particle energy.
            update(layer, layer_size, k, position, energy);
        }
    }
}

/* Relaxation kernel
For better performance, the shared memory is used */
__global__ void relaxation(float *layer, float *layer_copy, int layer_size) {
    extern __shared__ float shared_data[]; // extern is used for run-time allocation.
    int thread_id = threadIdx.x;
    int k = blockIdx.x * blockDim.x + threadIdx.x; // Get cell position.

    if (k < layer_size) {
        shared_data[thread_id + 1] = layer_copy[k]; // Take the value corresponding to position k.
        /* Take the neighbouring values */
        if (thread_id == 0) {
            /* First thread in the block
            Here, cell 0 (first cell of the first block) must be handled separately */
            if (k > 0) {
                shared_data[0] = layer_copy[k - 1]; // Take the value of the left neighbour.
            } else {
                shared_data[0] = 0.0f; // Use a placeholder as cell 0 does not have a left neighbour.
            }
        }
        if (thread_id == blockDim.x - 1 || k == layer_size - 1) {
            /* Last thread in the block
            Here, the problem lies in taking the right neighbour as it is located on a different block.
            Furthermore, cell layer_size - 1 (last cell of the last block) must be handled separately */
            if (k < layer_size - 1) {
                shared_data[thread_id + 2] = layer_copy[k + 1]; // Take the value of the right neighbour.
            } else {
                shared_data[thread_id + 2] = 0.0f; // Use a placeholder as cell layer_size - 1 does not have a right neighbour.
            }
        }
    } else {
        shared_data[thread_id + 1] = 0.0f; // Use a placeholder value for the invalid position.
    }

    __syncthreads(); // Synchronization point before the relaxation step.

    /* Relaxation step */
    if (k > 0 && k < layer_size - 1) {
        /* Skip updating the first and last cells */
        layer[k] = (shared_data[thread_id] + shared_data[thread_id + 1] + shared_data[thread_id + 2]) / 3;
    }
}

/* Reduction kernel to find the local maximum within a block */
__global__ void local_max_reduction(float *layer, float *max_val, int *max_pos, int layer_size) {
    extern __shared__ float shared_max[];
    int *shared_pos = (int *)&shared_max[blockDim.x]; // Partition the allocated memory between shared_max (array of floats) and shared_pos (array of ints) between arrays of the same size.

    int thread_id = threadIdx.x;
    int k = blockIdx.x * blockDim.x + threadIdx.x;

    /* Initialization step */
    shared_max[thread_id] = -1.0f;
    shared_pos[thread_id] = -1;

    /* Initial load of the local maxima */
    if (k > 0 && k < layer_size - 1) {
        /* Check it only if it is a local maximum */
        if (layer[k] > layer[k - 1] && layer[k] > layer[k + 1]) {
            shared_max[thread_id] = layer[k];
            shared_pos[thread_id] = k;
        }
    }

    __syncthreads();

    /* Tree reduction using the shared memory
    This is carried out by performing a right shift (divide by 2) on the stride until the local maximum is found */
    for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (thread_id < s) {
            if (shared_max[thread_id + s] > shared_max[thread_id]) {
                shared_max[thread_id] = shared_max[thread_id + s];
                shared_pos[thread_id] = shared_pos[thread_id + s];
            }
        }
        __syncthreads();
    }

    /* Thread 0 writes the local maximum and its position in the corresponding slots */
    if (thread_id == 0) {
        max_val[blockIdx.x] = shared_max[0];
        max_pos[blockIdx.x] = shared_pos[0];
    }
}

/* Reduction kernel to find the global maximum */
__global__ void global_max_reduction(float *block_max_val, int *block_max_pos, float *global_max_val, int *global_max_pos, int n_blocks) {
    extern __shared__ float shared_maximum[];
    int *shared_position = (int *)&shared_maximum[blockDim.x];

    int thread_id = threadIdx.x;
    int k = blockDim.x * blockIdx.x + threadIdx.x;

    /* Initialization step */
    shared_maximum[thread_id] = -1.0f;
    shared_position[thread_id] = -1;

    /* Initial load of the maxima (useful if, for large arrays, there are more local blocks than threads) */
    for (int i = thread_id; i < n_blocks; i += blockDim.x) {
        /* Load only if it is a potential maximum */
        if (block_max_val[i] > shared_maximum[thread_id]) {
            shared_maximum[thread_id] = block_max_val[i];
            shared_position[thread_id] = block_max_pos[i];
        }
    }

    __syncthreads();

    /* Tree reduction using the shared memory */
    for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (thread_id < s) {
            if (shared_maximum[thread_id + s] > shared_maximum[thread_id]) {
                shared_maximum[thread_id] = shared_maximum[thread_id + s];
                shared_position[thread_id] = shared_position[thread_id + s];
            }
        }
        __syncthreads();
    }
    /* Thread 0 writes the global maximum and its position in the corresponding slots */
    if (thread_id == 0) {
        *global_max_val = shared_maximum[0];
        *global_max_pos = shared_position[0];
    }
}

void core(int layer_size, int num_storms, Storm *storms, float *maximum, int *positions) {
    int i;

    /* Define the number of threads per block and, as such, the number of threads to use */
    const int BLOCK_SIZE = 256;
    int n_blocks = (layer_size + BLOCK_SIZE - 1) / BLOCK_SIZE;

    /* 3. Allocate memory for the layer and initialize to zero 
          Make some adjustments for CUDA memory management on the GPU */
    float *device_layer, *device_layer_copy; // GPU arrays for computations.
    float *device_max_val; // GPU array for storing the local maxima.
    int *device_max_pos; // GPU array for storing the positions of the local maxima.

    cudaMalloc(&device_layer, sizeof(float) * layer_size); // Allocation for the GPU array.
    cudaMalloc(&device_layer_copy, sizeof(float) * layer_size); // Allocation for the GPU ancillary array.
    cudaMalloc(&device_max_val, sizeof(float) * n_blocks);
    cudaMalloc(&device_max_pos, sizeof(int) * n_blocks);
    cudaMemset(device_layer, 0, sizeof(float) * layer_size); // Initialization to 0 for the GPU array.

    float *device_global_max_val; // GPU array of size one storing the global maximum's value.
    int *device_global_max_pos; // GPU array of size one storing the global maximum's position.
    cudaMalloc(&device_global_max_val, sizeof(float));
    cudaMalloc(&device_global_max_pos, sizeof(int));

    /* To reduce overhead, create a new array to store information about storms
    For simplicity, the maximum amount of memory needed is considered to avoid problems like trying to access an illegal address */
    int max_particles = 0; // Initialize the maximum number of particles to determine the array size.
    for (i = 0; i < num_storms; i++) {
        if (storms[i].size > max_particles) {
            max_particles = storms[i].size;
        }
    }
    int *device_storm_particles; // GPU array storing storm information.
    cudaMalloc(&device_storm_particles, sizeof(int) * max_particles * 2); // Allocation for the storm array (position and energy).
    
    /* 4. Storms simulation */
    for( i=0; i<num_storms; i++) {
        /* Start by copying the current storm on the GPU */
        cudaMemcpy(device_storm_particles, storms[i].posval, storms[i].size * 2 * sizeof(int), cudaMemcpyHostToDevice);

        /* 4.1. Add impacts energies to layer cells */
        update_storm<<<n_blocks, BLOCK_SIZE>>>(device_layer, layer_size, device_storm_particles, storms[i].size);

        /* 4.2. Energy relaxation between storms */
        /* 4.2.1. Copy values to the ancillary array */
        cudaMemcpy(device_layer_copy, device_layer, sizeof(float) * layer_size, cudaMemcpyDeviceToDevice); // Copy the energy amounts on the ancillary GPU array.

        /* 4.2.2. Update layer using the ancillary values.
                  Skip updating the first and last positions */
        
        size_t shared_memory_size_relaxation = (BLOCK_SIZE + 2) * sizeof(float); // Size of the shared memory to allocate (BLOCK_SIZE + 2) comes from handling boundary values for each block.
        relaxation<<<n_blocks, BLOCK_SIZE, shared_memory_size_relaxation>>>(device_layer, device_layer_copy, layer_size); // Execution using shared memory.

        /* 4.3. Locate the maximum value in the layer, and its position
                To improve efficiency, the GPU carries out a tree reduction to find the local maxima of each block
                Then, the GPU carries out another tree reduction to find the global maximum */
        size_t shared_memory_size_max_reduction = BLOCK_SIZE * (sizeof(float) + sizeof(int)); // Size of the shared memory to allocated.
        local_max_reduction<<<n_blocks, BLOCK_SIZE, shared_memory_size_max_reduction>>>(device_layer, device_max_val, device_max_pos, layer_size);
        global_max_reduction<<<1, BLOCK_SIZE, shared_memory_size_max_reduction>>>(device_max_val, device_max_pos, device_global_max_val, device_global_max_pos, n_blocks);

        /* Copy the global maximum and its position on the CPU */
        cudaMemcpy(&maximum[i], device_global_max_val, sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(&positions[i], device_global_max_pos, sizeof(int), cudaMemcpyDeviceToHost);
    }
    /* Free up the allocated memory at the end */
    cudaFree(device_layer);
    cudaFree(device_layer_copy);
    cudaFree(device_max_val);
    cudaFree(device_max_pos);
    cudaFree(device_global_max_val);
    cudaFree(device_global_max_pos);
    cudaFree(device_storm_particles);
}
