import spi
import reader show Reader
import writer show Writer
import gpio

class Flash:
  flash_ := null
  mount_point/string

  constructor.sdcard .mount_point/string spi_bus/spi.Bus cs/gpio.Pin:
    if not mount_point.starts_with "/": throw "INVALID_ARGUMENT"
    flash_ = init_sdcard_ mount_point spi_bus.spi_ cs.num

  constructor.flash .mount_point/string spi_bus/spi.Bus cs/gpio.Pin size/int=-1:
    if not mount_point.starts_with "/": throw "INVALID_ARGUMENT"
    print_ "$mount_point .. $cs.num .. $size"
    flash_ = init_flash_ mount_point spi_bus.spi_ cs.num size

  close:
    close_sdcard_ flash_

init_flash_ mount_point spi_bus cs size -> any:
  #primitive.spi_flash.init_flash

init_sdcard_ mount_point spi_bus cs -> any:
  #primitive.spi_flash.init_sdcard

close_sdcard_ flash:
  #primitive.spi_flash.close
