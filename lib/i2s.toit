// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the lib/LICENSE file.

import gpio
import monitor

import serial

/**
I2S Serial communication Bus, primarily used to emit sound but has a wide range of usages.

The I2S Bus works closely with the underlying hardware units, which means that
  some restrictions around buffer and write sizes are enforced.
*/
class Bus:
  i2s_ := ?
  state_/ResourceState_ ::= ?
  write_mutex_ ::= monitor.Mutex

  /** Number of encountered errors. */
  errors := 0

  /**
  Initializes the I2S bus.

  $sample_rate is the rate at which samples are written.
  $bits_per_sample is the width of each sample. It can be either 16, 24 or 32.
  $buffer_size, in number of frames to use for internal buffer. One frame is a left and right sample
  $mclk is the pin used to output the master clock. Only relevant when the I2S
    Bus is operating in master mode.
  $mclk_multiplier is the muliplier of the $sample_rate to be used for the
    master clock.
    It should be one of the 128, 256 or 384.
    It is only relevant if the $mclk is not null.
  $is_master is a flag determining if the I2S driver should run in master
    (true) or slave (false) mode.
  $use_apll use a high precision clock.
  */
  constructor
      --sck/gpio.Pin?=null
      --ws/gpio.Pin?=null
      --tx/gpio.Pin?=null
      --rx/gpio.Pin?=null
      --mclk/gpio.Pin?=null
      --sample_rate/int
      --bits_per_sample/int
      --is_master/bool=true
      --mclk_multiplier/int=256
      --use_apll/bool=false
      --buffer_size/int=32:
    sck_pin := sck ? sck.num : -1
    ws_pin := ws ? ws.num : -1
    tx_pin := tx ? tx.num : -1
    rx_pin := rx ? rx.num : -1
    mclk_pin := mclk ? mclk.num : -1
    i2s_ = i2s_create_ resource_group_ sck_pin ws_pin tx_pin rx_pin mclk_pin sample_rate bits_per_sample buffer_size is_master mclk_multiplier use_apll
    state_ = ResourceState_ resource_group_ i2s_


  /**
  Writes samples to the I2S bus. The list should be interleaved with left then right samples. A sample is a
    signed integer with a range corresponding to the bits_per_sample parameter.

  This method blocks until all samples have been written.

  Returns the number of frames written.
  */
  write samples/List -> int:
    if samples.size % 2 != 0: throw "INVALID_ARGUMENT"
    array := Array_.from samples
    write_mutex_.do:
      while true:
        done := i2s_write_ i2s_ array
        if done: return samples.size / 2

        state_.clear_state WRITE_STATE_
        state := state_.wait_for_state WRITE_STATE_ | ERROR_STATE_

        if not i2s_: throw "CLOSED"

        if state & ERROR_STATE_ != 0:
          state_.clear_state ERROR_STATE_
          errors++

    unreachable
  /**
  Read samples from the I2S bus. The returned list contains samples as left then right interleaved.

  This methods blocks until data is available.
  */
  read -> List?:
    while true:
      state := state_.wait_for_state READ_STATE_ | ERROR_STATE_
      if state & ERROR_STATE_ != 0:
        state_.clear_state ERROR_STATE_
        errors++
      else if state & READ_STATE_ != 0:
        data := i2s_read_ i2s_
        length := data[1]
        if length > 0: return data[0][0..length]
        state_.clear_state READ_STATE_
      else:
        // It was closed (disposed).
        return null

  /**
  Close the I2S bus and releases resources associated to it.
  */
  close:
    if not i2s_: return
    critical_do:
      state_.dispose
      i2s_close_ resource_group_ i2s_
      i2s_ = null

resource_group_ ::= i2s_init_

READ_STATE_  ::= 1 << 0
WRITE_STATE_ ::= 1 << 1
ERROR_STATE_ ::= 1 << 2

i2s_init_:
  #primitive.i2s.init

i2s_create_ resource_group sck_pin ws_pin tx_pin rx_pin mclk_pin sample_rate bits_per_sample buffer_size is_master mclk_multiplier use_apll:
  #primitive.i2s.create

i2s_close_ resource_group i2s:
  #primitive.i2s.close

i2s_write_ i2s samples -> int:
  #primitive.i2s.write

i2s_read_ i2s -> List:
  #primitive.i2s.read
