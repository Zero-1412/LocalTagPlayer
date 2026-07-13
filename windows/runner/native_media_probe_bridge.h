#ifndef RUNNER_NATIVE_MEDIA_PROBE_BRIDGE_H_
#define RUNNER_NATIVE_MEDIA_PROBE_BRIDGE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <queue>
#include <set>
#include <string>
#include <thread>
#include <vector>

/**
 * Windows 原生 FFmpeg 媒体信息批处理桥。
 *
 * 单工作线程顺序调用 libavformat/libavcodec，支持 generation 取消与执行中断；
 * 该边界不访问 SQLite，也不把完整路径放入错误结果。
 */
class NativeMediaProbeBridge {
 public:
  explicit NativeMediaProbeBridge(flutter::BinaryMessenger* messenger);
  ~NativeMediaProbeBridge();

  NativeMediaProbeBridge(const NativeMediaProbeBridge&) = delete;
  NativeMediaProbeBridge& operator=(const NativeMediaProbeBridge&) = delete;

 private:
  /** 单条不可变媒体探测请求。 */
  struct Request {
    std::string video_id;
    std::string path;
    int64_t known_size = -1;
    int64_t known_modified_at = -1;
  };

  /** 一批同代请求及其异步方法通道响应。 */
  struct Job {
    int64_t generation_id = 0;
    std::vector<Request> requests;
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  };

  /** FFmpeg interrupt callback 使用的取消与超时上下文。 */
  struct InterruptState {
    std::shared_ptr<std::atomic_bool> cancelled;
    int64_t deadline_millis = 0;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void WorkerLoop();
  flutter::EncodableMap ProbeOne(const Request& request,
                                 const InterruptState& interrupt);
  bool IsGenerationCancelled(int64_t generation_id) const;
  void CancelGeneration(int64_t generation_id);
  static int InterruptCallback(void* context);
  static int64_t NowMillis();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  mutable std::mutex mutex_;
  std::condition_variable condition_;
  std::queue<Job> jobs_;
  std::set<int64_t> queued_generations_;
  std::set<int64_t> cancelled_generations_;
  std::shared_ptr<std::atomic_bool> active_cancelled_;
  int64_t active_generation_ = -1;
  std::thread worker_;
  bool shutting_down_ = false;
};

#endif  // RUNNER_NATIVE_MEDIA_PROBE_BRIDGE_H_
