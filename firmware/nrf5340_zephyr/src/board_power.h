#ifndef BOARD_POWER_H
#define BOARD_POWER_H

#include <stdint.h>

enum board_power_button_event {
	BOARD_POWER_BUTTON_SHORT_PRESS,
	BOARD_POWER_BUTTON_LONG_PRESS_READY,
	BOARD_POWER_BUTTON_SHUTDOWN_RELEASED,
};

typedef void (*board_power_button_callback_t)(enum board_power_button_event event);

void board_power_init(void);
void board_power_set_button_callback(board_power_button_callback_t callback);
int board_power_read_battery(uint16_t *voltage_mv, uint16_t *percentage);
int board_power_enter_ship_mode(void);

#endif
