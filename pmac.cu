#include <iostream>
#include <iomanip>
#include <fstream>
#include <vector>
#include "aes.h"


using namespace std;


__global__ void first(uint8_t* d_message, uint8_t* d_key1, int* d_key2, uint8_t* d_cipher){ 

  __shared__ uint8_t cipher[16];

  // parallal part
  uint8_t message_block[16];
  int value = ((*d_key2)*(threadIdx.x))%1000000007;
  for(size_t i = 0; i < 16; ++i){
    message_block[i] = d_message[threadIdx.x*16+i]; 
    message_block[i] ^= ((value >> (i * 8)) & 0xFF);
  }
  uint8_t *cipher_block;

  AES aes(AESKeyLength::AES_128);
  cipher_block = aes.EncryptECB(message_block, 16, d_key1);

  for(size_t i = 0; i < 16; ++i){
    cipher[i] ^= cipher_block[i]; 
  }

  // sync
  __syncthreads();

  for(size_t i = 0; i < 16; ++i){
    d_cipher[i] = cipher[i]; 
  }

}

__global__ void second(uint8_t* d_cipher, uint8_t* d_key1, uint8_t* d_final){ 

  AES aes(AESKeyLength::AES_128);
  

  uint8_t *final_cipher;
  final_cipher = aes.EncryptECB(d_cipher, 16, d_key1);

  for(int i = 0; i < 16; i++){
    d_final[i] = final_cipher[i];
  }

}


int main(int argc, char* argv[])
{
    // reading plaintext files
    ifstream message_file(argv[1], ios::binary);

    message_file.seekg(0, ios::end);
    size_t file_size = message_file.tellg();
    size_t padding_bytes = 16 - (file_size % 16);
    size_t message_size = file_size + padding_bytes;
    message_file.seekg(0, ios::beg);

    uint8_t message[message_size];
    message_file.read(reinterpret_cast<char*>(message), file_size);
    message_file.close();

    message[file_size] = 0x80; 
    for (size_t i = file_size + 1; i < message_size; ++i) {
        message[i] = 0x00; 
    }


    // reading first key file
    ifstream key_file1(argv[2], ios::binary);

    key_file1.seekg(0, ios::end);
    file_size = key_file1.tellg();
    if(file_size != 128){
        cerr << "KEY SHOULD BE OF 16 BYTES ONLY!" << endl;
        return 1;
    }
    key_file1.seekg(0, ios::beg);

    uint8_t key1[16];
    key_file1.read(reinterpret_cast<char*>(key1), 16);
    key_file1.close();


    // reading second key file
    ifstream key_file2(argv[3]);
    int key2;
    key_file2 >> key2;
    key_file2.close();

    // uint8_t key2[16];
    // key_file2.read(reinterpret_cast<char*>(key2), 16);
    // key_file2.close();

    // parallal computation
    uint8_t *d_message, *d_key1, *d_cipher, *d_final;
    cudaMalloc(&d_message, message_size*sizeof(uint8_t));
    cudaMalloc(&d_key1, 16*sizeof(uint8_t));
    cudaMalloc(&d_cipher, 16*sizeof(uint8_t));
    cudaMalloc(&d_final, 16*sizeof(uint8_t));

    cudaMemcpy(d_message, message, message_size*sizeof(uint8_t), cudaMemcpyHostToDevice);
    cudaMemcpy(d_key1, key1, 16*sizeof(uint8_t), cudaMemcpyHostToDevice);

    int *d_key2;
    cudaMalloc((void **)&d_key2, sizeof(int));
    cudaMemcpy(d_key2, &key2, sizeof(int), cudaMemcpyHostToDevice); 

    first<<<1, message_size/16>>>(d_message, d_key1, d_key2, d_cipher);
    cudaDeviceSynchronize();


    // second step of pmac
    second<<<1, 1>>>(d_cipher, d_key1, d_final);
    cudaDeviceSynchronize();

    uint8_t* h_cipher = (uint8_t*)malloc(16* sizeof(uint8_t));
    cudaMemcpy(h_cipher, d_final, 16*sizeof(uint8_t), cudaMemcpyDeviceToHost);

    // saving output
    ofstream outFile("tag.txt");
    for (size_t i = 0; i < 16; ++i) {
        outFile << std::hex << static_cast<int>(h_cipher[i]) << " ";
    }
    outFile.close();



    // // thrust

    // // thrust::host_vector<uint8_t> h_message(message, message+message_size);
    // // thrust::host_vector<uint8_t> h_key1(key1, key1+16);
    // // thrust::host_vector<uint8_t> h_key2(key2, key2+16);

    // // thrust::host_vector<uint8_t> h_cipher(16, 0);

    // // thrust::device_vector<uint8_t> d_message(message, message+message_size);
    // // thrust::device_vector<uint8_t> d_key1(key1, key1+16);
    // // thrust::device_vector<uint8_t> d_key2(key2, key2+16);

    // // thrust::device_vector<uint8_t> d_cipher(16, 0);

    // // fun<<<1, message_size/16>>>(d_message, d_key1, d_key2, d_cipher);


    // // fun<<<1, message_size/16>>>(thrust::raw_pointer_cast(d_message.data()),
    // //                                          thrust::raw_pointer_cast(d_key1.data()),
    // //                                          thrust::raw_pointer_cast(d_key2.data()),
    // //                                          thrust::raw_pointer_cast(d_cipher.data()));
    // // cudaDeviceSynchronize();


    // // shared

    // // sycl::queue queue(sycl::default_selector{});
    // // uint8_t* d_message = sycl::malloc_shared<int>(file_size, queue);
    // // uint8_t* d_key1 = sycl::malloc_shared<int>(16, queue);
    // // uint8_t* d_key2 = sycl::malloc_shared<int>(16, queue);
    // // uint8_t* d_cipher = sycl::malloc_shared<int>(16, queue);

    // // d_message = message;
    // // d_key1 = key1;
    // // d_key2 = key2;



   

   

    
}
