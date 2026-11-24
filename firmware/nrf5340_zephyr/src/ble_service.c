#include "ble_service.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gap.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/util.h>

#include "AD5940Main.h"
#include "board_power.h"
#include "contact_check.h"

LOG_MODULE_REGISTER(ble_service, LOG_LEVEL_INF);

#define UUID16_BASE(uuid16) BT_UUID_128_ENCODE(uuid16, 0x0000, 0x1000, 0x8000, 0x00805f9b34fb)

#define UUID_CONTROL_SERVICE UUID16_BASE(0x0000af00)
#define UUID_CONFIG_SERVICE  UUID16_BASE(0x0000af01)
#define UUID_DATA_SERVICE    UUID16_BASE(0x0000af02)
#define UUID_ENV_SERVICE     UUID16_BASE(0x0000af03)

#define UUID_CONTROL_COMMAND UUID16_BASE(0x0000c000)
#define UUID_SERIAL_NUMBER   UUID16_BASE(0x0000c001)
#define UUID_RCAL            UUID16_BASE(0x0000c011)
#define UUID_SWEEP_ENABLE    UUID16_BASE(0x0000c012)
#define UUID_SWEEP_START     UUID16_BASE(0x0000c013)
#define UUID_SWEEP_STOP      UUID16_BASE(0x0000c014)
#define UUID_SWEEP_POINTS    UUID16_BASE(0x0000c015)
#define UUID_NUM_REPS        UUID16_BASE(0x0000c017)
#define UUID_EXCITATION      UUID16_BASE(0x0000c018)
#define UUID_IMU_QUAT        UUID16_BASE(0x0000c201)
#define UUID_BATTERY_LEVEL   UUID16_BASE(0x0000c202)
#define UUID_IMU_Q_VARIANCE  UUID16_BASE(0x0000c203)

#define COMMAND_MEASUREMENT      0x01
#define COMMAND_BATTERY_MANUAL   0x02
#define COMMAND_IMU_SINGLE       0x03
#define COMMAND_IMU_STATS        0x04
#define COMMAND_START_AUTO_MODE  0x05
#define COMMAND_STOP_AUTO_MODE   0x06
#define COMMAND_GET_STORED_COUNT 0x07
#define COMMAND_GET_STORED_BATCH 0x08
#define COMMAND_CLEAR_STORED     0x09
#define COMMAND_HEALTH_CHECK     0x0a
#define COMMAND_CONTACT_CHECK    0x0b
#define COMMAND_LED_BLINK        100

#define COMMAND_QUEUE_LEN 8
#define COMMAND_PAYLOAD_MAX 8
#define MEASUREMENT_THREAD_STACK 6144
#define MEASUREMENT_THREAD_PRIORITY 5
#define STORED_REPETITIONS 5
#define STORED_POINTS_PER_REP 48
#define STORED_METADATA_SIZE 12
#define STORED_QUATERNION_SIZE (STORED_REPETITIONS * 4 * sizeof(float))
#define STORED_RECORD_SIZE (STORED_METADATA_SIZE + \
			    (STORED_REPETITIONS * STORED_POINTS_PER_REP * 12) + \
			    STORED_QUATERNION_SIZE + sizeof(uint16_t))
#define STORED_RECORD_CAPACITY 4
#define AUTO_MODE_DEFAULT_INTERVAL_S 300
#define AUTO_MODE_MIN_INTERVAL_S 60
#define AUTO_MODE_MAX_INTERVAL_S 3600
#define ADV_FAST_WINDOW_S 60
#define ADV_SLOW_INTERVAL_MIN 1600
#define ADV_SLOW_INTERVAL_MAX 1920
#define CONN_MEASUREMENT_SETTLE_MS 350
#define HEALTH_FLAG_PMIC_OK BIT(0)
#define HEALTH_FLAG_AD5940_ADIID_OK BIT(1)
#define HEALTH_FLAG_AD5940_CHIPID_KNOWN BIT(2)
#define HEALTH_AD5940_ADIID_EXPECTED 0x4144
#define HEALTH_AD5940_CHIPID_PART_MASK 0xfff0
#define HEALTH_AD5940_CHIPID_PART_EXPECTED 0x5500

struct ble_command {
	uint8_t opcode;
	uint8_t payload_len;
	uint8_t payload[COMMAND_PAYLOAD_MAX];
};

struct measurement_stream {
	uint8_t data[244];
	size_t offset;
	AD5940SweepConfig config;
};

struct stored_record {
	uint8_t bytes[STORED_RECORD_SIZE];
};

enum advertising_mode {
	ADVERTISING_FAST,
	ADVERTISING_SLOW,
};

static const struct bt_uuid_128 control_service_uuid = BT_UUID_INIT_128(UUID_CONTROL_SERVICE);
static const struct bt_uuid_128 config_service_uuid = BT_UUID_INIT_128(UUID_CONFIG_SERVICE);
static const struct bt_uuid_128 data_service_uuid = BT_UUID_INIT_128(UUID_DATA_SERVICE);
static const struct bt_uuid_128 env_service_uuid = BT_UUID_INIT_128(UUID_ENV_SERVICE);

static const struct bt_uuid_128 control_command_uuid = BT_UUID_INIT_128(UUID_CONTROL_COMMAND);
static const struct bt_uuid_128 serial_number_uuid = BT_UUID_INIT_128(UUID_SERIAL_NUMBER);
static const struct bt_uuid_128 rcal_uuid = BT_UUID_INIT_128(UUID_RCAL);
static const struct bt_uuid_128 sweep_enable_uuid = BT_UUID_INIT_128(UUID_SWEEP_ENABLE);
static const struct bt_uuid_128 sweep_start_uuid = BT_UUID_INIT_128(UUID_SWEEP_START);
static const struct bt_uuid_128 sweep_stop_uuid = BT_UUID_INIT_128(UUID_SWEEP_STOP);
static const struct bt_uuid_128 sweep_points_uuid = BT_UUID_INIT_128(UUID_SWEEP_POINTS);
static const struct bt_uuid_128 num_reps_uuid = BT_UUID_INIT_128(UUID_NUM_REPS);
static const struct bt_uuid_128 excitation_uuid = BT_UUID_INIT_128(UUID_EXCITATION);
static const struct bt_uuid_128 imu_quat_uuid = BT_UUID_INIT_128(UUID_IMU_QUAT);
static const struct bt_uuid_128 battery_level_uuid = BT_UUID_INIT_128(UUID_BATTERY_LEVEL);
static const struct bt_uuid_128 imu_q_variance_uuid = BT_UUID_INIT_128(UUID_IMU_Q_VARIANCE);

static AD5940SweepConfig sweep_config;
static struct bt_conn *current_conn;
static struct k_mutex conn_lock;
static struct k_mutex adv_lock;
static struct k_mutex config_lock;
static struct k_mutex notify_lock;
static struct k_mutex stored_lock;
static struct k_work_delayable advertising_restart_work;
static struct k_work_delayable advertising_slow_work;
static uint8_t battery_payload[4];
static uint8_t quaternion_payload[16];
static bool measurement_running;
static bool auto_mode_enabled;
static uint16_t auto_mode_interval_s;
static struct stored_record stored_records[STORED_RECORD_CAPACITY];
static uint32_t stored_write_total;
static uint16_t stored_count;
static uint16_t stored_session_id = 1;
static uint16_t stored_sequence_number;
static MeasurementPoint stored_builder_points[STORED_REPETITIONS][STORED_POINTS_PER_REP];
static uint32_t stored_builder_seen_points;
static uint8_t stored_send_buffer[STORED_RECORD_SIZE];
static bool advertising_active;
static enum advertising_mode advertising_current_mode;

K_MSGQ_DEFINE(command_msgq, sizeof(struct ble_command), COMMAND_QUEUE_LEN, 4);

static const struct gpio_dt_spec status_led = GPIO_DT_SPEC_GET_OR(DT_ALIAS(led0), gpios, {0});

static ssize_t read_serial(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			   void *buf, uint16_t len, uint16_t offset)
{
	ARG_UNUSED(conn);
	ARG_UNUSED(attr);
	return bt_gatt_attr_read(conn, attr, buf, len, offset,
				 CONFIG_BIOMESS_SERIAL_NUMBER,
				 strlen(CONFIG_BIOMESS_SERIAL_NUMBER));
}

static void put_le_float(float value, uint8_t *dst)
{
	uint32_t raw;

	memcpy(&raw, &value, sizeof(raw));
	sys_put_le32(raw, dst);
}

static float get_le_float(const void *src)
{
	uint32_t raw = sys_get_le32(src);
	float value;

	memcpy(&value, &raw, sizeof(value));
	return value;
}

static ssize_t read_config(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			   void *buf, uint16_t len, uint16_t offset)
{
	uint8_t out[4];
	uint8_t field = POINTER_TO_UINT(attr->user_data);
	size_t size = sizeof(out);

	k_mutex_lock(&config_lock, K_FOREVER);
	switch (field) {
	case 0:
		put_le_float(sweep_config.rcal_ohms, out);
		break;
	case 1:
		out[0] = sweep_config.sweep_enabled ? 1 : 0;
		size = 1;
		break;
	case 2:
		put_le_float(sweep_config.start_hz, out);
		break;
	case 3:
		put_le_float(sweep_config.stop_hz, out);
		break;
	case 4:
		sys_put_le32(sweep_config.points, out);
		break;
	case 5:
		out[0] = sweep_config.repetitions;
		size = 1;
		break;
	case 6:
		sys_put_le16(sweep_config.excitation_mvpp, out);
		size = 2;
		break;
	default:
		k_mutex_unlock(&config_lock);
		return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
	}
	k_mutex_unlock(&config_lock);

	return bt_gatt_attr_read(conn, attr, buf, len, offset, out, size);
}

static ssize_t write_config(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			    const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	uint8_t field = POINTER_TO_UINT(attr->user_data);

	ARG_UNUSED(conn);
	ARG_UNUSED(flags);

	if (offset != 0) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
	}

	k_mutex_lock(&config_lock, K_FOREVER);
	switch (field) {
	case 0:
		if (len != sizeof(float)) {
			goto invalid_len;
		}
		sweep_config.rcal_ohms = get_le_float(buf);
		break;
	case 1:
		if (len != 1) {
			goto invalid_len;
		}
		sweep_config.sweep_enabled = (*(const uint8_t *)buf) != 0;
		break;
	case 2:
		if (len != sizeof(float)) {
			goto invalid_len;
		}
		sweep_config.start_hz = get_le_float(buf);
		break;
	case 3:
		if (len != sizeof(float)) {
			goto invalid_len;
		}
		sweep_config.stop_hz = get_le_float(buf);
		break;
	case 4:
		if (len != sizeof(uint32_t)) {
			goto invalid_len;
		}
		sweep_config.points = CLAMP(sys_get_le32(buf), 2, AD5940_MAX_SWEEP_POINTS);
		break;
	case 5:
		if (len != 1) {
			goto invalid_len;
		}
		sweep_config.repetitions = CLAMP(*(const uint8_t *)buf, 1, 10);
		break;
	case 6:
		if (len != sizeof(uint16_t)) {
			goto invalid_len;
		}
		sweep_config.excitation_mvpp = CLAMP(sys_get_le16(buf), AD5940_EXCITATION_MVPP_MIN,
						     AD5940_EXCITATION_MVPP_MAX);
		break;
	default:
		k_mutex_unlock(&config_lock);
		return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
	}
	k_mutex_unlock(&config_lock);

	return len;

invalid_len:
	k_mutex_unlock(&config_lock);
	return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
}

static ssize_t read_battery(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			    void *buf, uint16_t len, uint16_t offset)
{
	ARG_UNUSED(attr);
	return bt_gatt_attr_read(conn, attr, buf, len, offset,
				 battery_payload, sizeof(battery_payload));
}

static ssize_t read_quaternion(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			       void *buf, uint16_t len, uint16_t offset)
{
	ARG_UNUSED(attr);
	return bt_gatt_attr_read(conn, attr, buf, len, offset,
				 quaternion_payload, sizeof(quaternion_payload));
}

static ssize_t write_command(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			     const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	const uint8_t *bytes = buf;
	struct ble_command command = {0};

	ARG_UNUSED(conn);
	ARG_UNUSED(attr);
	ARG_UNUSED(flags);

	if (offset != 0) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
	}
	if (len < 1) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	command.opcode = bytes[0];
	command.payload_len = MIN(len - 1, COMMAND_PAYLOAD_MAX);
	memcpy(command.payload, &bytes[1], command.payload_len);

	if (k_msgq_put(&command_msgq, &command, K_NO_WAIT) != 0) {
		return BT_GATT_ERR(BT_ATT_ERR_INSUFFICIENT_RESOURCES);
	}

	return len;
}

static void ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	LOG_INF("Notifications %s for attr %p", value == BT_GATT_CCC_NOTIFY ? "enabled" : "disabled", attr);
}

BT_GATT_SERVICE_DEFINE(control_svc,
	BT_GATT_PRIMARY_SERVICE(&control_service_uuid.uuid),
	BT_GATT_CHARACTERISTIC(&control_command_uuid.uuid,
			       BT_GATT_CHRC_WRITE | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_WRITE, NULL, write_command, NULL),
	BT_GATT_CCC(ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&serial_number_uuid.uuid, BT_GATT_CHRC_READ,
			       BT_GATT_PERM_READ, read_serial, NULL, NULL),
	BT_GATT_CHARACTERISTIC(&rcal_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(0)),
	BT_GATT_CHARACTERISTIC(&sweep_enable_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(1)),
	BT_GATT_CHARACTERISTIC(&sweep_start_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(2)),
	BT_GATT_CHARACTERISTIC(&sweep_stop_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(3)),
	BT_GATT_CHARACTERISTIC(&sweep_points_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(4)),
	BT_GATT_CHARACTERISTIC(&num_reps_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(5)),
	/* Optional, appended last so earlier attributes keep their order. */
	BT_GATT_CHARACTERISTIC(&excitation_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(6))
);

BT_GATT_SERVICE_DEFINE(config_svc,
	BT_GATT_PRIMARY_SERVICE(&config_service_uuid.uuid),
	BT_GATT_CHARACTERISTIC(&rcal_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(0)),
	BT_GATT_CHARACTERISTIC(&sweep_enable_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(1)),
	BT_GATT_CHARACTERISTIC(&sweep_start_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(2)),
	BT_GATT_CHARACTERISTIC(&sweep_stop_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(3)),
	BT_GATT_CHARACTERISTIC(&sweep_points_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(4)),
	BT_GATT_CHARACTERISTIC(&num_reps_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(5)),
	/* Optional, appended last so earlier attributes keep their order. */
	BT_GATT_CHARACTERISTIC(&excitation_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, read_config, write_config, UINT_TO_POINTER(6))
);

BT_GATT_SERVICE_DEFINE(data_svc,
	BT_GATT_PRIMARY_SERVICE(&data_service_uuid.uuid)
);

BT_GATT_SERVICE_DEFINE(env_svc,
	BT_GATT_PRIMARY_SERVICE(&env_service_uuid.uuid),
	BT_GATT_CHARACTERISTIC(&imu_quat_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_quaternion, NULL, NULL),
	BT_GATT_CCC(ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&battery_level_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_battery, NULL, NULL),
	BT_GATT_CCC(ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&imu_q_variance_uuid.uuid, BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_READ, read_quaternion, NULL, NULL),
	BT_GATT_CCC(ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE)
);

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

static const struct bt_le_conn_param conn_param_measurement =
	BT_LE_CONN_PARAM_INIT(BT_GAP_MS_TO_CONN_INTERVAL(30),
			      BT_GAP_MS_TO_CONN_INTERVAL(50),
			      0,
			      BT_GAP_MS_TO_CONN_TIMEOUT(4000));

static const struct bt_le_conn_param conn_param_idle =
	BT_LE_CONN_PARAM_INIT(BT_GAP_MS_TO_CONN_INTERVAL(250),
			      BT_GAP_MS_TO_CONN_INTERVAL(500),
			      4,
			      BT_GAP_MS_TO_CONN_TIMEOUT(6000));

static const struct bt_le_adv_param adv_conn_fast_identity =
	BT_LE_ADV_PARAM_INIT(BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_IDENTITY,
			     BT_GAP_ADV_FAST_INT_MIN_1,
			     BT_GAP_ADV_FAST_INT_MAX_1,
			     NULL);

static const struct bt_le_adv_param adv_conn_slow_identity =
	BT_LE_ADV_PARAM_INIT(BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_IDENTITY,
			     BT_GAP_ADV_FAST_INT_MIN_2,
			     BT_GAP_ADV_FAST_INT_MAX_2,
			     NULL);

static void pulse_status_led(uint16_t on_ms)
{
	if (!gpio_is_ready_dt(&status_led)) {
		return;
	}

	(void)gpio_pin_configure_dt(&status_led, GPIO_OUTPUT_INACTIVE);
	gpio_pin_set_dt(&status_led, 1);
	k_msleep(on_ms);
	gpio_pin_set_dt(&status_led, 0);
}

static int start_advertising_locked(enum advertising_mode mode)
{
	const struct bt_le_adv_param *param;
	int ret;

	if (advertising_active && advertising_current_mode == mode) {
		LOG_INF("BLE %s advertising already active as %s",
			mode == ADVERTISING_FAST ? "fast" : "slow", CONFIG_BT_DEVICE_NAME);
		return 0;
	}

	if (advertising_active) {
		ret = bt_le_adv_stop();
		if (ret < 0 && ret != -EALREADY) {
			LOG_WRN("BLE advertising stop failed before mode switch: %d", ret);
		}
		advertising_active = false;
	}

	if (mode == ADVERTISING_FAST) {
		param = &adv_conn_fast_identity;
	} else {
		param = &adv_conn_slow_identity;
	}

	ret = bt_le_adv_start(param, ad, ARRAY_SIZE(ad), NULL, 0);

	if (ret == -EALREADY) {
		advertising_active = true;
		advertising_current_mode = mode;
		LOG_INF("BLE advertising already active as %s", CONFIG_BT_DEVICE_NAME);
		pulse_status_led(50);
		return 0;
	}
	if (ret < 0) {
		LOG_ERR("BLE advertising start failed: %d", ret);
		return ret;
	}

	advertising_active = true;
	advertising_current_mode = mode;

	if (mode == ADVERTISING_FAST) {
		(void)k_work_reschedule(&advertising_slow_work, K_SECONDS(ADV_FAST_WINDOW_S));
	} else {
		(void)k_work_cancel_delayable(&advertising_slow_work);
	}

	LOG_INF("BLE %s advertising as %s", mode == ADVERTISING_FAST ? "fast" : "slow",
		CONFIG_BT_DEVICE_NAME);
	pulse_status_led(mode == ADVERTISING_FAST ? 90 : 35);
	return 0;
}

static int start_advertising_mode(enum advertising_mode mode)
{
	bool connected;
	int ret;

	k_mutex_lock(&conn_lock, K_FOREVER);
	connected = current_conn != NULL;
	k_mutex_unlock(&conn_lock);

	if (connected) {
		LOG_INF("BLE advertising skipped while connected");
		return 0;
	}

	k_mutex_lock(&adv_lock, K_FOREVER);
	ret = start_advertising_locked(mode);
	k_mutex_unlock(&adv_lock);

	return ret;
}

static void advertising_restart_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	(void)start_advertising_mode(ADVERTISING_FAST);
}

static void advertising_slow_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);
	(void)start_advertising_mode(ADVERTISING_SLOW);
}

static int start_advertising(void)
{
	return start_advertising_mode(ADVERTISING_FAST);
}

void ble_service_request_fast_advertising(void)
{
	(void)k_work_reschedule(&advertising_restart_work, K_NO_WAIT);
}

static int request_connection_params(const struct bt_le_conn_param *param, const char *name)
{
	struct bt_conn *conn;
	int ret;

	k_mutex_lock(&conn_lock, K_FOREVER);
	conn = current_conn != NULL ? bt_conn_ref(current_conn) : NULL;
	k_mutex_unlock(&conn_lock);

	if (conn == NULL) {
		return -ENOTCONN;
	}

	ret = bt_conn_le_param_update(conn, param);
	bt_conn_unref(conn);

	if (ret < 0 && ret != -EALREADY && ret != -EBUSY) {
		LOG_WRN("BLE %s connection parameter request failed: %d", name, ret);
	} else if (ret == 0) {
		LOG_INF("BLE %s connection parameters requested", name);
	}

	return ret;
}

static void connected(struct bt_conn *conn, uint8_t err)
{
	if (err != 0) {
		LOG_ERR("BLE connection failed: %u", err);
		return;
	}

	k_mutex_lock(&conn_lock, K_FOREVER);
	if (current_conn != NULL) {
		bt_conn_unref(current_conn);
	}
	current_conn = bt_conn_ref(conn);
	k_mutex_unlock(&conn_lock);

	k_mutex_lock(&adv_lock, K_FOREVER);
	advertising_active = false;
	k_mutex_unlock(&adv_lock);
	(void)k_work_cancel_delayable(&advertising_slow_work);

	LOG_INF("BLE connected");
	(void)request_connection_params(&conn_param_idle, "idle");
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	ARG_UNUSED(conn);

	k_mutex_lock(&conn_lock, K_FOREVER);
	if (current_conn != NULL) {
		bt_conn_unref(current_conn);
		current_conn = NULL;
	}
	k_mutex_unlock(&conn_lock);

	auto_mode_enabled = false;
	k_mutex_lock(&adv_lock, K_FOREVER);
	advertising_active = false;
	k_mutex_unlock(&adv_lock);
	(void)k_work_cancel_delayable(&advertising_slow_work);
	LOG_INF("BLE disconnected: 0x%02x", reason);
	(void)k_work_reschedule(&advertising_restart_work, K_MSEC(250));
}

static void le_param_updated(struct bt_conn *conn, uint16_t interval, uint16_t latency,
			     uint16_t timeout)
{
	ARG_UNUSED(conn);

	LOG_INF("BLE connection params: interval %u ms, latency %u, timeout %u ms",
		BT_CONN_INTERVAL_TO_MS(interval), latency, timeout * 10U);
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = connected,
	.disconnected = disconnected,
	.le_param_updated = le_param_updated,
};

static const struct bt_gatt_attr *control_notify_attr(void)
{
	return &control_svc.attrs[2];
}

static const struct bt_gatt_attr *battery_notify_attr(void)
{
	return &env_svc.attrs[5];
}

static const struct bt_gatt_attr *imu_notify_attr(void)
{
	return &env_svc.attrs[2];
}

static void put_battery_payload(uint16_t voltage_mv, uint16_t percentage)
{
	sys_put_le16(voltage_mv, &battery_payload[0]);
	sys_put_le16(percentage, &battery_payload[2]);
}

static uint16_t crc16_ccitt(const uint8_t *data, size_t len)
{
	uint16_t crc = 0xffff;

	for (size_t i = 0; i < len; i++) {
		crc ^= (uint16_t)data[i] << 8;
		for (int bit = 0; bit < 8; bit++) {
			crc = (crc & 0x8000) != 0 ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
		}
	}

	return crc;
}

int ble_service_notify_measurement_chunk(const void *data, size_t len)
{
	struct bt_conn *conn;
	int ret;

	k_mutex_lock(&conn_lock, K_FOREVER);
	conn = current_conn != NULL ? bt_conn_ref(current_conn) : NULL;
	k_mutex_unlock(&conn_lock);

	if (conn == NULL) {
		return -ENOTCONN;
	}

	k_mutex_lock(&notify_lock, K_FOREVER);
	ret = bt_gatt_notify(conn, control_notify_attr(), data, len);
	k_mutex_unlock(&notify_lock);

	bt_conn_unref(conn);
	return ret;
}

int ble_service_notify_battery(uint16_t voltage_mv, uint16_t percentage)
{
	struct bt_conn *conn;
	int ret;

	put_battery_payload(voltage_mv, percentage);

	k_mutex_lock(&conn_lock, K_FOREVER);
	conn = current_conn != NULL ? bt_conn_ref(current_conn) : NULL;
	k_mutex_unlock(&conn_lock);

	if (conn == NULL) {
		return -ENOTCONN;
	}

	ret = bt_gatt_notify(conn, battery_notify_attr(), battery_payload, sizeof(battery_payload));
	bt_conn_unref(conn);
	return ret;
}

static size_t notification_payload_limit(void)
{
	struct bt_conn *conn;
	uint16_t mtu = 23;

	k_mutex_lock(&conn_lock, K_FOREVER);
	conn = current_conn != NULL ? bt_conn_ref(current_conn) : NULL;
	k_mutex_unlock(&conn_lock);

	if (conn != NULL) {
		mtu = bt_gatt_get_mtu(conn);
		bt_conn_unref(conn);
	}

	return MAX((size_t)20, (size_t)mtu - 3);
}

static void measurement_point_callback(const MeasurementPoint *point, void *user_data)
{
	struct measurement_stream *stream = user_data;
	size_t limit = MIN(sizeof(stream->data), notification_payload_limit());
	uint32_t linear_index;
	uint32_t repetition;
	uint32_t point_index;

	if (point == NULL || stream == NULL) {
		return;
	}

	if (stream->offset > 0 && stream->offset + 12 > limit) {
		(void)ble_service_notify_measurement_chunk(stream->data, stream->offset);
		stream->offset = 0;
		k_msleep(8);
	}

	put_le_float(point->frequency, &stream->data[stream->offset]);
	put_le_float(point->magnitude, &stream->data[stream->offset + 4]);
	put_le_float(point->phase, &stream->data[stream->offset + 8]);
	stream->offset += 12;

	if (stream->config.points > 0) {
		linear_index = stored_builder_seen_points++;
		repetition = linear_index / stream->config.points;
		point_index = linear_index % stream->config.points;

		if (repetition < STORED_REPETITIONS && point_index < STORED_POINTS_PER_REP) {
			stored_builder_points[repetition][point_index] = *point;
		}
	}

	if (stream->offset >= limit) {
		(void)ble_service_notify_measurement_chunk(stream->data, stream->offset);
		stream->offset = 0;
		k_msleep(8);
	}
}

static void flush_measurement_stream(struct measurement_stream *stream)
{
	if (stream != NULL && stream->offset > 0) {
		(void)ble_service_notify_measurement_chunk(stream->data, stream->offset);
		stream->offset = 0;
	}
}

static uint8_t current_battery_percentage(void)
{
	return (uint8_t)MIN(sys_get_le16(&battery_payload[2]), 100);
}

static void reset_stored_builder(void)
{
	memset(stored_builder_points, 0, sizeof(stored_builder_points));
	stored_builder_seen_points = 0;
}

static void save_stored_record(const AD5940SweepConfig *config)
{
	struct stored_record record = {0};
	size_t offset = 0;
	uint16_t crc;
	uint16_t write_index;
	uint16_t voltage_mv;
	uint16_t percentage;

	if (config == NULL) {
		return;
	}

	if (board_power_read_battery(&voltage_mv, &percentage) == 0) {
		put_battery_payload(voltage_mv, percentage);
	}

	sys_put_le32((uint32_t)(k_uptime_get() / 1000), &record.bytes[offset]);
	offset += 4;
	sys_put_le16(stored_session_id, &record.bytes[offset]);
	offset += 2;
	sys_put_le16(stored_sequence_number++, &record.bytes[offset]);
	offset += 2;
	sys_put_le16(auto_mode_enabled ? auto_mode_interval_s : 0, &record.bytes[offset]);
	offset += 2;
	record.bytes[offset++] = current_battery_percentage();
	record.bytes[offset++] = MIN(config->repetitions, STORED_REPETITIONS);

	for (uint8_t rep = 0; rep < STORED_REPETITIONS; rep++) {
		for (uint8_t point = 0; point < STORED_POINTS_PER_REP; point++) {
			put_le_float(stored_builder_points[rep][point].frequency, &record.bytes[offset]);
			offset += 4;
			put_le_float(stored_builder_points[rep][point].magnitude, &record.bytes[offset]);
			offset += 4;
			put_le_float(stored_builder_points[rep][point].phase, &record.bytes[offset]);
			offset += 4;
		}
	}

	for (uint8_t rep = 0; rep < STORED_REPETITIONS; rep++) {
		memcpy(&record.bytes[offset], quaternion_payload, sizeof(quaternion_payload));
		offset += sizeof(quaternion_payload);
	}

	crc = crc16_ccitt(record.bytes, offset);
	sys_put_le16(crc, &record.bytes[offset]);
	offset += 2;

	__ASSERT_NO_MSG(offset == STORED_RECORD_SIZE);

	k_mutex_lock(&stored_lock, K_FOREVER);
	write_index = stored_write_total % STORED_RECORD_CAPACITY;
	stored_records[write_index] = record;
	stored_write_total++;
	if (stored_count < STORED_RECORD_CAPACITY) {
		stored_count++;
	}
	k_mutex_unlock(&stored_lock);
}

static int run_measurement_command(void)
{
	AD5940SweepConfig active;
	struct measurement_stream stream = {0};
	int ret;

	if (measurement_running) {
		return -EBUSY;
	}

	k_mutex_lock(&config_lock, K_FOREVER);
	active = sweep_config;
	k_mutex_unlock(&config_lock);

	reset_stored_builder();
	stream.config = active;
	measurement_running = true;
	if (request_connection_params(&conn_param_measurement, "measurement") == 0) {
		k_msleep(CONN_MEASUREMENT_SETTLE_MS);
	}
	ret = AD5940_RunSweep(&active, measurement_point_callback, &stream);
	flush_measurement_stream(&stream);
	measurement_running = false;
	(void)request_connection_params(&conn_param_idle, "idle");
	if (ret == 0) {
		save_stored_record(&active);
	}
	return ret;
}

static void notify_stored_count(void)
{
	uint8_t count[2];
	uint16_t value;

	k_mutex_lock(&stored_lock, K_FOREVER);
	value = stored_count;
	k_mutex_unlock(&stored_lock);

	sys_put_le16(value, count);
	(void)ble_service_notify_measurement_chunk(count, sizeof(count));
}

static void notify_stored_batch(const struct ble_command *command)
{
	uint16_t offset = 0;
	uint8_t requested = 1;
	uint16_t available;
	size_t chunk_len;
	size_t notify_limit = notification_payload_limit();

	if (command != NULL && command->payload_len >= 3) {
		offset = sys_get_le16(command->payload);
		requested = command->payload[2];
	}

	k_mutex_lock(&stored_lock, K_FOREVER);
	available = stored_count;
	k_mutex_unlock(&stored_lock);

	for (uint16_t i = 0; i < requested && offset + i < available; i++) {
		uint16_t logical_index = offset + i;
		uint16_t physical_index;
		size_t sent = 0;

		k_mutex_lock(&stored_lock, K_FOREVER);
		if (stored_write_total <= STORED_RECORD_CAPACITY) {
			physical_index = logical_index;
		} else {
			uint32_t oldest = stored_write_total - stored_count;
			physical_index = (oldest + logical_index) % STORED_RECORD_CAPACITY;
		}
		memcpy(stored_send_buffer, stored_records[physical_index].bytes, sizeof(stored_send_buffer));
		k_mutex_unlock(&stored_lock);

		while (sent < sizeof(stored_send_buffer)) {
			chunk_len = MIN(notify_limit, sizeof(stored_send_buffer) - sent);
			(void)ble_service_notify_measurement_chunk(&stored_send_buffer[sent], chunk_len);
			sent += chunk_len;
			k_msleep(8);
		}
	}
}

static void notify_quaternion_zero(void)
{
	struct bt_conn *conn;

	k_mutex_lock(&conn_lock, K_FOREVER);
	conn = current_conn != NULL ? bt_conn_ref(current_conn) : NULL;
	k_mutex_unlock(&conn_lock);

	if (conn != NULL) {
		(void)bt_gatt_notify(conn, imu_notify_attr(), quaternion_payload, sizeof(quaternion_payload));
		bt_conn_unref(conn);
	}
}

static void handle_battery_command(void)
{
	uint16_t voltage_mv = 0;
	uint16_t percentage = 0;
	int ret = board_power_read_battery(&voltage_mv, &percentage);

	if (ret < 0) {
		LOG_WRN("Battery read failed: %d", ret);
		voltage_mv = 0;
		percentage = 0;
	}

	(void)ble_service_notify_battery(voltage_mv, percentage);
}

static void handle_health_command(void)
{
	AD5940Identity identity = {0};
	uint16_t voltage_mv = 0;
	uint16_t percentage = 0;
	uint16_t flags = 0;
	uint8_t payload[12] = {0};
	int identity_ret;

	if (board_power_read_battery(&voltage_mv, &percentage) == 0) {
		put_battery_payload(voltage_mv, percentage);
		flags |= HEALTH_FLAG_PMIC_OK;
	} else {
		LOG_WRN("Health PMIC read failed");
	}

	identity_ret = AD5940_ReadIdentity(&identity);
	if (identity_ret < 0) {
		LOG_WRN("Health AD5940 identity read failed: ADIID=0x%04x CHIPID=0x%04x",
			identity.adi_id, identity.chip_id);
	}
	if (identity.adi_id == HEALTH_AD5940_ADIID_EXPECTED) {
		flags |= HEALTH_FLAG_AD5940_ADIID_OK;
	} else if (identity_ret == 0) {
		LOG_WRN("Health AD5940 unexpected ADIID: 0x%04x", identity.adi_id);
	}
	if ((identity.chip_id & HEALTH_AD5940_CHIPID_PART_MASK) == HEALTH_AD5940_CHIPID_PART_EXPECTED) {
		flags |= HEALTH_FLAG_AD5940_CHIPID_KNOWN;
	} else if (identity_ret == 0) {
		LOG_WRN("Health AD5940 unexpected CHIPID: 0x%04x", identity.chip_id);
	}

	sys_put_le16(flags, &payload[0]);
	sys_put_le16(voltage_mv, &payload[2]);
	sys_put_le16(percentage, &payload[4]);
	sys_put_le16(identity.adi_id, &payload[6]);
	sys_put_le16(identity.chip_id, &payload[8]);

	(void)ble_service_notify_measurement_chunk(payload, sizeof(payload));
}

static void handle_contact_check_command(void)
{
	struct contact_check_result result;
	static uint8_t payload[CONTACT_CHECK_PAYLOAD_SIZE];
	size_t notify_limit;
	size_t len;
	size_t sent = 0;
	float rcal_ohms;
	int ret;

	k_mutex_lock(&config_lock, K_FOREVER);
	rcal_ohms = sweep_config.rcal_ohms;
	k_mutex_unlock(&config_lock);

	measurement_running = true;
	ret = contact_check_run(rcal_ohms, &result);
	measurement_running = false;
	if (ret < 0) {
		LOG_WRN("Contact check incomplete: %d (flags 0x%04x)", ret, result.flags);
	}

	len = contact_check_encode(&result, payload, sizeof(payload));
	notify_limit = notification_payload_limit();
	while (sent < len) {
		size_t chunk_len = MIN(notify_limit, len - sent);

		(void)ble_service_notify_measurement_chunk(&payload[sent], chunk_len);
		sent += chunk_len;
		k_msleep(8);
	}
}

static void blink_led(void)
{
	for (int i = 0; i < 3; i++) {
		pulse_status_led(120);
		k_msleep(120);
	}
}

static void command_thread(void)
{
	struct ble_command command;

	for (;;) {
		k_timeout_t wait = auto_mode_enabled ? K_SECONDS(auto_mode_interval_s) : K_FOREVER;
		int queue_ret = k_msgq_get(&command_msgq, &command, wait);

		if (queue_ret == -EAGAIN && auto_mode_enabled) {
			(void)run_measurement_command();
			continue;
		}
		if (queue_ret != 0) {
			continue;
		}

		LOG_INF("BLE command 0x%02x (%u payload bytes)", command.opcode, command.payload_len);

		switch (command.opcode) {
		case COMMAND_MEASUREMENT:
			(void)run_measurement_command();
			break;
		case COMMAND_BATTERY_MANUAL:
			handle_battery_command();
			break;
		case COMMAND_IMU_SINGLE:
		case COMMAND_IMU_STATS:
			notify_quaternion_zero();
			break;
		case COMMAND_START_AUTO_MODE:
			auto_mode_enabled = true;
			auto_mode_interval_s = command.payload_len >= 2 ?
				CLAMP(sys_get_le16(command.payload), AUTO_MODE_MIN_INTERVAL_S, AUTO_MODE_MAX_INTERVAL_S) :
				AUTO_MODE_DEFAULT_INTERVAL_S;
			stored_session_id++;
			stored_sequence_number = 0;
			LOG_INF("Auto mode started (%u s)", auto_mode_interval_s);
			break;
		case COMMAND_STOP_AUTO_MODE:
			auto_mode_enabled = false;
			break;
		case COMMAND_GET_STORED_COUNT:
			notify_stored_count();
			break;
		case COMMAND_GET_STORED_BATCH:
			notify_stored_batch(&command);
			break;
		case COMMAND_CLEAR_STORED:
			k_mutex_lock(&stored_lock, K_FOREVER);
			stored_count = 0;
			stored_write_total = 0;
			memset(stored_records, 0, sizeof(stored_records));
			k_mutex_unlock(&stored_lock);
			notify_stored_count();
			break;
		case COMMAND_HEALTH_CHECK:
			handle_health_command();
			break;
		case COMMAND_CONTACT_CHECK:
			handle_contact_check_command();
			break;
		case COMMAND_LED_BLINK:
			blink_led();
			break;
		default:
			LOG_WRN("Unknown command 0x%02x", command.opcode);
			break;
		}
	}
}

K_THREAD_DEFINE(command_thread_id, MEASUREMENT_THREAD_STACK, command_thread,
		NULL, NULL, NULL, MEASUREMENT_THREAD_PRIORITY, 0, 0);

int ble_service_init(void)
{
	int ret;

	k_mutex_init(&conn_lock);
	k_mutex_init(&adv_lock);
	k_mutex_init(&config_lock);
	k_mutex_init(&notify_lock);
	k_mutex_init(&stored_lock);
	k_work_init_delayable(&advertising_restart_work, advertising_restart_work_handler);
	k_work_init_delayable(&advertising_slow_work, advertising_slow_work_handler);
	AD5940_GetDefaultSweepConfig(&sweep_config);
	put_battery_payload(0, 0);
	memset(quaternion_payload, 0, sizeof(quaternion_payload));

	ret = bt_enable(NULL);
	if (ret < 0) {
		LOG_ERR("Bluetooth init failed: %d", ret);
		return ret;
	}

	ret = start_advertising();
	if (ret < 0) {
		return ret;
	}

	return 0;
}
