// M5 · ESP-SR 离线语音
//
// 链路：INMP441 --I2S0--> feed_task --> AFE(NS/VAD/AGC + WakeNet9)
//                                        --> detect_task --> MultiNet7(中文) --> evt_post()
//
// 唤醒词 -> 命令词 两段式：唤醒词是乐鑫现成模型（自定义唤醒词是付费服务，方案 §7.4），
// 命令词由本文件用拼音在运行时注册，改词不用重新训练模型。
//
// 命令表见方案 §7.4；模型烧在 model 分区（6MB，partitions.csv），
// esp-sr 的 CMake 会按 sdkconfig 里勾选的模型自动生成 srmodels.bin 并跟着 idf.py flash 一起烧。
#include "sr.h"

#include "board.h"
#include "buzzer.h"
#include "events.h"

#include <stdlib.h>
#include <string.h>

#include "driver/i2s_std.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_afe_sr_models.h"
#include "esp_mn_models.h"
#include "esp_mn_speech_commands.h"
#include "esp_process_sdkconfig.h"
#include "model_path.h"

static const char *TAG = "sr";

/* ---- 可调参数 ----------------------------------------------------------- */

/* INMP441 是 24bit MSB 对齐塞在 32bit 槽里：raw >> 16 才是数学上正确的 int16。
 * 但这颗麦克风灵敏度 −26dBFS，1m 处正常说话只有 −40dBFS 左右，直接 >>16 太小。
 * 这里多给 2bit（4×）增益，超量程的部分饱和截断而不是回绕。
 * 🔴 实测阶段调这个数：日志里 data_volume 常态应在 −45 ~ −25 dBFS。
 *    偏小就减（增益变大），削顶/识别率反而下降就加。 */
#define MIC_GAIN_SHIFT   14

/* 唤醒后等命令词的窗口。超时自动回到"只等唤醒词"，省得一直跑 MultiNet */
#define MN_TIMEOUT_MS    5760

/* 方案 §7.2：sr 相关任务优先级 5，独占 core 1（core 0 让给 WiFi/ESP-NOW） */
#define SR_TASK_PRIO     5
#define SR_CORE          1

/* ---- 命令表（方案 §7.4）------------------------------------------------
 * MultiNet7 中文吃不带声调的拼音，音节之间空格。同一个 id 可以挂多条说法。
 * ⚠ 两个音节的词更容易误触发，所以必须先喊唤醒词才进这一段。 */
typedef struct {
    int id;
    const char *pinyin;
} sr_cmd_t;

#define SR_CMD_OPEN   1
#define SR_CMD_CLOSE  2
#define SR_CMD_RESET  3

static const sr_cmd_t SR_COMMANDS[] = {
    { SR_CMD_OPEN,  "qi gan"   },
    { SR_CMD_OPEN,  "tai gan"  },
    { SR_CMD_OPEN,  "kai men"  },
    { SR_CMD_CLOSE, "luo gan"  },
    { SR_CMD_CLOSE, "jiang gan"},
    { SR_CMD_CLOSE, "guan men" },
    { SR_CMD_RESET, "fu wei"   },
};

/* ---- 状态 --------------------------------------------------------------- */

static i2s_chan_handle_t s_rx;
static const esp_afe_sr_iface_t *s_afe;
static esp_afe_sr_data_t *s_afe_data;
static const esp_mn_iface_t *s_mn;
static model_iface_data_t *s_mn_data;

/* feed_task 与 detect_task 之间没有共享状态：唤醒标志只在 detect_task 里用 */

/* ---- I2S ---------------------------------------------------------------- */

static esp_err_t mic_init(void)
{
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
    ESP_RETURN_ON_ERROR(i2s_new_channel(&chan_cfg, NULL, &s_rx), TAG, "i2s_new_channel");

    /* INMP441 的 L/R 接了 GND（网表 N8）-> 数据落在左声道，所以只取左槽。
     * 32bit 槽宽是必须的：这颗麦一帧要 64 个 BCLK，16bit 槽宽收不到数据。 */
    i2s_std_config_t std_cfg = {
        .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(16000),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT,
                                                        I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = PIN_MIC_SCK,
            .ws   = PIN_MIC_WS,
            .dout = I2S_GPIO_UNUSED,
            .din  = PIN_MIC_SD,
            .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
        },
    };
    std_cfg.slot_cfg.slot_mask = I2S_STD_SLOT_LEFT;

    ESP_RETURN_ON_ERROR(i2s_channel_init_std_mode(s_rx, &std_cfg), TAG, "i2s_init_std");
    ESP_RETURN_ON_ERROR(i2s_channel_enable(s_rx), TAG, "i2s_enable");
    return ESP_OK;
}

/* ---- feed：I2S -> AFE ---------------------------------------------------- */

static void feed_task(void *arg)
{
    (void)arg;
    const int chunk = s_afe->get_feed_chunksize(s_afe_data);   /* 每声道采样点数 */
    const int ch = s_afe->get_feed_channel_num(s_afe_data);    /* "M" -> 1 */

    int32_t *raw = heap_caps_malloc(chunk * sizeof(int32_t), MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    int16_t *pcm = heap_caps_malloc(chunk * ch * sizeof(int16_t), MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (!raw || !pcm) {
        ESP_LOGE(TAG, "feed 缓冲分配失败（chunk=%d ch=%d）", chunk, ch);
        free(raw);
        free(pcm);
        vTaskDelete(NULL);
        return;
    }

    for (;;) {
        size_t got = 0;
        if (i2s_channel_read(s_rx, raw, chunk * sizeof(int32_t), &got, portMAX_DELAY) != ESP_OK) {
            continue;
        }
        const int n = (int)(got / sizeof(int32_t));
        for (int i = 0; i < n; i++) {
            int32_t v = raw[i] >> MIC_GAIN_SHIFT;
            if (v > INT16_MAX) v = INT16_MAX;          /* 饱和，不许回绕成反相噪声 */
            else if (v < INT16_MIN) v = INT16_MIN;
            pcm[i] = (int16_t)v;
        }
        for (int i = n; i < chunk; i++) pcm[i] = 0;    /* 读短了补零，帧长必须给满 */
        s_afe->feed(s_afe_data, pcm);
    }
}

/* ---- detect：AFE -> WakeNet -> MultiNet -> 事件 -------------------------- */

static void post_command(int command_id)
{
    switch (command_id) {
    case SR_CMD_OPEN:  evt_post(EVT_CMD_OPEN,  SRC_VOICE, 0); break;
    case SR_CMD_CLOSE: evt_post(EVT_CMD_CLOSE, SRC_VOICE, 0); break;
    case SR_CMD_RESET: evt_post(EVT_CMD_RESET, SRC_VOICE, 0); break;
    default: ESP_LOGW(TAG, "未知命令 id=%d", command_id); break;
    }
}

static void detect_task(void *arg)
{
    (void)arg;
    bool awake = false;   /* true = 正在等命令词 */

    for (;;) {
        afe_fetch_result_t *res = s_afe->fetch(s_afe_data);
        if (!res || res->ret_value == ESP_FAIL) continue;

        if (!awake && res->wakeup_state == WAKENET_DETECTED) {
            awake = true;
            /* 命令词那几秒里关掉 WakeNet：一是省算力，二是免得命令词里的音再触发一次唤醒 */
            s_afe->disable_wakenet(s_afe_data);
            s_mn->clean(s_mn_data);
            buzzer_play(BEEP_TICK);        /* "在听" —— 整机没喇叭，只能拿蜂鸣器应答 */
            ESP_LOGI(TAG, "唤醒（音量 %.1f dBFS），请说命令", res->data_volume);
            continue;                      /* 唤醒词那一帧本身不喂给 MultiNet */
        }

        if (!awake) continue;

        esp_mn_state_t st = s_mn->detect(s_mn_data, res->data);
        if (st == ESP_MN_STATE_DETECTING) continue;

        if (st == ESP_MN_STATE_DETECTED) {
            esp_mn_results_t *r = s_mn->get_results(s_mn_data);
            if (r && r->num > 0) {
                ESP_LOGI(TAG, "识别到 id=%d prob=%.2f (%s)",
                         r->command_id[0], (double)r->prob[0], r->string);
                post_command(r->command_id[0]);
            }
        } else {   /* ESP_MN_STATE_TIMEOUT */
            ESP_LOGI(TAG, "命令词超时，回到等唤醒");
        }

        awake = false;
        s_afe->enable_wakenet(s_afe_data);
        s_mn->clean(s_mn_data);
    }
}

/* ---- 启动 --------------------------------------------------------------- */

void sr_start(void)
{
    check_chip_config();   /* CPU 频率 / cache 配得不对时会在这里报出来 */

    if (mic_init() != ESP_OK) {
        ESP_LOGE(TAG, "麦克风初始化失败，语音不可用（按键和遥控器不受影响）");
        return;
    }

    srmodel_list_t *models = esp_srmodel_init("model");
    if (!models || models->num <= 0) {
        ESP_LOGE(TAG, "model 分区里没有模型。是不是只烧了 app？整包重烧一次 idf.py flash");
        return;
    }
    char *wn_name = esp_srmodel_filter(models, ESP_WN_PREFIX, NULL);
    char *mn_name = esp_srmodel_filter(models, ESP_MN_PREFIX, ESP_MN_CHINESE);
    if (!wn_name || !mn_name) {
        ESP_LOGE(TAG, "缺模型：wakenet=%s multinet=%s（menuconfig 里勾选后重编）",
                 wn_name ? wn_name : "无", mn_name ? mn_name : "无");
        return;
    }
    const char *ww = esp_srmodel_get_wake_words(models, wn_name);
    ESP_LOGI(TAG, "唤醒词模型 %s（%s），命令词模型 %s", wn_name, ww ? ww : "?", mn_name);

    /* 单麦，没有喇叭 -> 没有回声参考通道，输入格式就一个 "M"。
     * AEC 和 SE(阵列处理) 都用不上，afe_config_check 也会把它们关掉。 */
    afe_config_t *cfg = afe_config_init("M", models, AFE_TYPE_SR, AFE_MODE_HIGH_PERF);
    if (!cfg) {
        ESP_LOGE(TAG, "afe_config_init 失败");
        return;
    }
    cfg->aec_init = false;
    cfg->se_init = false;
    /* ⚠ 不去改 cfg->wakenet_model_name：那块内存是 afe_config_init 自己 strdup 的，
     *   换成 models 里的指针，afe_config_free 就会把模型表里的字符串给 free 掉。
     *   分区里只烧了一个唤醒词模型，默认选中的就是它。 */
    cfg->afe_perferred_core = SR_CORE;
    cfg->afe_perferred_priority = SR_TASK_PRIO;
    cfg->memory_alloc_mode = AFE_MEMORY_ALLOC_MORE_PSRAM;   /* 8MB 八线 PSRAM 就是给它用的 */
    afe_config_check(cfg);

    s_afe = esp_afe_handle_from_config(cfg);
    s_afe_data = s_afe->create_from_config(cfg);
    afe_config_free(cfg);
    if (!s_afe_data) {
        ESP_LOGE(TAG, "AFE 创建失败（多半是 PSRAM 没起来）");
        return;
    }
    s_afe->print_pipeline(s_afe_data);

    s_mn = esp_mn_handle_from_name(mn_name);
    if (!s_mn) {
        ESP_LOGE(TAG, "取不到 MultiNet 句柄：%s", mn_name);
        return;
    }
    s_mn_data = s_mn->create(mn_name, MN_TIMEOUT_MS);
    if (!s_mn_data) {
        ESP_LOGE(TAG, "MultiNet 创建失败");
        return;
    }

    /* 命令词是运行时注册的，不是编译进模型的。改词只要改上面的 SR_COMMANDS */
    ESP_ERROR_CHECK(esp_mn_commands_alloc(s_mn, s_mn_data));
    for (size_t i = 0; i < sizeof(SR_COMMANDS) / sizeof(SR_COMMANDS[0]); i++) {
        esp_mn_commands_add(SR_COMMANDS[i].id, SR_COMMANDS[i].pinyin);
    }
    esp_mn_error_t *err = esp_mn_commands_update();
    if (err && err->num > 0) {
        for (int i = 0; i < err->num; i++) {
            ESP_LOGE(TAG, "命令词 \"%s\" 没被模型接受", err->phrases[i]->string);
        }
    }
    s_mn->print_active_speech_commands(s_mn_data);

    xTaskCreatePinnedToCore(feed_task, "sr_feed", 4096, NULL, SR_TASK_PRIO, NULL, SR_CORE);
    xTaskCreatePinnedToCore(detect_task, "sr_detect", 8192, NULL, SR_TASK_PRIO, NULL, SR_CORE);

    ESP_LOGI(TAG, "语音就绪：先喊唤醒词，再说 起杆 / 落杆 / 复位");
}
