/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Two-wire electrode contact check for the Myohm AD5941 front end.
 *
 * Board topology (hardware/mainboard, sheet AD5941):
 *   CE0  - RL1 1 kohm - C5 4.7 uF - I+  (CN1.1)
 *   AIN1 - C4 4.7 uF            - I-  (CN1.4)
 *   AIN2 - C3 4.7 uF            - V+  (CN1.2)
 *   AIN3 - C2 4.7 uF            - V-  (CN1.3)
 *   RCAL0 - RCAL1 30 ohm 0.1 %; DE0, SE0, RE0 and AIN0 are not connected.
 *
 * For each pair the excitation buffer drives one pin (D and P switches on
 * the same pin) and the HSTIA holds the other pin at virtual ground (N and T
 * switches on the same pin). The ADC measures the forced voltage between the
 * P and N nodes and then the HSTIA output. The same measurement on RCAL gives
 * the RTIA transfer, so
 *
 *   Z = RCAL * (V_pair / Vtia_pair) * (Vtia_rcal / V_rcal)
 *
 * which cancels RTIA, PGA and DFT scaling (ratio method of the ADI impedance
 * examples). RL1 (for pairs that include I+) and the two coupling capacitors
 * are then subtracted with their nominal values.
 *
 * The excitation uses HSDACGAIN_0P2 and EXCITBUFGAIN_0P25, so the pins see at
 * most 40 mVpp regardless of CONFIG_MYOHM_EXCITATION_MVPP. Pairs without RL1
 * have no series resistor on the board; the low amplitude keeps their current
 * at 0.2 mApp (71 uA rms) for a 200 ohm electrode path.
 */

#include "contact_check.h"

#include <errno.h>
#include <math.h>
#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/printk.h>

#include "ad5940.h"
#include "AD5940Main.h"

#define CONTACT_SYS_CLK_HZ         16000000.0f /* HFOSC in 16 MHz mode, as in AD5940PlatformCfg */
#define CONTACT_RL1_OHM            1000.0f     /* RL1 nominal; tolerance not given in the BOM */
#define CONTACT_COUPLING_CAP_F     4.7e-6f     /* C2..C5 nominal */
#define CONTACT_PAIR_AMP_WORD      2047U       /* 800 mVpp * 0.2 * 0.25 = 40 mVpp at the pins */
#define CONTACT_RCAL_AMP_WORD      1024U       /* ~20 mVpp across RCAL, ~0.67 Vpp at the HSTIA */
#define CONTACT_PAIR_FULL_MVPP     40.0f
#define CONTACT_RCAL_EXC_MVPP      (CONTACT_PAIR_FULL_MVPP * (float)CONTACT_RCAL_AMP_WORD / 2047.0f)
#define CONTACT_RTIA_OHM           1000.0f     /* HSTIARTIA_1K, used only for the range check */
#define CONTACT_TIA_LINEAR_MVPP    1440.0f     /* 80 % of the 1.8 Vpp HSTIA swing (ADI guidance) */
#define CONTACT_SETTLE_FIRST_MS    30          /* ~3 tau of 5 kohm with 2.35 uF in series */
#define CONTACT_SETTLE_NEXT_MS     5
#define CONTACT_RCAL_SETTLE_MS     2
#define CONTACT_MUX_SETTLE_US      100
#define CONTACT_DFT_TIMEOUT_MS     250

#define CONTACT_PI_F 3.14159265f

static const float contact_freqs_hz[CONTACT_CHECK_FREQ_COUNT] = {10000.0f, 100000.0f};

struct contact_route {
	uint8_t pair;
	uint32_t dswitch;
	uint32_t pswitch;
	uint32_t nswitch;
	uint32_t tswitch;
	bool through_rl1;
};

/* Every routed pin has a D/P or N/T switch on the AD5941 matrix (ad5940.h
 * SWD_/SWP_/SWN_/SWT_ constants), so all four pairs are reachable. */
static const struct contact_route contact_routes[CONTACT_PAIR_COUNT] = {
	{CONTACT_PAIR_IP_IM, SWD_CE0,  SWP_CE0,  SWN_AIN1, SWT_AIN1 | SWT_TRTIA, true},
	{CONTACT_PAIR_VP_VM, SWD_AIN2, SWP_AIN2, SWN_AIN3, SWT_AIN3 | SWT_TRTIA, false},
	{CONTACT_PAIR_IP_VP, SWD_CE0,  SWP_CE0,  SWN_AIN2, SWT_AIN2 | SWT_TRTIA, true},
	{CONTACT_PAIR_IM_VM, SWD_AIN3, SWP_AIN3, SWN_AIN1, SWT_AIN1 | SWT_TRTIA, false},
};

static const struct contact_route contact_rcal_route = {
	0xff, SWD_RCAL0, SWP_RCAL0, SWN_RCAL1, SWT_RCAL1 | SWT_TRTIA, false,
};

struct cplx {
	float re;
	float im;
};

static struct cplx cplx_div(struct cplx a, struct cplx b)
{
	float den = b.re * b.re + b.im * b.im;
	struct cplx out = {
		(a.re * b.re + a.im * b.im) / den,
		(a.im * b.re - a.re * b.im) / den,
	};

	return out;
}

static struct cplx cplx_mul(struct cplx a, struct cplx b)
{
	struct cplx out = {
		a.re * b.re - a.im * b.im,
		a.re * b.im + a.im * b.re,
	};

	return out;
}

static float cplx_abs(struct cplx a)
{
	return sqrtf(a.re * a.re + a.im * a.im);
}

static int32_t sign_extend_18(uint32_t raw)
{
	raw &= 0x3ffff;
	if (raw & (1UL << 17)) {
		raw |= 0xfffc0000;
	}
	return (int32_t)raw;
}

static void configure_afe(void)
{
	AFERefCfg_Type aferef_cfg;
	DSPCfg_Type dsp_cfg;

	memset(&aferef_cfg, 0, sizeof(aferef_cfg));
	aferef_cfg.HpBandgapEn = bTRUE;
	aferef_cfg.Hp1V1BuffEn = bTRUE;
	aferef_cfg.Hp1V8BuffEn = bTRUE;
	AD5940_REFCfgS(&aferef_cfg);

	memset(&dsp_cfg, 0, sizeof(dsp_cfg));
	dsp_cfg.ADCBaseCfg.ADCMuxP = ADCMUXP_HSTIA_P;
	dsp_cfg.ADCBaseCfg.ADCMuxN = ADCMUXN_HSTIA_N;
	dsp_cfg.ADCBaseCfg.ADCPga = ADCPGA_1P5;
	dsp_cfg.ADCFilterCfg.ADCAvgNum = ADCAVGNUM_16;
	dsp_cfg.ADCFilterCfg.ADCRate = ADCRATE_800KHZ;
	dsp_cfg.ADCFilterCfg.ADCSinc2Osr = ADCSINC2OSR_22;
	dsp_cfg.ADCFilterCfg.ADCSinc3Osr = ADCSINC3OSR_2;
	dsp_cfg.ADCFilterCfg.BpSinc3 = bFALSE;
	dsp_cfg.ADCFilterCfg.BpNotch = bTRUE;
	dsp_cfg.ADCFilterCfg.Sinc2NotchEnable = bTRUE;
	dsp_cfg.ADCFilterCfg.Sinc2NotchClkEnable = bTRUE;
	dsp_cfg.ADCFilterCfg.Sinc3ClkEnable = bTRUE;
	dsp_cfg.ADCFilterCfg.WGClkEnable = bTRUE;
	dsp_cfg.ADCFilterCfg.DFTClkEnable = bTRUE;
	dsp_cfg.DftCfg.DftNum = DFTNUM_8192;
	dsp_cfg.DftCfg.DftSrc = DFTSRC_SINC3;
	dsp_cfg.DftCfg.HanWinEn = bTRUE;
	AD5940_DSPCfgS(&dsp_cfg);

	AD5940_AFECtrlS(AFECTRL_HPREFPWR | AFECTRL_HSTIAPWR | AFECTRL_INAMPPWR |
			AFECTRL_EXTBUFPWR | AFECTRL_DACREFPWR | AFECTRL_HSDACPWR |
			AFECTRL_SINC2NOTCH, bTRUE);
}

static void configure_loop(const struct contact_route *route, float freq_hz, uint32_t amp_word)
{
	HSLoopCfg_Type hs_loop;

	memset(&hs_loop, 0, sizeof(hs_loop));
	hs_loop.HsDacCfg.ExcitBufGain = EXCITBUFGAIN_0P25;
	hs_loop.HsDacCfg.HsDacGain = HSDACGAIN_0P2;
	hs_loop.HsDacCfg.HsDacUpdateRate = 7;

	hs_loop.HsTiaCfg.DiodeClose = bFALSE;
	hs_loop.HsTiaCfg.HstiaBias = HSTIABIAS_1P1;
	hs_loop.HsTiaCfg.HstiaCtia = 16;
	hs_loop.HsTiaCfg.HstiaDeRload = HSTIADERLOAD_OPEN;
	hs_loop.HsTiaCfg.HstiaDeRtia = HSTIADERTIA_OPEN;
	hs_loop.HsTiaCfg.HstiaRtiaSel = HSTIARTIA_1K;

	hs_loop.SWMatCfg.Dswitch = route->dswitch;
	hs_loop.SWMatCfg.Pswitch = route->pswitch;
	hs_loop.SWMatCfg.Nswitch = route->nswitch;
	hs_loop.SWMatCfg.Tswitch = route->tswitch;

	hs_loop.WgCfg.WgType = WGTYPE_SIN;
	hs_loop.WgCfg.GainCalEn = bFALSE;
	hs_loop.WgCfg.OffsetCalEn = bFALSE;
	hs_loop.WgCfg.SinCfg.SinFreqWord = AD5940_WGFreqWordCal(freq_hz, CONTACT_SYS_CLK_HZ);
	hs_loop.WgCfg.SinCfg.SinAmplitudeWord = amp_word;
	hs_loop.WgCfg.SinCfg.SinOffsetWord = 0;
	hs_loop.WgCfg.SinCfg.SinPhaseWord = 0;
	AD5940_HSLoopCfgS(&hs_loop);
}

static void float_switches(void)
{
	SWMatrixCfg_Type sw_cfg = {
		.Dswitch = SWD_OPEN,
		.Pswitch = SWP_PL | SWP_PL2,
		.Nswitch = SWN_NL | SWN_NL2,
		.Tswitch = SWT_TRTIA,
	};

	AD5940_SWMatrixCfgS(&sw_cfg);
}

/* One DFT on the selected ADC inputs. Returns the phasor with the imaginary
 * sign corrected (the AD594x register holds its opposite, see AD5940_HSRtiaCal). */
static int dft_measure(uint32_t mux_p, uint32_t mux_n, struct cplx *out)
{
	int64_t deadline;

	AD5940_ADCMuxCfgS(mux_p, mux_n);
	k_busy_wait(CONTACT_MUX_SETTLE_US);
	AD5940_INTCClrFlag(AFEINTSRC_DFTRDY);
	AD5940_AFECtrlS(AFECTRL_ADCCNV | AFECTRL_DFT, bTRUE);

	deadline = k_uptime_get() + CONTACT_DFT_TIMEOUT_MS;
	while (AD5940_INTCTestFlag(AFEINTC_1, AFEINTSRC_DFTRDY) == bFALSE) {
		if (k_uptime_get() > deadline) {
			AD5940_AFECtrlS(AFECTRL_ADCCNV | AFECTRL_DFT, bFALSE);
			return -ETIMEDOUT;
		}
		k_usleep(500);
	}
	AD5940_AFECtrlS(AFECTRL_ADCCNV | AFECTRL_DFT, bFALSE);
	AD5940_INTCClrFlag(AFEINTSRC_DFTRDY);

	out->re = (float)sign_extend_18(AD5940_ReadAfeResult(AFERESULT_DFTREAL));
	out->im = -(float)sign_extend_18(AD5940_ReadAfeResult(AFERESULT_DFTIMAGE));
	return 0;
}

/* Voltage between the P and N nodes and HSTIA output for the active route. */
static int measure_route(struct cplx *v, struct cplx *vtia)
{
	int ret = dft_measure(ADCMUXP_P_NODE, ADCMUXN_N_NODE, v);

	if (ret == 0) {
		ret = dft_measure(ADCMUXP_HSTIA_P, ADCMUXN_HSTIA_N, vtia);
	}
	return ret;
}

struct rcal_ref {
	struct cplx v;
	struct cplx vtia;
	bool valid;
};

static void fill_entry(struct contact_check_entry *entry, const struct contact_route *route,
		       float freq_hz, struct cplx v, struct cplx vtia,
		       const struct rcal_ref *rcal, float rcal_ohms, uint32_t threshold)
{
	float omega = 2.0f * CONTACT_PI_F * freq_hz;
	/* HSTIA swing during the RCAL step: 20 mVpp / RCAL * 1 kohm (~0.67 Vpp). */
	float rcal_tia_mvpp = CONTACT_RCAL_EXC_MVPP / rcal_ohms * CONTACT_RTIA_OHM;
	float vtia_abs = cplx_abs(vtia);
	float tia_mvpp;
	struct cplx z;

	if (vtia_abs == 0.0f) {
		/* No measurable current: open circuit at this resolution. */
		entry->flags |= CONTACT_ENTRY_FLAG_OPEN | CONTACT_ENTRY_FLAG_HIGH;
		entry->magnitude_ohm = INFINITY;
		entry->phase_deg = 0.0f;
		return;
	}

	/* Z = RCAL * (V / Vtia) * (Vtia_rcal / V_rcal) */
	z = cplx_mul(cplx_div(v, vtia), cplx_div(rcal->vtia, rcal->v));
	z.re *= rcal_ohms;
	z.im *= rcal_ohms;

	/* Remove the board series elements: RL1 and two 4.7 uF capacitors. */
	if (route->through_rl1) {
		z.re -= CONTACT_RL1_OHM;
	}
	z.im += 2.0f / (omega * CONTACT_COUPLING_CAP_F);

	entry->magnitude_ohm = cplx_abs(z);
	entry->phase_deg = atan2f(z.im, z.re) * 180.0f / CONTACT_PI_F;

	/* DFT magnitudes scale linearly, so the RCAL step calibrates the swing. */
	tia_mvpp = vtia_abs / cplx_abs(rcal->vtia) * rcal_tia_mvpp;
	if (tia_mvpp > CONTACT_TIA_LINEAR_MVPP) {
		entry->flags |= CONTACT_ENTRY_FLAG_OVERRANGE;
	}

	if (!isfinite(entry->magnitude_ohm)) {
		entry->flags |= CONTACT_ENTRY_FLAG_INVALID;
	} else if (entry->magnitude_ohm > (float)threshold) {
		entry->flags |= CONTACT_ENTRY_FLAG_HIGH;
	}
}

static void init_result(struct contact_check_result *result)
{
	memset(result, 0, sizeof(*result));
	result->threshold_ohm = CONFIG_MYOHM_CONTACT_HIGH_OHMS;
	result->count = CONTACT_CHECK_MAX_ENTRIES;
	for (size_t p = 0; p < CONTACT_PAIR_COUNT; p++) {
		for (size_t f = 0; f < CONTACT_CHECK_FREQ_COUNT; f++) {
			struct contact_check_entry *entry =
				&result->entries[p * CONTACT_CHECK_FREQ_COUNT + f];

			entry->pair = contact_routes[p].pair;
			entry->frequency_hz = contact_freqs_hz[f];
			entry->magnitude_ohm = NAN;
			entry->phase_deg = NAN;
			entry->flags = CONTACT_ENTRY_FLAG_INVALID;
		}
	}
}

static void finish_flags(struct contact_check_result *result)
{
	for (size_t i = 0; i < result->count; i++) {
		uint8_t flags = result->entries[i].flags;

		if (flags & CONTACT_ENTRY_FLAG_HIGH) {
			result->flags |= CONTACT_FLAG_ANY_HIGH;
		}
		if (flags & (CONTACT_ENTRY_FLAG_INVALID | CONTACT_ENTRY_FLAG_OVERRANGE)) {
			result->flags |= CONTACT_FLAG_ANY_INVALID;
		}
	}
}

static void shutdown_afe(void)
{
	AD5940_AFECtrlS(AFECTRL_ADCCNV | AFECTRL_DFT | AFECTRL_WG | AFECTRL_ADCPWR, bFALSE);
	float_switches();
	AD5940_INTCClrFlag(AFEINTSRC_ALLINT);
	AD5940_ShutDownS();
	(void)AD5940_ClrMCUIntFlag();
}

int contact_check_run(float rcal_ohms, struct contact_check_result *result)
{
	struct rcal_ref rcal[CONTACT_CHECK_FREQ_COUNT];
	int ret = 0;

	if (result == NULL) {
		return -EINVAL;
	}
	init_result(result);
	if (!(rcal_ohms > 0.0f)) {
		result->flags |= CONTACT_FLAG_AFE_ERROR | CONTACT_FLAG_ANY_INVALID;
		return -EINVAL;
	}

	AD5940PlatformCfg();
	if (AD5940_GetADIID() != AD5940_ADIID) {
		result->flags |= CONTACT_FLAG_AFE_ERROR | CONTACT_FLAG_ANY_INVALID;
		return -ENODEV;
	}

	/* Results are read from the DFT registers; keep them out of the FIFO so
	 * the data-FIFO interrupt used by the sweep does not fire. */
	AD5940_FIFOCtrlS(FIFOSRC_DFT, bFALSE);
	AD5940_AFEPwrBW(AFEPWR_LP, AFEBW_250KHZ);
	configure_afe();

	/* RCAL reference at both frequencies. */
	for (size_t f = 0; f < CONTACT_CHECK_FREQ_COUNT && ret == 0; f++) {
		configure_loop(&contact_rcal_route, contact_freqs_hz[f], CONTACT_RCAL_AMP_WORD);
		AD5940_AFECtrlS(AFECTRL_WG | AFECTRL_ADCPWR, bTRUE);
		k_msleep(CONTACT_RCAL_SETTLE_MS);
		ret = measure_route(&rcal[f].v, &rcal[f].vtia);
		rcal[f].valid = ret == 0 && cplx_abs(rcal[f].v) > 0.0f &&
				cplx_abs(rcal[f].vtia) > 0.0f;
		if (ret == 0 && !rcal[f].valid) {
			ret = -EIO;
		}
	}
	if (ret != 0) {
		printk("Contact check: RCAL reference failed (%d)\n", ret);
		result->flags |= CONTACT_FLAG_AFE_ERROR | CONTACT_FLAG_ANY_INVALID;
		shutdown_afe();
		return ret;
	}

	for (size_t p = 0; p < CONTACT_PAIR_COUNT; p++) {
		const struct contact_route *route = &contact_routes[p];

		for (size_t f = 0; f < CONTACT_CHECK_FREQ_COUNT; f++) {
			struct contact_check_entry *entry =
				&result->entries[p * CONTACT_CHECK_FREQ_COUNT + f];
			struct cplx v;
			struct cplx vtia;
			int meas_ret;

			configure_loop(route, contact_freqs_hz[f], CONTACT_PAIR_AMP_WORD);
			AD5940_AFECtrlS(AFECTRL_WG | AFECTRL_ADCPWR, bTRUE);
			/* The first frequency of a pair also lets the coupling
			 * capacitors settle after the switch change. */
			k_msleep(f == 0 ? CONTACT_SETTLE_FIRST_MS : CONTACT_SETTLE_NEXT_MS);

			meas_ret = measure_route(&v, &vtia);
			if (meas_ret != 0) {
				/* Remaining entries stay INVALID. */
				printk("Contact check: DFT failed (%d)\n", meas_ret);
				result->flags |= CONTACT_FLAG_AFE_ERROR;
				ret = meas_ret;
				goto done;
			}
			entry->flags = 0;
			fill_entry(entry, route, contact_freqs_hz[f], v, vtia, &rcal[f],
				   rcal_ohms, result->threshold_ohm);
			printk("Contact pair %u @ %.0f Hz: |Z|=%.1f Ohm phase=%.2f deg flags=0x%02x\n",
			       entry->pair, (double)entry->frequency_hz,
			       (double)entry->magnitude_ohm, (double)entry->phase_deg,
			       entry->flags);
		}
		AD5940_AFECtrlS(AFECTRL_WG | AFECTRL_ADCPWR, bFALSE);
	}

done:
	shutdown_afe();
	finish_flags(result);
	return ret;
}

static void put_le_float(float value, uint8_t *dst)
{
	uint32_t raw;

	memcpy(&raw, &value, sizeof(raw));
	sys_put_le32(raw, dst);
}

size_t contact_check_encode(const struct contact_check_result *result,
			    uint8_t *buf, size_t buf_len)
{
	size_t offset = 0;

	if (result == NULL || buf == NULL ||
	    buf_len < CONTACT_CHECK_HEADER_SIZE + (size_t)result->count * CONTACT_CHECK_ENTRY_SIZE) {
		return 0;
	}

	buf[offset++] = CONTACT_CHECK_PAYLOAD_VERSION;
	buf[offset++] = result->count;
	sys_put_le16(result->flags, &buf[offset]);
	offset += 2;
	sys_put_le32(result->threshold_ohm, &buf[offset]);
	offset += 4;

	for (size_t i = 0; i < result->count; i++) {
		const struct contact_check_entry *entry = &result->entries[i];

		buf[offset++] = entry->pair;
		buf[offset++] = entry->flags;
		sys_put_le16(0, &buf[offset]);
		offset += 2;
		put_le_float(entry->frequency_hz, &buf[offset]);
		offset += 4;
		put_le_float(entry->magnitude_ohm, &buf[offset]);
		offset += 4;
		put_le_float(entry->phase_deg, &buf[offset]);
		offset += 4;
	}

	return offset;
}
