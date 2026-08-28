#include "sr.h"

#include "esp_log.h"

static const char *TAG = "sr";

/* M5 待做。落地时在这里：
 *   1. I2S0 读 INMP441（PIN_MIC_SCK/WS/SD），16kHz 16bit 单声道
 *   2. esp_afe_sr_v1 做 AEC/NS/VAD，独占一核（方案 §7.2，优先级 5）
 *   3. WakeNet9 唤醒 -> MultiNet7 中文命令词：
 *        id1 "qi gan,tai gan,kai men" -> EVT_CMD_OPEN
 *        id2 "luo gan,jiang gan,guan men" -> EVT_CMD_CLOSE
 *        id3 "fu wei" -> EVT_CMD_RESET
 *   4. 模型烧在 model 分区（6MB，见 partitions.csv），
 *      idf.py 会按 sdkconfig 里选的模型自动生成 srmodels.bin
 * 依赖：idf.py add-dependency "espressif/esp-sr"
 */
void sr_start(void)
{
    ESP_LOGW(TAG, "语音识别未实现（M5）。当前只能用按键和遥控器。");
}
