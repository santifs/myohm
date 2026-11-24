/* Myohm adapted distribution (modification notice added 2026-10-14).
 * This is not an unmodified ADI upstream release. See MODIFICATIONS.md.
 * Existing ADI copyright and LicenseRef-ADI-reference terms remain in force.
 */
/*!
 *****************************************************************************
 @file:    AD5940Main.h
 @author:  Firmware Team
 @brief:   Header file for AD5940 main functions
 @version: 3.0 (Zephyr port)
 -----------------------------------------------------------------------------

Copyright (c) 2017-2025 Analog Devices, Inc. All Rights Reserved.

*****************************************************************************/

#ifndef AD5940MAIN_H
#define AD5940MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include "debug_config.h"

#define AD5940_MAX_SWEEP_POINTS 100

/* Excitation DAC amplitude limits in mVpp (before EXCITBUFGAIN_2). Keep in
 * sync with the range of CONFIG_MYOHM_EXCITATION_MVPP in Kconfig. */
#define AD5940_EXCITATION_MVPP_MIN 50
#define AD5940_EXCITATION_MVPP_MAX 800
/* The 200 kHz point is invalid with the present configuration (100 ohm read as 5.6 ohm, +90 deg). */
#define AD5940_MAX_STOP_HZ 198000.0f

/* Measurement point structure */
typedef struct {
    float frequency;
    float magnitude;
    float phase;
} MeasurementPoint;

typedef struct {
    float rcal_ohms;
    bool sweep_enabled;
    float start_hz;
    float stop_hz;
    uint32_t points;
    uint8_t repetitions;
    uint16_t excitation_mvpp; /* HSDAC amplitude, mVpp before the x2 excitation buffer */
} AD5940SweepConfig;

typedef void (*AD5940MeasurementCallback)(const MeasurementPoint *point, void *user_data);

typedef struct {
    uint16_t adi_id;
    uint16_t chip_id;
} AD5940Identity;

/* Global measurement buffer */
extern MeasurementPoint g_measurement_buffer[AD5940_MAX_SWEEP_POINTS];
extern uint32_t g_measurement_count;

/**
 * @brief Main AD5940 measurement function
 * @details Performs a complete bioimpedance sweep according to configured parameters
 */
void AD5940_Main(void);
/* Hardware reset plus clock, FIFO, interrupt and GPIO setup shared by the
 * sweep and the contact check. */
void AD5940PlatformCfg(void);
int AD5940_RunSweep(const AD5940SweepConfig *config,
                    AD5940MeasurementCallback callback,
                    void *user_data);
void AD5940_GetDefaultSweepConfig(AD5940SweepConfig *config);
int AD5940_ReadIdentity(AD5940Identity *identity);

#ifdef __cplusplus
}
#endif

#endif /* AD5940MAIN_H */
