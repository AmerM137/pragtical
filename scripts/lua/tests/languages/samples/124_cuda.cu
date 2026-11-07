#include <cuda_runtime.h>
#include <cstdio>

#define CHECK(call) do { cudaError_t err = (call); if (err != cudaSuccess) return 1; } while (0)

__constant__ float scale = 2.0f;

template <typename T>
__global__ void saxpy(int n, T a, const T* __restrict__ x, T* y) {
  __shared__ T tile[256];
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    tile[threadIdx.x] = x[i];
    __syncthreads();
    y[i] = a * tile[threadIdx.x] * scale + y[i];
  }
}

__device__ __forceinline__ float square(float v) { return v * v; }

int main() {
  const int n = 1 << 20;
  float *x = nullptr, *y = nullptr;
  CHECK(cudaMalloc(&x, n * sizeof(float)));
  CHECK(cudaMallocManaged(&y, n * sizeof(float)));
  dim3 block(256), grid((n + block.x - 1) / block.x);
  saxpy<float><<<grid, block, 0, cudaStreamDefault>>>(n, 3.0f, x, y);
  CHECK(cudaDeviceSynchronize());
  printf("done: %s\n", cudaGetErrorString(cudaGetLastError()));
  cudaFree(x); cudaFree(y);
  return 0;
}
