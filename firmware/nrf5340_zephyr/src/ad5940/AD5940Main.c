/* Myohm adapted distribution (modification notice added 2026-10-14).
 * This is not an unmodified ADI upstream release. See MODIFICATIONS.md.
 * Existing ADI copyright and LicenseRef-ADI-reference terms remain in force.
 */
/*!
 *****************************************************************************
 @file:    AD5940Main.c
 @author:  $Author: nxu2 $
 @brief:   Used to control specific application and futhur process data.
 @version: $Revision: 766 $
 @date:    $Date: 2017-08-21 14:09:35 +0100 (Mon, 21 Aug 2017) $
 -----------------------------------------------------------------------------

Copyright (c) 2017-2019 Analog Devices, Inc. All Rights Reserved.

This software is proprietary to Analog Devices, Inc. and its licensors.
By using this software you agree to the terms of the associated
Analog Devices Software License Agreement.

*****************************************************************************/
/**
 * @addtogroup AD5940_System_Examples
 * @{
 *  @defgroup BioElec_Example
 *  @{
  */

#include "ad5940.h"
#include <errno.h>
#include <stdio.h>
#include <zephyr/kernel.h>
#include "BodyImpedance.h"
#include "AD5940Main.h"

#define APPBUFF_SIZE 512
uint32_t AppBuff[APPBUFF_SIZE];
extern uint8_t BIAend;

/* Config parameters AD5940 */
float cfgRcalVal = 30.0;  /* Myohm schematic RCAL1 is 30 ohms, 0.1%; verify populated value. */
int32_t cfgNumOfData = DEFAULT_NUM_REPETITIONS * DEFAULT_SWEEP_POINTS;
bool cfgSweepEn = true;
float cfgSweepStart = 4000;
float cfgSweepStop = 198000;
uint32_t cfgSweepPoints = DEFAULT_SWEEP_POINTS;
uint8_t cfgNumRepetitions = DEFAULT_NUM_REPETITIONS;
/* HSDAC amplitude in mVpp before EXCITBUFGAIN_2; CE0 swings twice this value. */
float cfgExcitationMvpp = (float)CONFIG_MYOHM_EXCITATION_MVPP;

/* Buffer global para almacenar los puntos de medicion */
MeasurementPoint g_measurement_buffer[AD5940_MAX_SWEEP_POINTS];
uint32_t g_measurement_count = 0;
static bool g_measurement_complete = false;
static AD5940MeasurementCallback g_measurement_callback;
static void *g_measurement_callback_user_data;

/* Print one measurement row: freq, |Z|, phase, Real, Imag. Complex Z = R + jX. */
int32_t BIAShowResult(uint32_t *pData, uint32_t DataCount)
{
  float freq;
  fImpPol_Type *pImp = (fImpPol_Type*)pData;
  AppBIACtrl(BIACTRL_GETFREQ, &freq);

  float mag = pImp[0].Magnitude;
  float phase_rad = pImp[0].Phase;
  float phase_deg = phase_rad * 180.0f / MATH_PI;
  float real = mag * cosf(phase_rad);
  float imag = mag * sinf(phase_rad);

  printk("%2u  %10.2f  %10.3f  %+8.3f  %+10.3f  %+10.3f\n",
         (unsigned)(g_measurement_count + 1),
         (double)freq, (double)mag, (double)phase_deg,
         (double)real, (double)imag);

  if (g_measurement_count < AD5940_MAX_SWEEP_POINTS) {
    g_measurement_buffer[g_measurement_count].frequency = freq;
    g_measurement_buffer[g_measurement_count].magnitude = mag;
    g_measurement_buffer[g_measurement_count].phase = phase_deg;
  }

  MeasurementPoint point = {
    .frequency = freq,
    .magnitude = mag,
    .phase = phase_deg,
  };

  if (g_measurement_callback != NULL) {
    g_measurement_callback(&point, g_measurement_callback_user_data);
  }

  g_measurement_count++;

  if (g_measurement_count >= cfgSweepPoints) {
    g_measurement_count = 0;
    g_measurement_complete = false;
  }

  return 0;
}

/* Initialize AD5940 basic blocks like clock */
void AD5940PlatformCfg(void)
{
  CLKCfg_Type clk_cfg;
  FIFOCfg_Type fifo_cfg;
  AGPIOCfg_Type gpio_cfg;

  /* Use hardware reset */
  AD5940_HWReset();
  AD5940_Delay10us(2000);  /* 20ms after reset */
  AD5940_Initialize();
  /* Step1. Configure clock */
  clk_cfg.ADCClkDiv = ADCCLKDIV_1;
  clk_cfg.ADCCLkSrc = ADCCLKSRC_HFOSC;
  clk_cfg.SysClkDiv = SYSCLKDIV_1;
  clk_cfg.SysClkSrc = SYSCLKSRC_HFOSC;
  clk_cfg.HfOSC32MHzMode = bFALSE;  /* LP mode uses 16 MHz HFOSC; legacy showed cleaner phase. */
  clk_cfg.HFOSCEn = bTRUE;
  clk_cfg.HFXTALEn = bFALSE;
  clk_cfg.LFOSCEn = bTRUE;
  AD5940_CLKCfg(&clk_cfg);
  /* Step2. Configure FIFO and Sequencer*/
  fifo_cfg.FIFOEn = bFALSE;
  fifo_cfg.FIFOMode = FIFOMODE_FIFO;
  fifo_cfg.FIFOSize = FIFOSIZE_4KB;
  fifo_cfg.FIFOSrc = FIFOSRC_DFT;
  fifo_cfg.FIFOThresh = 4;
  AD5940_FIFOCfg(&fifo_cfg);
  fifo_cfg.FIFOEn = bTRUE;
  AD5940_FIFOCfg(&fifo_cfg);

  /* Step3. Interrupt controller */
  AD5940_INTCCfg(AFEINTC_1, AFEINTSRC_ALLINT, bTRUE);
  AD5940_INTCCfg(AFEINTC_0, AFEINTSRC_DATAFIFOTHRESH, bTRUE);
  AD5940_INTCClrFlag(AFEINTSRC_ALLINT);
  /* Step4: Reconfigure GPIO */
  gpio_cfg.FuncSet = GP6_SYNC|GP5_SYNC|GP4_SYNC|GP2_TRIG|GP1_SYNC|GP0_INT;
  gpio_cfg.InputEnSet = AGPIO_Pin2;
  gpio_cfg.OutputEnSet = AGPIO_Pin0|AGPIO_Pin1|AGPIO_Pin4|AGPIO_Pin5|AGPIO_Pin6;
  gpio_cfg.OutVal = 0;
  gpio_cfg.PullEnSet = 0;

  AD5940_AGPIOCfg(&gpio_cfg);
}

/* !!Change the application parameters here if you want to change it to none-default value */
void AD5940BIAStructInit(void)
{
  static bool first_time = 1;
  AppBIACfg_Type *pBIACfg;

  AppBIAGetCfg(&pBIACfg);

  pBIACfg->SeqStartAddr = 0;
  pBIACfg->MaxSeqLen = 512;

  pBIACfg->RcalVal = cfgRcalVal;
  pBIACfg->DftNum = DFTNUM_8192;
  pBIACfg->NumOfData = cfgNumOfData;
  pBIACfg->BiaODR = 20;
  pBIACfg->FifoThresh = 4;
  pBIACfg->ADCSinc3Osr = ADCSINC3OSR_2;
  pBIACfg->DacVoltPP = cfgExcitationMvpp;
  pBIACfg->HsDacGain = HSDACGAIN_1;
  pBIACfg->ExcitBufGain = EXCITBUFGAIN_2;

  pBIACfg->SweepCfg.SweepEn = cfgSweepEn;
  pBIACfg->SweepCfg.SweepStart = cfgSweepStart;
  pBIACfg->SweepCfg.SweepStop = cfgSweepStop;
  pBIACfg->SweepCfg.SweepPoints = cfgSweepPoints;
  pBIACfg->SweepCfg.SweepLog = bTRUE;

  if (first_time) {
    pBIACfg->SweepCfg.SweepIndex = 0;
    first_time = 0;
  }
}


static void PrintHeader(void)
{
  AppBIACfg_Type *pBIACfg;
  AppBIAGetCfg(&pBIACfg);

  printk("\nSweep: %.0f Hz -> %.0f Hz  (%u points, log)\n",
         (double)cfgSweepStart, (double)cfgSweepStop,
         (unsigned)cfgSweepPoints);
  printk("RCAL = %.1f Ohm   RTIA sel = 1 kOhm   Excitation = %.0f mVpp\n",
         (double)cfgRcalVal, (double)(pBIACfg->DacVoltPP *
         (pBIACfg->ExcitBufGain == EXCITBUFGAIN_2 ? 2.0f : 0.25f)));
  printk("Calibrated RTIA (first point): |R|=%.2f Ohm, phase=%.3f deg\n\n",
         (double)pBIACfg->RtiaCalTable[0][0],
         (double)(pBIACfg->RtiaCalTable[0][1] * 180.0f / MATH_PI));

  printk(" #    Freq [Hz]      |Z| [Ohm]   Phase[deg]    Real[Ohm]    Imag[Ohm]\n");
  printk("---  -----------  -----------  ----------  -----------  -----------\n");
}

void AD5940_Main(void)
{
  uint32_t temp;

  BIAend = 0;

  AD5940PlatformCfg();
  AD5940BIAStructInit();
  AppBIAInit(AppBuff, APPBUFF_SIZE);
  PrintHeader();
  AppBIACtrl(BIACTRL_START, 0);
  AD5940_ClrMCUIntFlag();

  while (!BIAend) {
    if (AD5940_GetMCUIntFlag()) {
      AD5940_ClrMCUIntFlag();
      temp = APPBUFF_SIZE;
      AppBIAISR(AppBuff, &temp);
      if (temp > 0) {
        BIAShowResult(AppBuff, temp);
      }
    }
    k_usleep(100);
  }
  BIAend = 0;
  printk("\n=== Sweep complete ===\n");
  AD5940_ShutDownS();
}

void AD5940_GetDefaultSweepConfig(AD5940SweepConfig *config)
{
  if (config == NULL) {
    return;
  }

  config->rcal_ohms = 30.0f;
  config->sweep_enabled = true;
  config->start_hz = 4000.0f;
  config->stop_hz = 198000.0f;
  config->points = DEFAULT_SWEEP_POINTS;
  config->repetitions = DEFAULT_NUM_REPETITIONS;
  config->excitation_mvpp = CONFIG_MYOHM_EXCITATION_MVPP;
}

int AD5940_ReadIdentity(AD5940Identity *identity)
{
  if (identity == NULL) {
    return -EINVAL;
  }

  AD5940_HWReset();
  AD5940_Delay10us(2000);
  AD5940_Initialize();

  identity->adi_id = (uint16_t)AD5940_GetADIID();
  identity->chip_id = (uint16_t)AD5940_GetChipID();

  if (identity->adi_id != AD5940_ADIID) {
    return -ENODEV;
  }

  return 0;
}

int AD5940_RunSweep(const AD5940SweepConfig *config,
                    AD5940MeasurementCallback callback,
                    void *user_data)
{
  AD5940SweepConfig active;

  if (config == NULL) {
    AD5940_GetDefaultSweepConfig(&active);
  } else {
    active = *config;
  }

  if (active.points < 2 || active.points > AD5940_MAX_SWEEP_POINTS ||
      active.repetitions == 0 || active.repetitions > 10 ||
      active.rcal_ohms <= 0.0f || active.start_hz <= 0.0f ||
      active.stop_hz <= active.start_hz || active.stop_hz > AD5940_MAX_STOP_HZ ||
      active.excitation_mvpp < AD5940_EXCITATION_MVPP_MIN ||
      active.excitation_mvpp > AD5940_EXCITATION_MVPP_MAX) {
    return -EINVAL;
  }

  cfgRcalVal = active.rcal_ohms;
  cfgSweepEn = active.sweep_enabled;
  cfgSweepStart = active.start_hz;
  cfgSweepStop = active.stop_hz;
  cfgSweepPoints = active.points;
  cfgNumRepetitions = active.repetitions;
  cfgNumOfData = (int32_t)(active.points * active.repetitions);
  cfgExcitationMvpp = (float)active.excitation_mvpp;

  AppBIACfg_Type *bia_cfg;
  if (AppBIAGetCfg(&bia_cfg) == AD5940ERR_OK && bia_cfg != NULL) {
    bia_cfg->BIAInited = bFALSE;
    bia_cfg->ReDoRtiaCal = bTRUE;
    bia_cfg->bParaChanged = bTRUE;
    bia_cfg->StopRequired = bFALSE;
    bia_cfg->FifoDataCount = 0;
    bia_cfg->SweepCfg.SweepIndex = 0;
  }

  g_measurement_callback = callback;
  g_measurement_callback_user_data = user_data;
  AD5940_Main();
  g_measurement_callback = NULL;
  g_measurement_callback_user_data = NULL;

  return 0;
}

/**
 * @}
 * @}
 * */
