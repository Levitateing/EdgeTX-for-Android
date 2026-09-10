/*
 * Android Bridge runtime (MCU side).
 * Streams: INPUT / CH / STATUS → App
 * Models: PUT/PATCH ← App; GET_MODEL → App
 * Radio:  PUT_RADIO ← App; GET_RADIO → App (full RadioData incl. calib)
 *
 * RX callback runs in USB context — only buffer bytes there.
 * Parse + TX run from androidBridgePoll() (per10ms / task context).
 */
#include "android_bridge.h"
#include <string.h>
#include "globals.h"
#include "hal/adc_driver.h"
#include "hal/key_driver.h"
#include "hal/rotary_encoder.h"
#include "hal/switch_driver.h"
#include "hal/usb_driver.h"
#include "board.h"
#include "myeeprom.h"
#include "storage/storage.h"
#include "timers_driver.h"
#if defined(USB_SERIAL) && !defined(SIMU) && !defined(BOOT)
extern void usbSerialPutc(void*, uint8_t c);
extern uint32_t usbSerialFreeSpace();
extern void usbSerialSetReceiveDataCb(void*, void (*cb)(uint8_t*, uint32_t));
static uint8_t rx_buf[ANDROID_BRIDGE_HEADER_SIZE + ANDROID_BRIDGE_MAX_PAYLOAD +
                      ANDROID_BRIDGE_CRC_SIZE];
static volatile uint32_t rx_len = 0;
static uint8_t linked = 0;
static uint32_t peer_caps = 0;
static uint16_t tx_seq = 1;
static uint8_t stream_div = 0;
static uint8_t status_div = 0;
static int32_t prev_rotenc = 0;
/* INPUT+CH every N×10ms; STATUS less often. */
#define STREAM_DIV 5
#define STATUS_DIV 50
static void android_bridge_usb_rx(uint8_t* data, uint32_t len)
{
  androidBridgeOnRx(data, len);
}
static uint32_t crc32_buf(const uint8_t* a, uint32_t a_len, const uint8_t* b,
                          uint32_t b_len)
{
  uint32_t c = 0xFFFFFFFFu;
  for (uint32_t i = 0; i < a_len; i++) {
    c ^= a[i];
    for (int bit = 0; bit < 8; bit++) {
      uint32_t mask = -(c & 1u);
      c = (c >> 1) ^ (0xEDB88320u & mask);
    }
  }
  for (uint32_t i = 0; i < b_len; i++) {
    c ^= b[i];
    for (int bit = 0; bit < 8; bit++) {
      uint32_t mask = -(c & 1u);
      c = (c >> 1) ^ (0xEDB88320u & mask);
    }
  }
  return ~c;
}
static void bridge_write_bytes(const uint8_t* data, uint32_t len)
{
  for (uint32_t i = 0; i < len; i++) {
    uint32_t spins = 0;
    while (usbSerialFreeSpace() < 1 && spins++ < 100000) {
    }
    usbSerialPutc(nullptr, data[i]);
  }
}
static void send_frame(uint16_t cmd, uint16_t seq, const void* payload,
                       uint32_t payload_len)
{
  if (payload_len > ANDROID_BRIDGE_MAX_PAYLOAD) return;
  uint8_t hdr[ANDROID_BRIDGE_HEADER_SIZE];
  hdr[0] = ANDROID_BRIDGE_MAGIC0;
  hdr[1] = ANDROID_BRIDGE_MAGIC1;
  hdr[2] = ANDROID_BRIDGE_MAGIC2;
  hdr[3] = ANDROID_BRIDGE_MAGIC3;
  hdr[4] = ANDROID_BRIDGE_PROTO_VERSION;
  hdr[5] = (uint8_t)(cmd & 0xFF);
  hdr[6] = (uint8_t)(cmd >> 8);
  hdr[7] = (uint8_t)(seq & 0xFF);
  hdr[8] = (uint8_t)(seq >> 8);
  hdr[9] = (uint8_t)(payload_len & 0xFF);
  hdr[10] = (uint8_t)((payload_len >> 8) & 0xFF);
  hdr[11] = (uint8_t)((payload_len >> 16) & 0xFF);
  hdr[12] = (uint8_t)((payload_len >> 24) & 0xFF);
  const uint8_t* p = (const uint8_t*)payload;
  uint32_t crc = crc32_buf(hdr, ANDROID_BRIDGE_HEADER_SIZE, p, payload_len);
  bridge_write_bytes(hdr, ANDROID_BRIDGE_HEADER_SIZE);
  if (payload_len && p) bridge_write_bytes(p, payload_len);
  uint8_t crc_le[4] = {
      (uint8_t)(crc & 0xFF),
      (uint8_t)((crc >> 8) & 0xFF),
      (uint8_t)((crc >> 16) & 0xFF),
      (uint8_t)((crc >> 24) & 0xFF),
  };
  bridge_write_bytes(crc_le, 4);
}
static void fill_hello_ack(AndroidBridgeHelloPayload* out)
{
  memset(out, 0, sizeof(*out));
  out->proto_version = ANDROID_BRIDGE_PROTO_VERSION;
  out->caps = ABR_CAP_INPUT_STREAM | ABR_CAP_CH_STREAM | ABR_CAP_PUT_MODEL |
              ABR_CAP_PATCH_MODEL | ABR_CAP_RADIO_FLIGHT | ABR_CAP_GET_MODEL |
              ABR_CAP_PUT_RADIO | ABR_CAP_GET_RADIO;
  out->modeldata_size = (uint32_t)sizeof(ModelData);
  out->radio_flight_size = (uint32_t)sizeof(AndroidBridgeRadioFlightPayload);
  strncpy(out->board_id, "android", sizeof(out->board_id) - 1);
#if defined(ANDROID_HW_TX16S)
  strncpy(out->hw_id, "tx16s-f429", sizeof(out->hw_id) - 1);
#else
  strncpy(out->hw_id, "h750", sizeof(out->hw_id) - 1);
#endif
  out->stick_mode = (uint8_t)(g_eeGeneral.stickMode & 3u);
  out->template_setup = g_eeGeneral.templateSetup;
}

static void apply_radio_flight(const AndroidBridgeRadioFlightPayload* rf)
{
  if (!rf) return;
  uint8_t sm = rf->stick_mode & 3u;
  bool dirty = false;
  if (g_eeGeneral.stickMode != sm) {
    g_eeGeneral.stickMode = sm;
    dirty = true;
  }
  if (g_eeGeneral.templateSetup != rf->template_setup) {
    g_eeGeneral.templateSetup = rf->template_setup;
    dirty = true;
  }
  if (dirty) storageDirty(EE_GENERAL);
}

static void fill_input_payload(AndroidBridgeInputPayload* out)
{
  memset(out, 0, sizeof(*out));
  out->timestamp_ms = (uint32_t)get_tmr10ms() * 10u;
  for (int i = 0; i < 4; i++) {
    out->sticks[i] = calibratedAnalogs[i];
  }
  uint8_t pot_off = adcGetInputOffset(ADC_INPUT_FLEX);
  uint8_t pot_n = adcGetMaxInputs(ADC_INPUT_FLEX);
  if (pot_n > ABR_INPUT_POTS) pot_n = ABR_INPUT_POTS;
  for (uint8_t i = 0; i < pot_n; i++) {
    out->pots[i] = calibratedAnalogs[pot_off + i];
  }
  uint8_t nt = MAX_TRIMS;
  if (nt > ABR_INPUT_TRIMS) nt = ABR_INPUT_TRIMS;
  for (uint8_t i = 0; i < nt; i++) {
    /* Mixer stores trims[i] = getTrimValue()*2; send storage units. */
    out->trims[i] = (int16_t)(trims[i] / 2);
  }
  uint8_t nsw = switchGetMaxSwitches();
  if (nsw > 16) nsw = 16;
  uint32_t swbits = 0;
  for (uint8_t i = 0; i < nsw; i++) {
    swbits |= ((uint32_t)(switchGetPosition(i) & 3u)) << (i * 2);
  }
  out->switches = swbits;
  out->keys = (uint16_t)(readKeys() & 0xFFFFu);
  out->trim_keys = (uint16_t)(readTrims() & 0xFFFFu);

  int32_t cur = (int32_t)rotaryEncoderGetValue();
  int32_t d = cur - prev_rotenc;
  prev_rotenc = cur;
  if (d > 32767) d = 32767;
  if (d < -32768) d = -32768;
  out->rotenc_delta = (int16_t)d;
  out->pwr = pwrPressed() ? 1 : 0;
  out->reserved = 0;
}
static void fill_ch_payload(AndroidBridgeChPayload* out)
{
  memset(out, 0, sizeof(*out));
  out->timestamp_ms = (uint32_t)get_tmr10ms() * 10u;
  uint8_t n = MAX_OUTPUT_CHANNELS;
  if (n > ABR_CH_MAX) n = ABR_CH_MAX;
  out->count = n;
  for (uint8_t i = 0; i < n; i++) {
    out->channels[i] = channelOutputs[i];
  }
}
static void fill_status_payload(AndroidBridgeStatusPayload* out)
{
  memset(out, 0, sizeof(*out));
  out->model_crc =
      crc32_buf((const uint8_t*)&g_model, sizeof(g_model), nullptr, 0);
  out->radio_flight_crc =
      crc32_buf((const uint8_t*)&g_eeGeneral, sizeof(g_eeGeneral), nullptr, 0);
  out->link_ok = linked;
  out->usb_mode_ok = 1;
  out->stick_mode = (uint8_t)(g_eeGeneral.stickMode & 3u);
  out->template_setup = g_eeGeneral.templateSetup;
  strncpy(out->model_name, g_model.header.name, sizeof(out->model_name) - 1);
}
static void maybe_send_streams(void)
{
  if (!linked) return;
  if (++stream_div >= STREAM_DIV) {
    stream_div = 0;
    AndroidBridgeInputPayload in;
    fill_input_payload(&in);
    send_frame(ABR_CMD_INPUT_STREAM, tx_seq++, &in, sizeof(in));
    AndroidBridgeChPayload ch;
    fill_ch_payload(&ch);
    /* Send header + count*2 channel words (omit unused tail). */
    uint32_t ch_bytes = 4 + 4 + (uint32_t)ch.count * sizeof(int16_t);
    send_frame(ABR_CMD_CH_STREAM, tx_seq++, &ch, ch_bytes);
  }
  if (++status_div >= STATUS_DIV) {
    status_div = 0;
    AndroidBridgeStatusPayload st;
    fill_status_payload(&st);
    send_frame(ABR_CMD_STATUS, tx_seq++, &st, sizeof(st));
  }
}
static void send_model_ack(uint16_t cmd, uint16_t seq, uint8_t status)
{
  AndroidBridgePutModelAck ack;
  memset(&ack, 0, sizeof(ack));
  ack.status = status;
  ack.modeldata_size = (uint32_t)sizeof(ModelData);
  send_frame(cmd, seq, &ack, sizeof(ack));
}
static void apply_put_model(uint16_t seq, const uint8_t* payload, uint32_t len)
{
  if (len != (uint32_t)sizeof(ModelData)) {
    send_model_ack(ABR_CMD_PUT_MODEL_ACK, seq, ABR_PUT_SIZE_MISMATCH);
    return;
  }
  preModelLoad();
  memcpy(&g_model, payload, sizeof(ModelData));
  postModelLoad(false);
  storageDirty(EE_MODEL);
  send_model_ack(ABR_CMD_PUT_MODEL_ACK, seq, ABR_PUT_OK);
}
static void send_radio_ack(uint16_t seq, uint8_t status)
{
  AndroidBridgePutModelAck ack;
  memset(&ack, 0, sizeof(ack));
  ack.status = status;
  ack.modeldata_size = (uint32_t)sizeof(RadioData);
  send_frame(ABR_CMD_PUT_RADIO_ACK, seq, &ack, sizeof(ack));
}

static void apply_put_radio(uint16_t seq, const uint8_t* payload, uint32_t len)
{
  if (len != (uint32_t)sizeof(RadioData)) {
    send_radio_ack(seq, ABR_PUT_SIZE_MISMATCH);
    return;
  }
  memcpy(&g_eeGeneral, payload, sizeof(RadioData));
  storageDirty(EE_GENERAL);
  send_radio_ack(seq, ABR_PUT_OK);
}

static void apply_patch_model(uint16_t seq, const uint8_t* payload, uint32_t len)
{
  if (len < 2) {
    send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_BAD);
    return;
  }
  uint16_t nreg = (uint16_t)payload[0] | ((uint16_t)payload[1] << 8);
  if (nreg == 0 || nreg > ABR_PATCH_MAX_REGIONS) {
    send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_BAD);
    return;
  }
  uint32_t off = 2;
  /* Validate all regions first. */
  for (uint16_t i = 0; i < nreg; i++) {
    if (off + 4 > len) {
      send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_BAD);
      return;
    }
    uint16_t ro = (uint16_t)payload[off] | ((uint16_t)payload[off + 1] << 8);
    uint16_t rl = (uint16_t)payload[off + 2] | ((uint16_t)payload[off + 3] << 8);
    off += 4;
    if (rl == 0 || (uint32_t)ro + rl > sizeof(ModelData) || off + rl > len) {
      send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_BAD);
      return;
    }
    off += rl;
  }
  if (off != len) {
    send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_BAD);
    return;
  }
  /* Apply in place (no full model reload — use PUT for structural swaps). */
  off = 2;
  uint8_t* base = (uint8_t*)&g_model;
  for (uint16_t i = 0; i < nreg; i++) {
    uint16_t ro = (uint16_t)payload[off] | ((uint16_t)payload[off + 1] << 8);
    uint16_t rl = (uint16_t)payload[off + 2] | ((uint16_t)payload[off + 3] << 8);
    off += 4;
    memcpy(base + ro, payload + off, rl);
    off += rl;
  }
  storageDirty(EE_MODEL);
  send_model_ack(ABR_CMD_PATCH_MODEL_ACK, seq, ABR_PUT_OK);
}
static void handle_frame(uint16_t cmd, uint16_t seq, const uint8_t* payload,
                         uint32_t len)
{
  switch (cmd) {
    case ABR_CMD_HELLO: {
      if (len >= 13) {
        /* caps at offset 1 (after proto_version); tolerate old/new HELLO sizes */
        peer_caps = (uint32_t)payload[1] | ((uint32_t)payload[2] << 8) |
                    ((uint32_t)payload[3] << 16) | ((uint32_t)payload[4] << 24);
      }
      linked = 1;
      stream_div = 0;
      status_div = 0;
      prev_rotenc = (int32_t)rotaryEncoderGetValue();
#if defined(USB_SERIAL) && !defined(SIMU)
      /* App handshake — stay on VCP; dismiss mode picker if still open. */
      if (getSelectedUsbMode() != USB_SERIAL_MODE) {
        setSelectedUsbMode(USB_SERIAL_MODE);
      }
      extern void closeUsbMenu();
      closeUsbMenu();
#endif
      AndroidBridgeHelloPayload ack;
      fill_hello_ack(&ack);
      send_frame(ABR_CMD_HELLO_ACK, seq, &ack, sizeof(ack));
      break;
    }
    case ABR_CMD_PING:
      send_frame(ABR_CMD_PONG, seq, payload, len);
      break;
    case ABR_CMD_GET_STATUS: {
      AndroidBridgeStatusPayload st;
      fill_status_payload(&st);
      send_frame(ABR_CMD_STATUS, seq, &st, sizeof(st));
      break;
    }
    case ABR_CMD_PUT_MODEL:
      apply_put_model(seq, payload, len);
      break;
    case ABR_CMD_PATCH_MODEL:
      apply_patch_model(seq, payload, len);
      break;
    case ABR_CMD_PUT_RADIO_FLIGHT: {
      if (len < sizeof(AndroidBridgeRadioFlightPayload)) {
        send_model_ack(ABR_CMD_PUT_RADIO_FLIGHT_ACK, seq, ABR_PUT_BAD);
        break;
      }
      apply_radio_flight((const AndroidBridgeRadioFlightPayload*)payload);
      send_model_ack(ABR_CMD_PUT_RADIO_FLIGHT_ACK, seq, ABR_PUT_OK);
      break;
    }
    case ABR_CMD_GET_MODEL:
      send_frame(ABR_CMD_MODEL_DATA, seq, &g_model, (uint32_t)sizeof(ModelData));
      break;
    case ABR_CMD_PUT_RADIO:
      apply_put_radio(seq, payload, len);
      break;
    case ABR_CMD_GET_RADIO:
      send_frame(ABR_CMD_RADIO_DATA, seq, &g_eeGeneral, (uint32_t)sizeof(RadioData));
      break;
    default: {
      uint16_t bad = cmd;
      send_frame(ABR_CMD_NACK, seq, &bad, sizeof(bad));
      break;
    }
  }
}
static void try_parse_rx(void)
{
  while (rx_len >= ANDROID_BRIDGE_HEADER_SIZE) {
    if (rx_buf[0] != ANDROID_BRIDGE_MAGIC0 || rx_buf[1] != ANDROID_BRIDGE_MAGIC1 ||
        rx_buf[2] != ANDROID_BRIDGE_MAGIC2 || rx_buf[3] != ANDROID_BRIDGE_MAGIC3) {
      memmove(rx_buf, rx_buf + 1, --rx_len);
      continue;
    }
    if (rx_buf[4] != ANDROID_BRIDGE_PROTO_VERSION) {
      memmove(rx_buf, rx_buf + 1, --rx_len);
      continue;
    }
    uint16_t cmd = (uint16_t)rx_buf[5] | ((uint16_t)rx_buf[6] << 8);
    uint16_t seq = (uint16_t)rx_buf[7] | ((uint16_t)rx_buf[8] << 8);
    uint32_t plen = (uint32_t)rx_buf[9] | ((uint32_t)rx_buf[10] << 8) |
                    ((uint32_t)rx_buf[11] << 16) | ((uint32_t)rx_buf[12] << 24);
    if (plen > ANDROID_BRIDGE_MAX_PAYLOAD) {
      memmove(rx_buf, rx_buf + 1, --rx_len);
      continue;
    }
    uint32_t frame_len =
        ANDROID_BRIDGE_HEADER_SIZE + plen + ANDROID_BRIDGE_CRC_SIZE;
    if (rx_len < frame_len) return;
    uint32_t expect = crc32_buf(rx_buf, ANDROID_BRIDGE_HEADER_SIZE,
                                rx_buf + ANDROID_BRIDGE_HEADER_SIZE, plen);
    const uint8_t* crcp = rx_buf + ANDROID_BRIDGE_HEADER_SIZE + plen;
    uint32_t got = (uint32_t)crcp[0] | ((uint32_t)crcp[1] << 8) |
                   ((uint32_t)crcp[2] << 16) | ((uint32_t)crcp[3] << 24);
    if (expect == got) {
      handle_frame(cmd, seq, rx_buf + ANDROID_BRIDGE_HEADER_SIZE, plen);
    }
    memmove(rx_buf, rx_buf + frame_len, rx_len - frame_len);
    rx_len -= frame_len;
  }
}
void androidBridgeInit(void)
{
  rx_len = 0;
  linked = 0;
  peer_caps = 0;
  tx_seq = 1;
  stream_div = 0;
  status_div = 0;
  prev_rotenc = 0;
}
void androidBridgeStart(void)
{
  usbSerialSetReceiveDataCb(nullptr, android_bridge_usb_rx);
}
void androidBridgeStop(void)
{
  linked = 0;
  usbSerialSetReceiveDataCb(nullptr, nullptr);
}
void androidBridgeOnRx(const uint8_t* data, uint32_t len)
{
  if (!data || !len) return;
  for (uint32_t i = 0; i < len; i++) {
    uint32_t n = rx_len;
    if (n >= sizeof(rx_buf)) {
      rx_len = 0;
      n = 0;
    }
    rx_buf[n] = data[i];
    rx_len = n + 1;
  }
}
void androidBridgePoll(void)
{
  usbSerialSetReceiveDataCb(nullptr, android_bridge_usb_rx);
  try_parse_rx();
  maybe_send_streams();
}
int androidBridgeIsLinked(void) { return linked; }
#else /* SIMU / BOOT / no USB_SERIAL */
void androidBridgeInit(void) {}
void androidBridgeStart(void) {}
void androidBridgeStop(void) {}
void androidBridgeOnRx(const uint8_t*, uint32_t) {}
void androidBridgePoll(void) {}
int androidBridgeIsLinked(void) { return 0; }
#endif
