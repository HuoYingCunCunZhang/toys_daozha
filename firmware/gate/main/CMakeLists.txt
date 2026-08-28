idf_component_register(
    SRCS "main.c" "motor.c" "endstop.c" "motion.c" "input.c" "buzzer.c" "comms.c" "sr.c"
    INCLUDE_DIRS "." "../../common"
    # ⚠ 两个坑：
    #   ① 没有叫 esp_now 的组件 —— esp_now.h 在 esp_wifi 里
    #   ② IDF v6 拆散了 driver 元组件，gpio/ledc 必须点名要 esp_driver_*
    REQUIRES esp_driver_gpio esp_driver_ledc esp_adc esp_timer
             esp_wifi esp_netif esp_event nvs_flash
)
