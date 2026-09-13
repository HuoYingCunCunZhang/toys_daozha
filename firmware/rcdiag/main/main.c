/* 遥控器按键诊断固件（2026-09-13）
 *
 * 两件事：
 *   A. 全脚扫描：内部上拉/下拉轮流读，看谁被拉死。对照脚 = PCB 上没接东西的脚。
 *   B. 弱驱探测：把 BTN 脚设成"输入+输出"、驱动能力调到最弱(约 5mA)、输出高，
 *      然后读回自己和另外两条。
 *
 *        自己读回 0  -> 金属级死短（5mA 都顶不起来，阻抗 < 约 100 欧）
 *        自己读回 1  -> 之前的低电平来自几 kΩ 级的弱拉（助焊剂/漏电），不是死短
 *        另外两条跟着变 1 -> 三条网络是彼此短在一起，不是各自对地短
 *
 *   弱驱 + 5ms，即使真是死短也远在 C3 引脚能力之内，安全。
 *
 * 打印一律 ASCII：中文经 USB-JTAG 读回来是 ??。
 * 不深睡、不开射频，串口一直在。 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "esp_log.h"

static const char *TAG = "rcdiag";

typedef struct { gpio_num_t pin; const char *tag; } probe_t;

/* 取自 EDA 里 U1 的焊盘表（2026-09-13 读出）：
 *   pad9=GPIO0 no net / pad10=GPIO1 BTN_RST / pad11=GPIO2 no net
 *   pad12=GPIO3 BTN_DN / pad13=GPIO4 BTN_UP / pad14=3V3 / pad15=GND / pad16=5V
 *   另一排 pad1..8 = GPIO5~10/20/21，PCB 上全部无网络
 * 跳过 GPIO18/19 —— C3 的原生 USB D-/D+，一碰串口就没了。 */
static const probe_t PROBES[] = {
    { GPIO_NUM_0,  "GPIO0  pad9  (no net)"      },
    { GPIO_NUM_1,  "GPIO1  pad10 BTN_RST"       },
    { GPIO_NUM_2,  "GPIO2  pad11 (no net)"      },
    { GPIO_NUM_3,  "GPIO3  pad12 BTN_DN"        },
    { GPIO_NUM_4,  "GPIO4  pad13 BTN_UP"        },
    { GPIO_NUM_5,  "GPIO5  row2  (no net)"      },
    { GPIO_NUM_6,  "GPIO6  row2  (no net)"      },
    { GPIO_NUM_7,  "GPIO7  row2  (no net)"      },
    { GPIO_NUM_8,  "GPIO8  row2  (onboard LED)" },
    { GPIO_NUM_9,  "GPIO9  row2  (BOOT btn)"    },
    { GPIO_NUM_10, "GPIO10 row2  (no net)"      },
    { GPIO_NUM_20, "GPIO20 row2  (no net)"      },
    { GPIO_NUM_21, "GPIO21 row2  (no net)"      },
};
#define NPIN (sizeof(PROBES)/sizeof(PROBES[0]))

static const gpio_num_t BTN[3]      = { GPIO_NUM_4, GPIO_NUM_3, GPIO_NUM_1 };
static const char *BTN_NAME[3]      = { "GPIO4 BTN_UP", "GPIO3 BTN_DN", "GPIO1 BTN_RST" };

/* 换上拉/下拉之后等一下：45k 配几十 pF 只要几微秒，5ms 是十倍以上余量 */
#define SETTLE_MS 5

static void read_both(gpio_num_t pin, int *pu, int *pd)
{
    gpio_set_pull_mode(pin, GPIO_PULLUP_ONLY);
    vTaskDelay(pdMS_TO_TICKS(SETTLE_MS));
    *pu = gpio_get_level(pin);

    gpio_set_pull_mode(pin, GPIO_PULLDOWN_ONLY);
    vTaskDelay(pdMS_TO_TICKS(SETTLE_MS));
    *pd = gpio_get_level(pin);

    gpio_set_pull_mode(pin, GPIO_PULLUP_ONLY);
    vTaskDelay(pdMS_TO_TICKS(SETTLE_MS));
}

static const char *verdict(int pu, int pd)
{
    if (pu == 1 && pd == 0) return "OK(free)";
    if (pu == 0 && pd == 0) return "** PINNED LOW **";
    if (pu == 1 && pd == 1) return "** PINNED HIGH **";
    return "?? odd ??";
}

static void as_input(gpio_num_t pin)
{
    gpio_set_direction(pin, GPIO_MODE_INPUT);
    gpio_set_pull_mode(pin, GPIO_PULLUP_ONLY);
}

/* 弱驱一条，读回三条 */
static void drive_probe(int idx)
{
    gpio_num_t p = BTN[idx];
    gpio_set_direction(p, GPIO_MODE_INPUT_OUTPUT);
    gpio_set_drive_capability(p, GPIO_DRIVE_CAP_0);   /* 最弱，约 5mA */
    gpio_set_level(p, 1);
    vTaskDelay(pdMS_TO_TICKS(SETTLE_MS));

    int lv[3];
    for (int i = 0; i < 3; i++) lv[i] = gpio_get_level(BTN[i]);

    gpio_set_level(p, 0);
    as_input(p);

    printf("  drive %-14s high(weak) -> UP=%d DN=%d RST=%d   %s\n",
           BTN_NAME[idx], lv[0], lv[1], lv[2],
           lv[idx] ? "lifted => soft pull (kohm)" : "STUCK => hard short (<~100 ohm)");
}

void app_main(void)
{
    uint64_t mask = 0;
    for (size_t i = 0; i < NPIN; i++) mask |= (1ULL << PROBES[i].pin);

    gpio_config_t cfg = {
        .pin_bit_mask = mask,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&cfg));

    ESP_LOGI(TAG, "scan + weak-drive probe. PU=1 PD=0 is healthy.");

    uint32_t n = 0;
    while (1) {
        printf("\n--- round %lu ---\n", (unsigned long)++n);
        for (size_t i = 0; i < NPIN; i++) {
            int pu, pd;
            read_both(PROBES[i].pin, &pu, &pd);
            printf("  %-28s PU=%d PD=%d  %s\n", PROBES[i].tag, pu, pd, verdict(pu, pd));
        }
        printf("  -- weak drive probe --\n");
        for (int i = 0; i < 3; i++) drive_probe(i);
        fflush(stdout);

        vTaskDelay(pdMS_TO_TICKS(900));
    }
}
