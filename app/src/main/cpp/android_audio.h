#pragma once

#include <cstdint>

// Native Android audio output — mirrors desktop SIMU (SDL_QueueAudio /
// SDL_ClearQueuedAudio / SDL_GetQueuedAudioSize in simuaudio.cpp).
bool androidAudioInit();
void androidAudioDeinit();

void androidAudioQueue(const uint8_t* buf, uint32_t len);
int androidAudioBufferedMs();
int androidAudioHostAudibleMs();
void androidAudioFlush();
