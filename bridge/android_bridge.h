#pragma once

#include <stddef.h>
#include <stdint.h>

#include "android_bridge_proto.h"

#ifdef __cplusplus
extern "C" {
#endif

void androidBridgeInit(void);
void androidBridgeStart(void);
void androidBridgeStop(void);

/* Feed raw USB CDC RX bytes (called from USB/serial RX path). */
void androidBridgeOnRx(const uint8_t* data, uint32_t len);

/* Called from a periodic task (~10–50 Hz). Handles TX streams when linked. */
void androidBridgePoll(void);

int androidBridgeIsLinked(void);

#ifdef __cplusplus
}
#endif
