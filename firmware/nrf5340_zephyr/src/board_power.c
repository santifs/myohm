#include "board_power.h"

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/mfd/npm13xx.h>
#include <zephyr/drivers/regulator.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>

LOG_MODULE_REGISTER(board_power, LOG_LEVEL_INF);

#define PMIC_NODE DT_NODELABEL(npm1304_pmic)
#define CHARGER_NODE DT_NODELABEL(npm1304_charger)
#define REGULATORS_NODE DT_NODELABEL(npm1304_regulators)

#define POWER_BUTTON_LONG_PRESS_MS 3000
#define POWER_BUTTON_SHIP_AFTER_RELEASE_MS 250

static const struct device *const pmic = DEVICE_DT_GET(PMIC_NODE);
static const struct device *const charger = DEVICE_DT_GET(CHARGER_NODE);
static const struct device *const regulators = DEVICE_DT_GET(REGULATORS_NODE);

static struct gpio_callback pmic_event_cb;
static struct k_work_delayable long_press_work;
static struct k_work_delayable ship_after_release_work;
static bool vbus_connected;
static bool button_pressed;
static bool long_press_ready;
static board_power_button_callback_t button_callback;
static int64_t last_button_release_handled_ms;

void board_power_set_button_callback(board_power_button_callback_t callback)
{
	button_callback = callback;
}

static int board_power_refresh_vbus_state(void)
{
	struct sensor_value val;
	int ret;

	if (!device_is_ready(charger)) {
		return -ENODEV;
	}

	ret = sensor_attr_get(charger, SENSOR_CHAN_CURRENT, SENSOR_ATTR_UPPER_THRESH, &val);
	if (ret < 0) {
		return ret;
	}

	vbus_connected = (val.val1 != 0) || (val.val2 != 0);
	return 0;
}

int board_power_enter_ship_mode(void)
{
	int ret;

	if (!device_is_ready(regulators)) {
		LOG_WRN("nPM1304 regulators are not ready");
		return -ENODEV;
	}

	if (vbus_connected) {
		LOG_WRN("Ship mode entry blocked while USB VBUS is present");
		return -EBUSY;
	}

	LOG_INF("Entering nPM1304 ship mode");
	ret = regulator_parent_ship_mode(regulators);
	if (ret < 0) {
		LOG_ERR("Could not enter nPM1304 ship mode: %d", ret);
	}

	return ret;
}

static void board_power_handle_button_release(int64_t press_duration_ms)
{
	int64_t now_ms = k_uptime_get();

	button_pressed = false;
	(void)k_work_cancel_delayable(&long_press_work);

	if ((now_ms - last_button_release_handled_ms) < 250) {
		LOG_INF("Ignoring duplicate button release event");
		return;
	}
	last_button_release_handled_ms = now_ms;

	if (long_press_ready || press_duration_ms >= POWER_BUTTON_LONG_PRESS_MS) {
		LOG_INF("nPM1304 shiphold long press released; scheduling ship mode");
		if (button_callback != NULL) {
			button_callback(BOARD_POWER_BUTTON_SHUTDOWN_RELEASED);
		}
		(void)k_work_reschedule(&ship_after_release_work,
					 K_MSEC(POWER_BUTTON_SHIP_AFTER_RELEASE_MS));
		long_press_ready = false;
	} else if (button_callback != NULL) {
		button_callback(BOARD_POWER_BUTTON_SHORT_PRESS);
	}
}

static void long_press_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (!button_pressed || long_press_ready) {
		return;
	}

	LOG_INF("nPM1304 shiphold long press threshold reached");
	long_press_ready = true;

	if (button_callback != NULL) {
		button_callback(BOARD_POWER_BUTTON_LONG_PRESS_READY);
	}
}

static void ship_after_release_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	if (button_pressed) {
		LOG_WRN("Ship mode entry deferred because SHPHLD is still pressed");
		return;
	}

	(void)board_power_enter_ship_mode();
}

static void pmic_event_handler(const struct device *dev, struct gpio_callback *cb, uint32_t pins)
{
	static int64_t press_started_ms;
	int64_t press_duration_ms;

	ARG_UNUSED(dev);
	ARG_UNUSED(cb);

	if (pins & BIT(NPM13XX_EVENT_SHIPHOLD_PRESS)) {
		press_started_ms = k_uptime_get();
		button_pressed = true;
		long_press_ready = false;
		(void)k_work_cancel_delayable(&ship_after_release_work);
		(void)k_work_reschedule(&long_press_work, K_MSEC(POWER_BUTTON_LONG_PRESS_MS));
		LOG_INF("nPM1304 shiphold press");
	}

	if (pins & BIT(NPM13XX_EVENT_SHIPHOLD_RELEASE)) {
		press_duration_ms = k_uptime_get() - press_started_ms;
		LOG_INF("nPM1304 shiphold release after %lld ms", press_duration_ms);

		board_power_handle_button_release(press_duration_ms);
	}

	if (pins & BIT(NPM13XX_EVENT_VBUS_DETECTED)) {
		vbus_connected = true;
		LOG_INF("USB VBUS detected");
	}

	if (pins & BIT(NPM13XX_EVENT_VBUS_REMOVED)) {
		vbus_connected = false;
		LOG_INF("USB VBUS removed");
	}
}

void board_power_init(void)
{
	int ret;

	if (!device_is_ready(pmic)) {
		LOG_ERR("nPM1304 PMIC is not ready");
		return;
	}

	LOG_INF("nPM1304 PMIC ready");

	if (device_is_ready(regulators)) {
		LOG_INF("nPM1304 regulators ready");
	} else {
		LOG_WRN("nPM1304 regulators are not ready");
	}

	k_work_init_delayable(&long_press_work, long_press_work_handler);
	k_work_init_delayable(&ship_after_release_work, ship_after_release_work_handler);

	gpio_init_callback(&pmic_event_cb, pmic_event_handler,
			   BIT(NPM13XX_EVENT_SHIPHOLD_PRESS) |
				   BIT(NPM13XX_EVENT_SHIPHOLD_RELEASE) |
				   BIT(NPM13XX_EVENT_VBUS_DETECTED) |
				   BIT(NPM13XX_EVENT_VBUS_REMOVED));
	ret = mfd_npm13xx_add_callback(pmic, &pmic_event_cb);
	if (ret < 0) {
		LOG_WRN("Could not register nPM1304 event callback: %d", ret);
	}

	if (device_is_ready(charger)) {
		/* Research candidate: explicitly clear a retained charging state.
         * R7 is a fixed resistor, not a battery temperature sensor.
         * This does not protect the interval before firmware initialization.
         */
        const struct sensor_value charge_disabled = { .val1 = 0, .val2 = 0 };
        ret = sensor_attr_set(charger, SENSOR_CHAN_GAUGE_DESIRED_CHARGING_CURRENT,
                              SENSOR_ATTR_CONFIGURATION, &charge_disabled);
        if (ret < 0) {
            LOG_ERR("Could not inhibit charging; disconnect battery/USB: %d", ret);
        } else {
            LOG_INF("Battery charging inhibited pending cell/NTC qualification");
        }
		ret = board_power_refresh_vbus_state();
		if (ret < 0) {
			LOG_WRN("Could not read initial USB VBUS state: %d", ret);
		} else {
			LOG_INF("Initial USB VBUS state: %s", vbus_connected ? "connected" : "removed");
		}
	} else {
		LOG_WRN("nPM1304 charger is not ready");
	}
}

int board_power_read_battery(uint16_t *voltage_mv, uint16_t *percentage)
{
	struct sensor_value voltage;
	int ret;
	int32_t mv;
	int32_t pct;

	if (voltage_mv == NULL || percentage == NULL) {
		return -EINVAL;
	}

	if (!device_is_ready(charger)) {
		return -ENODEV;
	}

	ret = sensor_sample_fetch(charger);
	if (ret < 0) {
		return ret;
	}

	ret = sensor_channel_get(charger, SENSOR_CHAN_GAUGE_VOLTAGE, &voltage);
	if (ret < 0) {
		return ret;
	}

	mv = (voltage.val1 * 1000) + (voltage.val2 / 1000);
	mv = CLAMP(mv, 0, UINT16_MAX);

	/* Conservative LiPo estimate until a fuel-gauge model is added. */
	pct = ((mv - 3300) * 100) / (4200 - 3300);
	pct = CLAMP(pct, 0, 100);

	*voltage_mv = (uint16_t)mv;
	*percentage = (uint16_t)pct;

	return 0;
}
