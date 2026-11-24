/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Two-wire electrode contact check for the Myohm AD5941 front end.
 * See docs/ble-protocol.md (command 0x0B) for the BLE payload.
 */

#ifndef CONTACT_CHECK_H
#define CONTACT_CHECK_H

#include <stddef.h>
#include <stdint.h>

/* Electrode pairs. Values are part of the BLE payload; do not renumber. */
enum contact_pair {
	CONTACT_PAIR_IP_IM = 0, /* I+ (CE0 via RL1) to I- (AIN1) */
	CONTACT_PAIR_VP_VM = 1, /* V+ (AIN2) to V- (AIN3) */
	CONTACT_PAIR_IP_VP = 2, /* I+ (CE0 via RL1) to V+ (AIN2) */
	CONTACT_PAIR_IM_VM = 3, /* V- (AIN3) to I- (AIN1) */
	CONTACT_PAIR_COUNT,
};

#define CONTACT_CHECK_FREQ_COUNT 2
#define CONTACT_CHECK_MAX_ENTRIES (CONTACT_PAIR_COUNT * CONTACT_CHECK_FREQ_COUNT)

/* Per-entry flags */
#define CONTACT_ENTRY_FLAG_HIGH    0x01 /* |Z| above CONFIG_MYOHM_CONTACT_HIGH_OHMS */
#define CONTACT_ENTRY_FLAG_INVALID 0x02 /* Not measured (AFE error or timeout) */
#define CONTACT_ENTRY_FLAG_OPEN    0x04 /* No measurable current; magnitude is +inf */
#define CONTACT_ENTRY_FLAG_OVERRANGE 0x08 /* HSTIA beyond its linear swing; |Z| unreliable (very low) */

/* Global flags */
#define CONTACT_FLAG_ANY_HIGH      0x0001
#define CONTACT_FLAG_ANY_INVALID   0x0002 /* Any entry INVALID or OVERRANGE */
#define CONTACT_FLAG_AFE_ERROR     0x0004 /* AD5941 not detected or check aborted */

#define CONTACT_CHECK_PAYLOAD_VERSION 1
#define CONTACT_CHECK_HEADER_SIZE 8
#define CONTACT_CHECK_ENTRY_SIZE 16
#define CONTACT_CHECK_PAYLOAD_SIZE \
	(CONTACT_CHECK_HEADER_SIZE + CONTACT_CHECK_MAX_ENTRIES * CONTACT_CHECK_ENTRY_SIZE)

struct contact_check_entry {
	uint8_t pair;
	uint8_t flags;
	float frequency_hz;
	float magnitude_ohm; /* Board series elements already subtracted */
	float phase_deg;
};

struct contact_check_result {
	uint16_t flags;
	uint32_t threshold_ohm;
	uint8_t count;
	struct contact_check_entry entries[CONTACT_CHECK_MAX_ENTRIES];
};

/*
 * Run the check on the AD5941. Blocks for roughly one second. The AFE is
 * reset at the start and left in hibernate; the next sweep reinitializes it.
 * The result is always filled; on AFE failure every entry is marked invalid
 * and a negative errno is returned.
 */
int contact_check_run(float rcal_ohms, struct contact_check_result *result);

/* Serialize a result into the little-endian BLE payload. Returns bytes written. */
size_t contact_check_encode(const struct contact_check_result *result,
			    uint8_t *buf, size_t buf_len);

#endif /* CONTACT_CHECK_H */
