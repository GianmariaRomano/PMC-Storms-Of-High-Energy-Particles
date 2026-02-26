# ☄ Storms of High-Energy Particles

This repository contains the project developed for the *Programmazione di Sistemi Multicore* exam of the **Informatica Course** at Sapienza Università di Roma during the Academic Year 2025/2026.

---

## 🚀 Project Overview

This project, which is based on the *EduHPC Peachy Parallel Assignments* competition held at Universidad de Valladolid in 2018, provides parallel implementations of a reference sequential code that simulates the effects of repeated high-energy particle storms on (a cross section of) an exposed surface.

In particular, the repository contains:
- A **hybrid OpenMP + MPI** implementation targeting distributed memory systems.
- A **CUDA** implementation designed for execution on NVIDIA GPUs.
---

## 📡 OpenMP + MPI Implementation

The implementation provided in the `energy_storms_mpi_omp_core.c` file uses a hybrid approach that aims to maximize hardware utilization across nodes and cores.

- **Workload distribution:** Perform a domain decomposition by partitioning the input array among MPI processes, handling unevenness using rank-based offset logic.
- **Communication:** Optimize halo exchanges using non-blocking communication functions to handle boundary cells during the relaxation phase.
- **Memory optimization:** Implement a pointer swapping technique between the layer and an ancillary buffer to eliminate unnecessary memory copies and use `posix_memalign` to improve memory alignment for cache-friendly behaviour.
- **Thread-level parallelism:** OpenMP threads use guided scheduling to balance uneven workload and exploit SIMD vectorization to achieve better performance.
- **Global synchronization:** Use `MPI_Allreduce` with the `MPI_MAXLOC` operator to efficiently find the global maximum energy and its position across all chunks.

---

## 🛰 CUDA Implementation

The implementation provided in the `energy_storms_cuda_core.cu` file aims to provide high-throughput data parallelism and memory bandwidth optimization.
- **Massively parallel kernels:** Implement a grid-stride pattern to allow the GPU to process every cell in the array simultaneously, with each thread iterating through storm particles to maintain high occupancy.
- **Shared memory relaxation:** Accelerate the 3-point stencil relaxarion by loading data into the on-chip shared memory, reducing global memory latency and redundant reads.
- **Parallel tree reduction:** Finding the maximum energy is implemented via a two stage warp-synchronous reduction.
  1) A local reduction per block finds candidate maxima.
  2) A global reduction kernel identifies the absolute maximum value and its position.
- **Resource management:** Minimize host-to-device overhead by keeping the array on the GPU during the simulation, copying just the final global results back to the CPU.

---

## 🌍 Results

The performance evaluation at the end of the project will include a comparison between sequential and parallel implementations, along with performance analysis and bottleneck discussions.

Detailed results and plots will be available in the `report.pdf` file.

---
