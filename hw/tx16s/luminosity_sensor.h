/*
 * Stub luminosity sensor for ANDROID TX16S (F429) — no lux hardware.
 * Defined so MIXSRC_LIGHT / App ModelData enums stay layout-compatible.
 */
#include <stdint.h>
#include "edgetx_types.h"

#pragma once

inline bool getPeriodicLuxSensorValue() { return false; }
inline uint16_t getLuxSensorValue() { return 0; }
