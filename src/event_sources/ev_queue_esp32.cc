// Copyright (C) 2018 Toitware ApS.
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version
// 2.1 only.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// The license can be found in the file `LICENSE` in the top level
// directory of this repository.

#include "../top.h"

#ifdef TOIT_FREERTOS

#include <driver/gpio.h>

#include "../objects_inline.h"
#include "../process.h"

#include "system_esp32.h"
#include "ev_queue_esp32.h"

namespace toit {

EventQueueEventSource* EventQueueEventSource::_instance = null;

EventQueueEventSource::EventQueueEventSource()
    : EventSource("EVQ")
    , Thread("EVQ")
    , _stop(xSemaphoreCreateBinary())
    , _gpio_queue(xQueueCreate(32, sizeof(word)))
    , _queue_set(xQueueCreateSet(3000)) {
  xQueueAddToSet(_stop, _queue_set);
  xQueueAddToSet(_gpio_queue, _queue_set);

  SystemEventSource::instance()->run([&]() -> void {
    FATAL_IF_NOT_ESP_OK(gpio_install_isr_service(ESP_INTR_FLAG_IRAM));
  });

  // Create OS thread to handle events.
  spawn();

  ASSERT(_instance == null);
  _instance = this;
}

EventQueueEventSource::~EventQueueEventSource() {
  xSemaphoreGive(_stop);

  join();

  SystemEventSource::instance()->run([&]() -> void {
    gpio_uninstall_isr_service();
  });

  vQueueDelete(_queue_set);
  vQueueDelete(_gpio_queue);
  vSemaphoreDelete(_stop);
  _instance = null;
}

void EventQueueEventSource::entry() {
  Locker locker(mutex());
  HeapTagScope scope(ITERATE_CUSTOM_TAGS + EVENT_SOURCE_MALLOC_TAG);

  while (true) {
    QueueSetMemberHandle_t handle;
    { Unlocker unlock(locker);
      // Wait for any queue/semaphore to wake up.
      handle = xQueueSelectFromSet(_queue_set, portMAX_DELAY);
    }
    // First test if we should shut down.
    if (handle == _stop && xSemaphoreTake(_stop, 0)) {
      return;
    }

    // See if there's a GPIO event.
    word pin;
    while (xQueueReceive(_gpio_queue, &pin, 0)) {
      bool data = gpio_get_level(gpio_num_t(pin)) != 0;
      for (auto r : resources()) {
        auto resource = static_cast<EventQueueResource*>(r);
        if (resource->check_gpio(pin)) {
          dispatch(locker, r, data);
        }
      }
    }

    // Then loop through other queues.
    for (auto r : resources()) {
      auto resource = static_cast<EventQueueResource*>(r);
      word data;
      while (resource->receive_event(&data)) {
        dispatch(locker, r, data);
      }
    }


  }
}

void EventQueueEventSource::on_register_resource(Locker& locker, Resource* r) {
  auto resource = static_cast<EventQueueResource*>(r);
  QueueHandle_t queue = resource->queue();
  if (queue == null) return;
  // We can only add to the queue set when the queue is empty, so we
  // repeatedly try to drain the queue before adding it to the set.
  int attempts = 0;
  do {
    if (attempts++ > 16) FATAL("couldn't register event resource");
    word data;
    while (resource->receive_event(&data)) {
      dispatch(locker, r, data);
    }
  } while (xQueueAddToSet(queue, _queue_set) != pdPASS);
}

void EventQueueEventSource::on_unregister_resource(Locker& locker, Resource* r) {
  auto resource = static_cast<EventQueueResource*>(r);
  QueueHandle_t queue = resource->queue();
  if (queue == null) return;
  // We can only remove from the queue set when the queue is empty, so we
  // repeatedly try to drain the queue before removing it from the set.
  int attempts = 0;
  do {
    if (attempts++ > 16) FATAL("couldn't unregister event resource");
    word data;
    while (resource->receive_event(&data)) {
      // Don't dispatch while unregistering.
    }
  } while (xQueueRemoveFromSet(queue, _queue_set) != pdPASS);
}

} // namespace toit

#endif // TOIT_FREERTOS
