/*
 * EdgeTX Android Bridge — wire protocol (App ↔ MCU over USB CDC).
 * Shared by firmware (C) and documented for the Kotlin host.
 *
 * Frame (little-endian):
 *   magic[4] = 'E','T','X','B'
 *   version  u8     (ANDROID_BRIDGE_PROTO_VERSION)
 *   cmd      u16
 *   seq      u16
 *   len      u32    (payload bytes)
 *   payload  len
 *   crc32    u32    (IEEE over bytes from magic through payload inclusive)
 */
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ANDROID_BRIDGE_PROTO_VERSION 1

#define ANDROID_BRIDGE_MAGIC0 'E'
#define ANDROID_BRIDGE_MAGIC1 'T'
#define ANDROID_BRIDGE_MAGIC2 'X'
#define ANDROID_BRIDGE_MAGIC3 'B'

#define ANDROID_BRIDGE_HEADER_SIZE 13 /* magic4 + ver1 + cmd2 + seq2 + len4 */
#define ANDROID_BRIDGE_CRC_SIZE 4
#define ANDROID_BRIDGE_MAX_PAYLOAD 8192

#define ABR_INPUT_POTS 10
#define ABR_INPUT_TRIMS 8
#define ABR_CH_MAX 32

enum AndroidBridgeCmd {
  ABR_CMD_HELLO = 0x0001,
  ABR_CMD_HELLO_ACK = 0x0002,
  ABR_CMD_PING = 0x0003,
  ABR_CMD_PONG = 0x0004,
  ABR_CMD_GET_STATUS = 0x0005,
  ABR_CMD_STATUS = 0x0006,
  ABR_CMD_INPUT_STREAM = 0x0010, /* MCU → App, periodic */
  ABR_CMD_CH_STREAM = 0x0011,    /* MCU → App, periodic */
  ABR_CMD_PUT_MODEL = 0x0020,    /* App → MCU, full ModelData */
  ABR_CMD_PUT_MODEL_ACK = 0x0021,
  ABR_CMD_PATCH_MODEL = 0x0022,  /* App → MCU, dirty regions */
  ABR_CMD_PATCH_MODEL_ACK = 0x0023,
  ABR_CMD_PUT_RADIO_FLIGHT = 0x0024, /* App → MCU, stickMode/templateSetup */
  ABR_CMD_PUT_RADIO_FLIGHT_ACK = 0x0025,
  ABR_CMD_GET_MODEL = 0x0026,        /* App → MCU */
  ABR_CMD_MODEL_DATA = 0x0027,       /* MCU → App, full ModelData */
  ABR_CMD_PUT_RADIO = 0x0028,        /* App → MCU, full RadioData */
  ABR_CMD_PUT_RADIO_ACK = 0x0029,
  ABR_CMD_GET_RADIO = 0x002A,        /* App → MCU */
  ABR_CMD_RADIO_DATA = 0x002B,       /* MCU → App, full RadioData */
  ABR_CMD_NACK = 0x00FF,
};

enum AndroidBridgeCaps {
  ABR_CAP_INPUT_STREAM = 1u << 0,
  ABR_CAP_CH_STREAM = 1u << 1,
  ABR_CAP_PUT_MODEL = 1u << 2,
  ABR_CAP_PATCH_MODEL = 1u << 3,
  ABR_CAP_RADIO_FLIGHT = 1u << 4,
  ABR_CAP_GET_MODEL = 1u << 5,
  ABR_CAP_PUT_RADIO = 1u << 6,
  ABR_CAP_GET_RADIO = 1u << 7,
};

/* HELLO / HELLO_ACK — flight-critical radio settings snapshot */
typedef struct __attribute__((packed)) {
  uint8_t proto_version;
  uint32_t caps;
  uint32_t modeldata_size;
  uint32_t radio_flight_size; /* sizeof(AndroidBridgeRadioFlightPayload) */
  char board_id[16];
  char hw_id[16];
  uint8_t stick_mode;      /* 0..3 = Mode 1..4 */
  uint8_t template_setup;  /* g_eeGeneral.templateSetup (RETA etc.) */
  uint8_t pad[2];
} AndroidBridgeHelloPayload;

/*
 * INPUT_STREAM — physical TX inputs (RESX ≈ -1024..+1024).
 * rotenc_delta: encoder steps since last stream (post granularity).
 * pwr: power switch pressed (1) / released (0).
 */
typedef struct __attribute__((packed)) {
  uint32_t timestamp_ms;
  int16_t sticks[4];
  int16_t pots[ABR_INPUT_POTS];
  int16_t trims[ABR_INPUT_TRIMS];
  uint32_t switches;
  uint16_t keys;
  uint16_t trim_keys;
  int16_t rotenc_delta;
  uint8_t pwr;
  uint8_t reserved;
} AndroidBridgeInputPayload;

typedef struct __attribute__((packed)) {
  uint32_t timestamp_ms;
  uint8_t count;
  uint8_t reserved[3];
  int16_t channels[ABR_CH_MAX];
} AndroidBridgeChPayload;

typedef struct __attribute__((packed)) {
  uint32_t model_crc;
  uint32_t radio_flight_crc;
  uint8_t link_ok;
  uint8_t usb_mode_ok;
  uint8_t stick_mode;
  uint8_t template_setup;
  char model_name[16];
} AndroidBridgeStatusPayload;

/* Minimal radio settings for mixer/layout parity (not full RadioData). */
typedef struct __attribute__((packed)) {
  uint8_t stick_mode;
  uint8_t template_setup;
  uint8_t pad[2];
} AndroidBridgeRadioFlightPayload;

#define ABR_PATCH_MAX_REGIONS 64

typedef struct __attribute__((packed)) {
  uint8_t status;
  uint8_t reserved[3];
  uint32_t modeldata_size;
} AndroidBridgePutModelAck;

enum AndroidBridgePutStatus {
  ABR_PUT_OK = 0,
  ABR_PUT_SIZE_MISMATCH = 1,
  ABR_PUT_BUSY = 2,
  ABR_PUT_BAD = 3,
};

#ifdef __cplusplus
} /* extern "C" */
#endif
