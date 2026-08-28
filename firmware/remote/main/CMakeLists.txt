idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "." "../../common"
    # ⚠ 同主机：esp_now.h 在 esp_wifi 里；IDF v6 的 gpio/rtc_io 在 esp_driver_gpio
    REQUIRES esp_driver_gpio esp_timer esp_wifi esp_netif esp_event nvs_flash
)
