// Copyright (C) 2021 Toitware ApS.
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

#include <driver/i2s.h>

#include "../objects_inline.h"
#include "../process.h"
#include "../resource.h"
#include "../resource_pool.h"
#include "../vm.h"

#include "../event_sources/system_esp32.h"
#include "../event_sources/ev_queue_esp32.h"

namespace toit {

const i2s_port_t kInvalidPort = i2s_port_t(-1);

const int kReadState = 1 << 0;
const int kWriteState = 1 << 1;
const int kErrorState = 1 << 2;

ResourcePool<i2s_port_t, kInvalidPort> i2s_ports(
    I2S_NUM_0
#if SOC_I2S_NUM > 1
    , I2S_NUM_1
#endif
);

class I2sResourceGroup : public ResourceGroup {
 public:
  TAG(I2sResourceGroup);

  I2sResourceGroup(Process* process, EventSource* event_source)
      : ResourceGroup(process, event_source) {}

  uint32_t on_event(Resource* r, word data, uint32_t state) {
    switch (data) {
      case I2S_EVENT_RX_DONE:
        state |= kReadState;
        break;

      case I2S_EVENT_TX_DONE:
        state |= kWriteState;
        break;

      case I2S_EVENT_DMA_ERROR:
        state |= kErrorState;
        break;
    }

    return state;
  }
};

class I2sResource: public EventQueueResource {
 public:
  TAG(I2sResource);
  I2sResource(I2sResourceGroup* group, i2s_port_t port, int max_frames_per_read, int word_size, QueueHandle_t queue)
    : EventQueueResource(group, queue)
    , port_(port)
    , max_frames_per_read_(max_frames_per_read)
    , word_size_(word_size) {}

  ~I2sResource() override {
    SystemEventSource::instance()->run([&]() -> void {
      FATAL_IF_NOT_ESP_OK(i2s_driver_uninstall(port_));
    });
    free(write_buffer_);
    i2s_ports.put(port_);
  }

  i2s_port_t port() const { return port_; }
  int max_frames_per_read() const { return max_frames_per_read_; }
  int word_size() const { return word_size_; }
  int bytes_per_sample() const { return word_size_ <= 2 ? 2 : 4; }
  bool receive_event(word* data) override;

  void set_write_buffer(uint8* write_buffer) { write_buffer_ = write_buffer; }
  uint8* write_buffer() const { return write_buffer_; }

  void set_write_position(uword write_position) { write_position_ = write_position; }
  uword write_position() const { return write_position_; }

 private:
  i2s_port_t port_;
  int max_frames_per_read_;
  int word_size_;
  uint8* write_buffer_ = null;
  uword write_position_ = 0;
};

bool I2sResource::receive_event(word* data) {
  i2s_event_t event;
  bool more = xQueueReceive(queue(), &event, 0);
  if (more) *data = event.type;
  return more;
}

MODULE_IMPLEMENTATION(i2s, MODULE_I2S);

PRIMITIVE(init) {
  ByteArray* proxy = process->object_heap()->allocate_proxy();
  if (proxy == null) {
    ALLOCATION_FAILED;
  }

  I2sResourceGroup* i2s = _new I2sResourceGroup(process, EventQueueEventSource::instance());
  if (!i2s) {
    MALLOC_FAILED;
  }

  proxy->set_external_address(i2s);
  return proxy;
}


PRIMITIVE(create) {
  ARGS(I2sResourceGroup, group, int, sck_pin, int, ws_pin, int, tx_pin,
       int, rx_pin, int, mclk_pin,
       uint32, sample_rate, int, bits_per_sample, int, buffer_size,
       bool, is_master, int, mclk_multiplier, bool, use_apll);

  uint32 fixed_mclk = 0;
  if (mclk_pin != -1) {
    if (mclk_multiplier != 128 && mclk_multiplier != 256 && mclk_multiplier != 384) INVALID_ARGUMENT;
    fixed_mclk = mclk_multiplier * sample_rate;
  }

  if (bits_per_sample != 16 && bits_per_sample != 24 && bits_per_sample != 32) INVALID_ARGUMENT;

  i2s_port_t port = i2s_ports.any();
  if (port == kInvalidPort) OUT_OF_RANGE;

  ByteArray* proxy = process->object_heap()->allocate_proxy();
  if (proxy == null) {
    i2s_ports.put(port);
    ALLOCATION_FAILED;
  }

  int mode;
  if (is_master) {
    mode = I2S_MODE_MASTER;
  } else {
    mode = I2S_MODE_SLAVE;
  }

  if (tx_pin != -1) {
    mode |= I2S_MODE_TX;
  }

  if (rx_pin != -1) {
    mode |= I2S_MODE_RX;
  }

  int word_size = bits_per_sample / 8;
  int number_of_dma_buffers = 4;
  int frames_per_dma_buffer = (buffer_size + number_of_dma_buffers -1 ) / number_of_dma_buffers;

  i2s_config_t config = {
    .mode = static_cast<i2s_mode_t>(mode),
    .sample_rate = sample_rate,
    .bits_per_sample = static_cast<i2s_bits_per_sample_t>(bits_per_sample),
    .channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = 0, // default interrupt priority
    .dma_buf_count = number_of_dma_buffers,
    .dma_buf_len = frames_per_dma_buffer * word_size,
    .use_apll = use_apll,
    .tx_desc_auto_clear = false,
    .fixed_mclk = static_cast<int>(fixed_mclk),
    .mclk_multiple = I2S_MCLK_MULTIPLE_DEFAULT,
    .bits_per_chan = I2S_BITS_PER_CHAN_DEFAULT,
#if SOC_I2S_SUPPORTS_TDM
    .chan_mask = static_cast<i2s_channel_t>(0),
    .total_chan = 0,
    .left_align = false,
    .big_edin = false,
    .bit_order_msb = false,
    .skip_msk = false,
#endif // SOC_I2S_SUPPORTS_TDM
  };

  struct {
    i2s_port_t port;
    i2s_config_t config;
    QueueHandle_t queue;
    esp_err_t err;
  } args {
    .port = port,
    .config = config,
    .queue = QueueHandle_t{},
    .err = esp_err_t{},
  };
  SystemEventSource::instance()->run([&]() -> void {
    args.err = i2s_driver_install(args.port, &args.config, 32, &args.queue);
  });
  if (args.err != ESP_OK) {
    i2s_ports.put(port);
    return Primitive::os_error(args.err, process);
  }

  i2s_pin_config_t pin_config = {
    .mck_io_num = mclk_pin >=0 ? mclk_pin: I2S_PIN_NO_CHANGE,
    .bck_io_num = sck_pin >= 0 ? sck_pin : I2S_PIN_NO_CHANGE,
    .ws_io_num = ws_pin >= 0 ? ws_pin : I2S_PIN_NO_CHANGE,
    .data_out_num = tx_pin >= 0 ? tx_pin : I2S_PIN_NO_CHANGE,
    .data_in_num = rx_pin >= 0 ? rx_pin : I2S_PIN_NO_CHANGE
  };
  esp_err_t err = i2s_set_pin(port, &pin_config);
  if (err != ESP_OK) {
    SystemEventSource::instance()->run([&]() -> void {
      i2s_driver_uninstall(port);
    });
    i2s_ports.put(port);
    return Primitive::os_error(err, process);
  }

  I2sResource* i2s = _new I2sResource(group, port, frames_per_dma_buffer * number_of_dma_buffers,
                                      word_size,  args.queue);
  if (!i2s) {
    SystemEventSource::instance()->run([&]() -> void {
      i2s_driver_uninstall(port);
    });
    i2s_ports.put(port);
    MALLOC_FAILED;
  }

  group->register_resource(i2s);
  proxy->set_external_address(i2s);

  return proxy;
}

PRIMITIVE(close) {
  ARGS(I2sResourceGroup, group, I2sResource, i2s);
  group->unregister_resource(i2s);
  i2s_proxy->clear_external_address();
  return process->program()->null_object();
}

// This write is a bit unusual in the sense that it has a state between calls. This is to
// make sure that we do not do misaligned writes. The corresponding toit method should have a mutex
// to guard against concurrent invocations.
PRIMITIVE(write) {
  ARGS(I2sResource, i2s, Array, array);
  if (!i2s->write_buffer()) {
    auto write_buffer = static_cast<uint8*>(malloc(i2s->bytes_per_sample() * array->length()));
    if (!write_buffer) MALLOC_FAILED;
    i2s->set_write_buffer(write_buffer);
    i2s->set_write_position(0);

    // Pack the samples in the array to the correct bit width
    int shift = 0;
    switch (i2s->word_size()) {
      case 1:
        shift = 8;
        /* FALL THROUGH */
      case 2:
        for (int i = 0; i < array->length(); i++) {
          *(((int16*)write_buffer) + i) = (int16)(Smi::cast(array->at(i))->value() << shift);
        }
        break;
      case 3:
        shift = 8;
        /* FALL THROUGH */
      case 4:
        for (int i = 0; i < array->length(); i++) {
          *(((int32*)write_buffer) + i) = (int32)(Smi::cast(array->at(i))->value() << shift);
        }
        break;
    }
  }

  uword written = 0;
  esp_err_t err = i2s_write(i2s->port(), i2s->write_buffer() + i2s->write_position(),
                            array->length() * i2s->bytes_per_sample() - i2s->write_position(), &written, 0);

  if (err != ESP_OK) {
    free(i2s->write_buffer());
    i2s->set_write_buffer(null);
    return Primitive::os_error(err, process);
  }

  i2s->set_write_position(written + i2s->write_position());

  if (i2s->write_position() == array->length() * i2s->bytes_per_sample()) {
    free(i2s->write_buffer());
    i2s->set_write_buffer(null);
    return BOOL(true);
  } else {
    return BOOL(false);
  }
}

PRIMITIVE(read) {
  ARGS(I2sResource, i2s);

  Array* array = process->object_heap()->allocate_array(i2s->max_frames_per_read() * 2,
                                                        process->program()->null_object());
  if (!array) ALLOCATION_FAILED;

  Array* result = process->object_heap()->allocate_array(2, process->program()->null_object());
  if (!result) ALLOCATION_FAILED;

  result->at_put(0, array);

  int buffer_len = i2s->bytes_per_sample() * i2s->max_frames_per_read() * 2;
  void* buffer = malloc(buffer_len);
  if (!buffer) MALLOC_FAILED;

  uword read = 0;
  esp_err_t err = i2s_read(i2s->port(), buffer, buffer_len, &read, 0);
  if (err != ESP_OK) {
    free(buffer);
    return Primitive::os_error(err, process);
  }

  if (read % (i2s->bytes_per_sample() * 2) != 0) {
    fail("Broken I2S read");
  }

  uword samples = read / i2s->bytes_per_sample();
  result->at_put(1, Smi::from(static_cast<int>(samples)));

  int shift = 0;
  switch (i2s->word_size()) {
    case 1:
      shift = 8;
      /* FALL THOUGH */
    case 2:
      for (int i = 0; i < samples; i++) {
        array->at_put(i, Smi::from(*(((int16*)buffer)+i) >> shift));
      }
    case 3:
      shift = 8;
      /* FALL THOUGH */
    case 4:
      for (int i = 0; i < samples; i++) {
        array->at_put(i, Smi::from(*(((int32*)buffer)+i) >> shift));
      }
  }
  free(buffer);

  return result;
}

} // namespace toit

#endif // TOIT_FREERTOS
