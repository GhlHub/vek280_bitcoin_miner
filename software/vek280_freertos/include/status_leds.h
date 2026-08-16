#ifndef STATUS_LEDS_H
#define STATUS_LEDS_H

#include <stdbool.h>

/*
 * VEK280 status LED meanings:
 *   DS6: Stratum TCP connection established by the R5.
 *   DS5: toggles for each received mining.notify message.
 *   DS4: toggles for each miner IRQ handled by the result worker.
 *   DS3: subscribed and authorized Stratum session is usable for mining.
 */
void status_leds_init(void);
void status_leds_set_pool_r5_connected(bool connected);
void status_leds_set_pool_attached(bool attached);
void status_leds_toggle_job_received(void);
void status_leds_toggle_irq_processed(void);

#endif
