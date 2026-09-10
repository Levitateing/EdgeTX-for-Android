/*
 * Stock TX16S has no WS2812 LED strip (no LED_STRIP_GPIO), but ANDROID
 * keeps FUNCTION_SWITCHES_RGB_LEDS for App ModelData layout parity.
 * Provide no-op / software-buffer stubs so the firmware links.
 */

#include "boards/generic_stm32/rgb_leds.h"

#include <string.h>

#if !defined(RGBLEDS_MAX_LEDS)
#define RGBLEDS_MAX_LEDS 26
#endif

#define RGBLEDS_BYTES_PER_LED 3

static uint8_t _led_colors[RGBLEDS_BYTES_PER_LED * RGBLEDS_MAX_LEDS];

void rgbLedInit() {}
void rgbLedHwInit() {}
void rgbLedStop() {}

void rgbSetLedColor(uint8_t led, uint8_t r, uint8_t g, uint8_t b)
{
  if (led >= RGBLEDS_MAX_LEDS) return;
  uint8_t* pixel = &_led_colors[led * RGBLEDS_BYTES_PER_LED];
  pixel[0] = g;
  pixel[1] = r;
  pixel[2] = b;
}

uint32_t rgbGetLedColor(uint8_t led)
{
  if (led >= RGBLEDS_MAX_LEDS) return 0;
  uint8_t* pixel = &_led_colors[led * RGBLEDS_BYTES_PER_LED];
  return (uint32_t(pixel[1]) << 16) | (uint32_t(pixel[0]) << 8) | pixel[2];
}

void rgbLedClearAll()
{
  memset(_led_colors, 0, sizeof(_led_colors));
}

bool rgbGetState(uint8_t led)
{
  return rgbGetLedColor(led) != 0;
}

void rgbLedColorApply() {}

__attribute__((weak)) void rgbLedOnUpdate() {}
