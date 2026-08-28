idf_component_register(
    SRCS "main.c" "motor.c" "endstop.c" "motion.c" "input.c" "buzzer.c" "comms.c" "sr.c"
    INCLUDE_DIRS "." "../../common"
    REQUIRES driver esp_adc esp_timer esp_wifi esp_now nvs_flash
)
