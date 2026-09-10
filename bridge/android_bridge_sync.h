/*
 * App-only ModelData fields for headless MCU: strip + flight CRC.
 * Shared by MCU bridge and App SIMU (must stay identical).
 *
 * App-only (cleared on MCU after PUT/PATCH; excluded from flight CRC):
 *   header.name, header.bitmap, header.labels
 *   COLORLCD: topbarWidgetWidth[], view
 * modelId[] is NOT stripped — required for RF.
 */
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "myeeprom.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline uint32_t androidBridgeCrc32Buf(const uint8_t* p, uint32_t len)
{
  uint32_t c = 0xFFFFFFFFu;
  for (uint32_t i = 0; i < len; i++) {
    c ^= p[i];
    for (int bit = 0; bit < 8; bit++) {
      uint32_t mask = -(c & 1u);
      c = (c >> 1) ^ (0xEDB88320u & mask);
    }
  }
  return ~c;
}

/** Zero UI-only fields in-place (dead on headless MCU). */
static inline void androidBridgeStripModelUiFields(ModelData* m)
{
  if (!m) return;
  memset(m->header.name, 0, sizeof(m->header.name));
#if LEN_BITMAP_NAME > 0
  memset(m->header.bitmap, 0, sizeof(m->header.bitmap));
#endif
#if defined(STORAGE_MODELSLIST)
  memset(m->header.labels, 0, sizeof(m->header.labels));
#endif
#if defined(COLORLCD)
  memset(m->topbarWidgetWidth, 0, sizeof(m->topbarWidgetWidth));
  m->view = 0;
#endif
}

/**
 * CRC32 over ModelData with UI-only fields treated as zero
 * (does not modify *src).
 */
static inline uint32_t androidBridgeModelFlightCrc(const ModelData* src)
{
  if (!src) return 0;
  ModelData tmp;
  memcpy(&tmp, src, sizeof(ModelData));
  androidBridgeStripModelUiFields(&tmp);
  return androidBridgeCrc32Buf((const uint8_t*)&tmp, (uint32_t)sizeof(ModelData));
}

/** Radio UI-only: theme name is App-only on COLORLCD. */
static inline void androidBridgeStripRadioUiFields(RadioData* r)
{
  if (!r) return;
#if defined(COLORLCD)
  memset(r->selectedTheme, 0, sizeof(r->selectedTheme));
#endif
}

#ifdef __cplusplus
}
#endif
