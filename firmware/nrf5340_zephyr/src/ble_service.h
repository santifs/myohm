#ifndef BLE_SERVICE_H
#define BLE_SERVICE_H

#include <stddef.h>
#include <stdint.h>

int ble_service_init(void);
void ble_service_request_fast_advertising(void);
int ble_service_notify_measurement_chunk(const void *data, size_t len);
int ble_service_notify_battery(uint16_t voltage_mv, uint16_t percentage);

#endif
