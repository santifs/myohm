#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>
#include <stdio.h>
#include "ad5940.h"
#include "AD5940Main.h"
#include "ble_service.h"
#include "board_power.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

volatile int biomess_boot_ble_ret = -9999;
volatile int biomess_boot_ad5940_ret = -9999;
volatile uint32_t biomess_boot_status_flags;

#define BIOMESS_BOOT_STATUS_BLE_OK BIT(0)
#define BIOMESS_BOOT_STATUS_AD5940_OK BIT(1)

static const struct gpio_dt_spec status_led = GPIO_DT_SPEC_GET_OR(DT_ALIAS(led0), gpios, {0});
static struct k_work button_short_led_work;
static struct k_work button_long_ready_led_work;
static struct k_work button_shutdown_led_work;

static void status_led_init(void)
{
	if (!gpio_is_ready_dt(&status_led)) {
		printf("WARN: status LED GPIO is not ready\n");
		return;
	}

	int ret = gpio_pin_configure_dt(&status_led, GPIO_OUTPUT_INACTIVE);
	if (ret != 0) {
		printf("WARN: status LED config failed: %d\n", ret);
		return;
	}

	printf("Status LED ready on %s.%u\n", status_led.port->name, status_led.pin);
}

static void status_led_set(bool on)
{
	if (!gpio_is_ready_dt(&status_led)) {
		return;
	}

	gpio_pin_set_dt(&status_led, on ? 1 : 0);
}

static void status_led_pattern(uint8_t pulses)
{
	if (!gpio_is_ready_dt(&status_led)) {
		k_msleep(1000);
		return;
	}

	for (uint8_t i = 0; i < pulses; i++) {
		gpio_pin_set_dt(&status_led, 1);
		k_msleep(120);
		gpio_pin_set_dt(&status_led, 0);
		k_msleep(160);
	}

	k_msleep(1200);
}

static void button_short_led_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (!gpio_is_ready_dt(&status_led)) {
		return;
	}

	gpio_pin_set_dt(&status_led, 1);
	k_msleep(90);
	gpio_pin_set_dt(&status_led, 0);
}

static void button_long_ready_led_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (!gpio_is_ready_dt(&status_led)) {
		return;
	}

	gpio_pin_set_dt(&status_led, 1);
	k_msleep(850);
	gpio_pin_set_dt(&status_led, 0);
}

static void button_shutdown_led_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (!gpio_is_ready_dt(&status_led)) {
		return;
	}

	gpio_pin_set_dt(&status_led, 0);
}

static uint8_t status_led_pulses(void)
{
	bool ble_ok = biomess_boot_ble_ret == 0;
	bool ad5940_ok = biomess_boot_ad5940_ret == 0;

	if (ble_ok && ad5940_ok) {
		return 1;
	}
	if (!ble_ok && ad5940_ok) {
		return 2;
	}
	if (ble_ok && !ad5940_ok) {
		return 3;
	}
	return 4;
}

static void power_button_callback(enum board_power_button_event event)
{
	if (event == BOARD_POWER_BUTTON_SHORT_PRESS) {
		k_work_submit(&button_short_led_work);
		ble_service_request_fast_advertising();
	} else if (event == BOARD_POWER_BUTTON_LONG_PRESS_READY) {
		k_work_submit(&button_long_ready_led_work);
	} else if (event == BOARD_POWER_BUTTON_SHUTDOWN_RELEASED) {
		k_work_submit(&button_shutdown_led_work);
	}
}

int main(void)
{
	status_led_init();
	k_work_init(&button_short_led_work, button_short_led_work_handler);
	k_work_init(&button_long_ready_led_work, button_long_ready_led_work_handler);
	k_work_init(&button_shutdown_led_work, button_shutdown_led_work_handler);
	status_led_set(true);

	/* Delay to allow serial connection before output */
	k_msleep(3000);
	printf("\n\n=== AD5940 Bioimpedance Analyzer ===\n");

	board_power_init();
	biomess_boot_ble_ret = ble_service_init();
	if (biomess_boot_ble_ret == 0) {
		biomess_boot_status_flags |= BIOMESS_BOOT_STATUS_BLE_OK;
	} else {
		printf("ERROR: BLE init failed: %d\n", biomess_boot_ble_ret);
	}

	biomess_boot_ad5940_ret = AD5940_MCUResourceInit();
	if (biomess_boot_ad5940_ret == 0) {
		biomess_boot_status_flags |= BIOMESS_BOOT_STATUS_AD5940_OK;
	} else {
		printf("ERROR: MCU resource init failed: %d\n", biomess_boot_ad5940_ret);
	}

	board_power_set_button_callback(power_button_callback);
	status_led_set(false);
	k_msleep(250);
	status_led_pattern(status_led_pulses());
	printf("Ready. Connect with the BioMess app and send BLE command 0x01.\n");

	k_sleep(K_FOREVER);

	return 0;
}
