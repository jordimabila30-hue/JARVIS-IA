#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Glisser-deposer de fichiers (import WhatsApp).
  canal_depot_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "jarvis/depot",
      &flutter::StandardMethodCodec::GetInstance());
  DragAcceptFiles(GetHandle(), TRUE);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::TransmettreDepot(HDROP depot) {
  flutter::EncodableList chemins;
  const UINT nombre = DragQueryFileW(depot, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < nombre; ++i) {
    const UINT longueur = DragQueryFileW(depot, i, nullptr, 0);
    std::wstring large(longueur + 1, L'\0');
    DragQueryFileW(depot, i, large.data(), longueur + 1);
    large.resize(longueur);
    const int taille = WideCharToMultiByte(CP_UTF8, 0, large.c_str(), -1,
                                           nullptr, 0, nullptr, nullptr);
    if (taille <= 1) continue;
    std::string utf8(taille - 1, '\0');
    WideCharToMultiByte(CP_UTF8, 0, large.c_str(), -1, utf8.data(), taille,
                        nullptr, nullptr);
    chemins.emplace_back(utf8);
  }
  DragFinish(depot);
  if (canal_depot_ && !chemins.empty()) {
    canal_depot_->InvokeMethod(
        "fichiersDeposes",
        std::make_unique<flutter::EncodableValue>(std::move(chemins)));
  }
}

void FlutterWindow::OnDestroy() {
  canal_depot_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DROPFILES:
      TransmettreDepot(reinterpret_cast<HDROP>(wparam));
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
