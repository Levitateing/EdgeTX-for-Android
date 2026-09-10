# ANDROID physical board: TX16S-class STM32F429
# Software identity remains PCB=ANDROID / RADIO_ANDROID / FLAVOUR=android.
# PCBX10 + RADIO_FAMILY_T16 are defined only so horus/hal.h pin maps match the radio.

option(UNEXPECTED_SHUTDOWN "Enable the Unexpected Shutdown screen" ON)
option(PXX1 "PXX1 protocol support" ON)
option(PXX2 "PXX2 protocol support" OFF)
option(AFHDS3 "AFHDS3 TX Module" ON)
option(MULTIMODULE "DIY Multiprotocol TX Module" ON)
option(GHOST "Ghost TX Module" ON)
option(MODULE_SIZE_STD "Standard size TX Module" ON)
option(LUA_MIXER "Enable LUA mixer/model scripts support" ON)
option(DISK_CACHE "Enable SD card disk cache" ON)
option(BLUETOOTH "FrSky BT module support" OFF)
option(INTERNAL_GPS "Support for internal GPS" ON)
option(STICK_DEAD_ZONE "Enable sticks dead zone" OFF)

# Keep ModelData-compatible feature flags aligned with App (RADIO_ANDROID).
option(FUNCTION_SWITCHES "Function switches in ModelData" ON)
option(FUNCTION_SWITCHES_RGB_LEDS "RGB FS fields in ModelData (layout match App)" ON)

set(PWR_BUTTON "PRESS" CACHE STRING "Pwr button type (PRESS/SWITCH)")
set(CPU_TYPE STM32F4)
set(HSE_VALUE 12000000)
set(SDCARD YES)
set(STORAGE_MODELSLIST YES)
set(HAPTIC YES)
set(GUI_DIR colorlcd)
set(BITMAPS_DIR 480x272)
set(TARGET_DIR horus)
set(RTC_BACKUP_RAM YES)
set(PPM_LIMITS_SYMETRICAL YES)
set(USB_SERIAL ON CACHE BOOL "Enable USB serial (CDC)")
set(HARDWARE_EXTERNAL_MODULE YES)
set(ROTARY_ENCODER YES)
set(FLEXSW "2" CACHE STRING "Max flex inputs usable as switches")
set(INTERNAL_GPS_BAUDRATE "9600" CACHE STRING "Baud rate for internal GPS")
set(NANO OFF)
set(FLYSKY_GIMBAL ON)

set(CPU_TYPE_FULL STM32F429xI)
set(TARGET_LINKER_DIR stm32f429_sdram)
set(SIZE_TARGET_MEM_DEFINE "MEM_SIZE_SDRAM2=8192")

set(AUX_SERIAL ON)
if(NOT BLUETOOTH)
  set(AUX2_SERIAL ON)
endif()

set(IMU ON)
set(USB_CHARGER YES)

set(ENABLE_SERIAL_PASSTHROUGH ON CACHE BOOL "Enable serial passthrough")
set(CLI ON CACHE BOOL "Enable CLI")

# --- ANDROID software identity ---
# FLAVOUR stays "android" so RADIO_ANDROID / storage / App layout win.
# Also define RADIO_TX16S: horus/hal.h gates TX16S pin maps (I2C1 touch,
# ADC VREF, battery divider, AUX power GPIO, …) on this macro. Without it,
# touch uses I2C3 on PH7/8 (wrong) and PCBREV conflicts on those pins.
set(FLAVOUR android)
add_definitions(-DPCBANDROID -DPCBHORUS -DPCBX10)
add_definitions(-DPCBREV=TX16S -DPCBREV_TX16S)
add_definitions(-DRADIO_FAMILY_T16)
add_definitions(-DRADIO_ANDROID)
add_definitions(-DRADIO_TX16S)
add_definitions(-DANDROID_HW_TX16S)
add_definitions(-DMANUFACTURER_RADIOMASTER)
add_definitions(-DSOFTWARE_VOLUME)
add_definitions(-DBATTERY_CHARGE)
add_definitions(-DSTM32_SUPPORT_32BIT_TIMERS)
add_definitions(-DSTM32F429_439xx -DSTM32F429xx -DSDRAM -DHARDWARE_KEYS)
add_definitions(-DRTCLOCK)
add_definitions(-DPWR_BUTTON_${PWR_BUTTON})
add_definitions(-DTHREADSAFE_MALLOC)
add_definitions(-DUSB_CHARGER)

# Prefer Bridge headers and TX16S-only overrides — do NOT put targets/android
# on the include path (its H750 hal.h would shadow targets/horus/hal.h).
include_directories(BEFORE
  ${CMAKE_CURRENT_LIST_DIR}/../hw/tx16s
  ${CMAKE_CURRENT_LIST_DIR}/../bridge
)
# Stock TX16S has no CFS LED strip offset; needed by generic_stm32/led_driver.cpp
add_definitions(-DCFS_LED_STRIP_START=0)

# Physical ADC/keys from TX16S map; platform name remains android via FLAVOUR
set(ANDROID_HW_DESC_JSON android_tx16s.json)

set(INTERNAL_MODULES PXX1;PXX2;MULTI;CRSF CACHE STRING "Internal modules")
set(DEFAULT_INTERNAL_MODULE MULTIMODULE CACHE STRING "Default internal module")

set(BITMAPS_TARGET bm480_bitmaps)
set(FONTS_TARGET x10_fonts)
set(HARDWARE_TOUCH YES)
set(RADIO_DEPENDENCIES ${RADIO_DEPENDENCIES} ${BITMAPS_TARGET})
set(FIRMWARE_DEPENDENCIES datacopy)
set(SOFTWARE_KEYBOARD ON)
set(AFHDS3 ON)

add_definitions(-DHARDWARE_TOUCH -DHARDWARE_KEYS -DSOFTWARE_KEYBOARD)
add_definitions(-DAUDIO -DVOICE)
add_definitions(-DGPS_USART_BAUDRATE=${INTERNAL_GPS_BAUDRATE})
# Keep MIXSRC_LIGHT in enums for App ModelData compatibility (no lux HW on stock TX16S)
add_definitions(-DLUMINOSITY_SENSOR)

set(SDRAM ON)

if(STICK_DEAD_ZONE)
  add_definitions(-DSTICK_DEAD_ZONE)
endif()

if(NOT UNEXPECTED_SHUTDOWN)
  add_definitions(-DNO_UNEXPECTED_SHUTDOWN)
endif()

if(DISK_CACHE)
  set(SRC ${SRC} disk_cache.cpp)
  add_definitions(-DDISK_CACHE)
endif()

if(FUNCTION_SWITCHES)
  add_definitions(-DFUNCTION_SWITCHES)
endif()

if(FUNCTION_SWITCHES_RGB_LEDS)
  set(RGB_LEDS YES)
  add_definitions(-DFUNCTION_SWITCHES_RGB_LEDS)
  add_definitions(-DRGB_LEDS)
  add_definitions(-DRGBLEDS_MAX_LEDS=26)
  # No LED_STRIP_GPIO on stock TX16S — rgb_leds.cpp compiles empty; stubs needed.
  set(SRC ${SRC} targets/android/hw/tx16s/rgb_leds_stub.cpp)
endif()

if(INTERNAL_GPS)
  message("-- Internal GPS enabled")
  add_definitions(-DINTERNAL_GPS)
  set(SRC ${SRC} gps.cpp gps_nmea.cpp gps_ubx.cpp)
endif()

if(AUX_SERIAL)
  add_definitions(-DCONFIGURABLE_MODULE_PORT)
endif()

set(TARGET_SRC_DIR targets/${TARGET_DIR})

set(BOARD_COMMON_SRC
  ${TARGET_SRC_DIR}/board.cpp
  ${TARGET_SRC_DIR}/haptic_driver.cpp
  ${TARGET_SRC_DIR}/backlight_driver.cpp
  ${TARGET_SRC_DIR}/lcd_driver.cpp
  ${TARGET_SRC_DIR}/usb_charger_driver.cpp
  targets/common/arm/stm32/abnormal_reboot.cpp
  targets/common/arm/stm32/delays_driver.cpp
  targets/common/arm/stm32/diskio_spi_flash.cpp
  targets/common/arm/stm32/dma2d.cpp
  targets/common/arm/stm32/flash_driver.cpp
  targets/common/arm/stm32/pwr_driver.cpp
  targets/common/arm/stm32/rotary_encoder_driver.cpp
  targets/common/arm/stm32/rtc_driver.cpp
  targets/common/arm/stm32/spi_flash.cpp
  targets/common/arm/stm32/watchdog_driver.cpp
  drivers/frftl.cpp
)

add_library(board_bl OBJECT EXCLUDE_FROM_ALL
  ${BOARD_COMMON_SRC}
  ${RADIO_SRC_DIR}/gui/colorlcd/boot_menu.cpp
  targets/common/arm/stm32/sdram_driver.cpp
)
add_dependencies(board_bl ${BITMAPS_TARGET})
set(BOOTLOADER_SRC ${BOOTLOADER_SRC} $<TARGET_OBJECTS:board_bl>)

add_library(board OBJECT EXCLUDE_FROM_ALL
  ${BOARD_COMMON_SRC}
  targets/common/arm/stm32/delays_driver.cpp
  targets/common/arm/stm32/heartbeat_driver.cpp
  drivers/lsm6ds.cpp
  drivers/icm42627.cpp
  drivers/sc7u22.cpp
  targets/common/arm/stm32/mixer_scheduler_driver.cpp
  targets/common/arm/stm32/module_timer_driver.cpp
  targets/common/arm/stm32/sticks_pwm_driver.cpp
  targets/common/arm/stm32/stm32_pulse_driver.cpp
  targets/common/arm/stm32/stm32_softserial_driver.cpp
  targets/common/arm/stm32/stm32_switch_driver.cpp
  targets/common/arm/stm32/trainer_driver.cpp
  targets/common/arm/stm32/stm32_rgbleds.cpp
  targets/common/arm/stm32/audio_dac_driver.cpp
)
set(FIRMWARE_SRC ${FIRMWARE_SRC} $<TARGET_OBJECTS:board>)

if(BLUETOOTH)
  target_sources(board PRIVATE targets/common/arm/stm32/bluetooth_driver.cpp)
endif()

if(HARDWARE_TOUCH)
  add_definitions(-DTP_GT911)
  target_sources(board PRIVATE ${TARGET_SRC_DIR}/tp_gt911.cpp)
endif()

include_directories(${RADIO_SRC_DIR}/fonts/colorlcd gui/${GUI_DIR} gui/${GUI_DIR}/layouts)

set(FIRMWARE_SRC
  ${FIRMWARE_SRC}
  bootloader/loadboot.cpp
)

set(SRC ${SRC}
  io/frsky_firmware_update.cpp
  io/multi_firmware_update.cpp
)

if(MULTIMODULE)
  add_definitions(-DMULTI_PROTOLIST)
  set(SRC ${SRC} io/multi_protolist.cpp)
endif()

message(STATUS "ANDROID_HW=TX16S (STM32F429) — RADIO_ANDROID storage, horus/TX16S pins")
