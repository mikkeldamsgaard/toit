import spi
import reader show Reader
import writer show Writer
import gpio

class Flash:
  flash_ := null
  mount_point/string

  /**
  Mounts an sdcard as a FAT file system under $mount_point on the $spi_bus.

  The $cs is the chip select pin for the sdcard holder and $frequency is the spi frequency.

  If $format is true, then format the sdcard with $max_files and $allocation_unit_size if it is not formatted.
  */
  constructor.sdcard
      --.mount_point/string
      --spi_bus/spi.Bus
      --cs/gpio.Pin
      --frequency/int=40_000_000
      --format/bool=false
      --max_files/int=5
      --allocation_unit_size/int=16384:
    if not mount_point.starts_with "/": throw "INVALID_ARGUMENT"
    flash_ = init_sdcard_ mount_point spi_bus.spi_ cs.num frequency (format?1:0) max_files allocation_unit_size

  /**
  Mounts an external NOR flash chip on the $spi_bus.

  The $cs is the chip select pin for the chip on the spi bus and $frequency is the spi frequency.

  If $format is true, then format the sdcard with $max_files and $allocation_unit_size if it is not formatted.
  */
  constructor.nor
      --.mount_point/string
      --spi_bus/spi.Bus
      --cs/gpio.Pin
      --frequency/int=40_000_000
      --format/bool=false
      --max_files/int=5
      --allocation_unit_size/int=16384:
    if not mount_point.starts_with "/": throw "INVALID_ARGUMENT"
    flash_ = init_nor_flash_ mount_point spi_bus.spi_ cs.num frequency (format?1:0) max_files allocation_unit_size

  /**
  Mounts an external NAND flash chip on the $spi_bus.

  The $cs is the chip select pin for the chip on the spi bus and $frequency is the spi frequency.

  If $format is true, then format the sdcard with $max_files and $allocation_unit_size if it is not formatted.
  */
  constructor.nand
      --.mount_point/string
      --spi_bus/spi.Bus
      --cs/gpio.Pin
      --frequency/int=40_000_000
      --format/bool=false
      --max_files/int=5
      --allocation_unit_size/int=2048:
    if not mount_point.starts_with "/": throw "INVALID_ARGUMENT"
    flash_ = init_nand_flash_ mount_point spi_bus.spi_ cs.num frequency (format?1:0) max_files allocation_unit_size

  /**
  Unmounts and releases resources for the external storage.
  */
  close:
    close_spi_flash_ flash_

init_nor_flash_ mount_point spi_bus cs frequency format max_files allocation_unit_size -> any:
  #primitive.spi_flash.init_nor_flash

init_nand_flash_ mount_point spi_bus cs frequency format max_files allocation_unit_size -> any:
  #primitive.spi_flash.init_nand_flash

init_sdcard_ mount_point spi_bus cs frequency format max_files allocation_unit_size -> any:
  #primitive.spi_flash.init_sdcard

close_spi_flash_ flash:
  #primitive.spi_flash.close
